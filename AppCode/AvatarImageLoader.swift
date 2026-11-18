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

    /// Repair saved URLs issued with the development database's origin, keeping the image number.
    static func storageURL(for url: URL) -> URL {
        guard url.scheme == "https", url.host == "xfnircfralbgkslbvaov.supabase.co",
              url.path.range(of: #"^/storage/v1/object/public/images/avatar-[0-9]+\.jpg$"#,
                             options: .regularExpression) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "woxotmmgvabizjgizwow.supabase.co"
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? url
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

    /// A deterministic backup for an unavailable Picsum origin, including saved CDN URLs.
    /// This uses the app's existing photo provider, with no bundled or disk-cached images.
    static func backupURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "picsum.photos" || host == "fastly.picsum.photos" else { return nil }
        let photos = [
            "photo-1494790108377-be9c29b29330",
            "photo-1500648767791-00dcc994a43e",
            "photo-1554151228-14d9def656e4",
            "photo-1514888286974-6c03e2ca1dba",
            "photo-1438761681033-6461ffad8d80"
        ]
        // Swift's Hasher is randomized between launches; use a stable hash instead.
        let identity = url.path.components(separatedBy: "/").filter { !$0.isEmpty }.prefix(2).joined(separator: "/")
        let hash = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return URL(string: "https://images.unsplash.com/\(photos[Int(hash % UInt64(photos.count))])?w=150&h=150&fit=crop")
    }

    func load(_ rawURL: String) async throws -> Data {
        guard let parsed = URL(string: rawURL), parsed.scheme?.lowercased() == "https",
              parsed.host != nil else { throw AvatarImageError.invalidURL }
        let original = Self.storageURL(for: parsed)
        for attempt in 0...retryDelays.count {
            try Task.checkCancellation()
            do {
                let backup = Self.backupURL(for: original)
                let url = attempt == 0 ? original : (backup ?? Self.retryURL(for: original))
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                         timeoutInterval: backup != nil && attempt == 0 ? 5 : 10)
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
    @Environment(\.designTemplate) private var template
    let url: String
    var isHater = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var loadedURL: String?
    @State private var failed = false
    @State private var retryGeneration = 0

    var body: some View {
        // Keep task ownership stable when loading / failure / image branches change.
        ZStack {
            if let image, loadedURL == url {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                if template == .lofi {
                    PixelGlyph(name: "person.fill").fill(isHater ? Color.gray : Theme.lavender,
                                                         style: FillStyle(antialiased: false)).padding(6)
                } else {
                Image(systemName: "person.circle.fill").resizable()
                    .foregroundStyle(isHater ? Color.gray : Theme.hotPink)
                }
            } else {
                Circle().fill(isHater ? Color.gray : Theme.deepPurple)
            }
        }
        .task(id: "\(url)#\(retryGeneration)") {
            guard image == nil || loadedURL != url else { return }
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
