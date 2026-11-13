import Foundation
import ImageIO

enum AvatarImageError: Error {
    case invalidURL, invalidResponse, invalidImage
}

/// No URLCache, disk files or permanent image store. Images live only in visible views.
final class AvatarImageLoader {
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        return config
    }

    static let shared = AvatarImageLoader(session: URLSession(configuration: configuration()))
    private let session: URLSession
    private let retryDelays: [UInt64]

    init(session: URLSession, retryDelays: [UInt64] = [1_000_000_000, 3_000_000_000]) {
        self.session = session
        self.retryDelays = Array(retryDelays.prefix(2))
    }

    /// Old saved CDN links can retry through Picsum with the SAME image ID, never a random photo.
    static func retryURL(for url: URL) -> URL {
        guard url.host?.lowercased() == "fastly.picsum.photos",
              url.path.range(of: #"^/id/[0-9]+/[0-9]+/[0-9]+\.(jpg|jpeg|webp)$"#, options: .regularExpression) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "picsum.photos"
        parts.queryItems = parts.queryItems?.filter { $0.name != "hmac" }
        return parts.url ?? url
    }

    func load(_ rawURL: String) async throws -> Data {
        guard let original = URL(string: rawURL), original.scheme?.lowercased() == "https",
              original.host != nil else { throw AvatarImageError.invalidURL }
        for attempt in 0...retryDelays.count {
            try Task.checkCancellation()
            do {
                let url = attempt == 0 ? original : Self.retryURL(for: original)
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      http.mimeType?.lowercased().hasPrefix("image/") == true else {
                    throw AvatarImageError.invalidResponse
                }
                guard data.count <= 2_000_000,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw AvatarImageError.invalidImage
                }
                return data
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .cancelled { throw error }
                guard attempt < retryDelays.count else { throw error }
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }
        throw AvatarImageError.invalidImage
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

struct AIAvatarImage: View {
    let url: String
    var isHater = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var loadedURL: String?
    @State private var failed = false
    @State private var retryGeneration = 0

    var body: some View {
        Group {
            if let image, loadedURL == url {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "person.circle.fill").resizable()
                    .foregroundStyle(isHater ? Color.gray : Theme.hotPink)
            } else {
                Circle().fill(isHater ? Color.gray : Theme.deepPurple)
            }
        }
        .task(id: "\(url)#\(retryGeneration)") {
            image = nil
            loadedURL = nil
            failed = false
            guard !DesignPreview.isActive else { failed = true; return }
            do {
                let data = try await AvatarImageLoader.shared.load(url)
                try Task.checkCancellation()
                image = UIImage(data: data)
                loadedURL = url
                failed = image == nil
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && image == nil { retryGeneration += 1 }
        }
        .accessibilityHidden(true)
    }
}
#endif
