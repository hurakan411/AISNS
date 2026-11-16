// xcrun swiftc -parse-as-library AppCode/AvatarImageLoader.swift scripts/check_avatar_images.swift -o /private/tmp/upme-avatar-checks
import Foundation
import CoreGraphics
import ImageIO

final class AvatarMockProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var mime = "image/png"
        var data = Data()
        var error: URLError?
    }
    static let lock = NSLock()
    static var replies: [Reply] = []
    static var requests: [URLRequest] = []
    static func configure(_ responses: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        replies = responses; requests = []
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let reply = Self.replies.count > 1 ? Self.replies.removeFirst() : Self.replies[0]
        Self.lock.unlock()
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct AvatarChecks {
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let loader = AvatarImageLoader.shared
            let urls = ["01", "19", "27", "51", "159", "200"].map {
                "https://woxotmmgvabizjgizwow.supabase.co/storage/v1/object/public/images/avatar-\($0).jpg"
            } + ["https://xfnircfralbgkslbvaov.supabase.co/storage/v1/object/public/images/avatar-159.jpg"]
            try await withThrowingTaskGroup(of: Int.self) { group in
                for url in urls {
                    group.addTask { try await loader.load(url).count }
                }
                for try await bytes in group {
                    print("Live avatar decoded: \(bytes) bytes")
                }
            }
            print("PASS: \(urls.count) Storage downloads, including repair of a saved wrong-origin URL; no image files saved.")
            return
        }
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name); checks += 1
        }
        let data = NSMutableData()
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        check(CGImageDestinationFinalize(destination), "Valid synthetic PNG fixture")
        let png = data as Data
        let config = AvatarImageLoader.configuration()
        check(config.urlCache == nil, "No disk or URL response cache")
        check(config.requestCachePolicy == .reloadIgnoringLocalCacheData, "No implicit local-cache reads")
        check(config.httpMaximumConnectionsPerHost == 4, "Bounded per-host connection count")
        config.protocolClasses = [AvatarMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session, retryDelays: [0, 0])
        let seed = "https://picsum.photos/seed/user24/150/150"

        let storagePath = "/storage/v1/object/public/images/avatar-159.jpg"
        let brokenStorage = "https://xfnircfralbgkslbvaov.supabase.co" + storagePath
        AvatarMockProtocol.configure([.init(data: png)])
        _ = try await loader.load(brokenStorage)
        check(AvatarMockProtocol.requests.first?.url?.absoluteString ==
              "https://woxotmmgvabizjgizwow.supabase.co" + storagePath,
              "Saved wrong Storage origin is repaired before the first request, preserving image identity")
        let otherStorage = URL(string: "https://example.com" + storagePath)!
        check(AvatarImageLoader.storageURL(for: otherStorage) == otherStorage,
              "Unrelated Storage origins are preserved")

        AvatarMockProtocol.configure([.init(status: 503), .init(error: URLError(.timedOut)), .init(data: png)])
        let recovered = try await loader.load(seed)
        check(recovered == png && AvatarMockProtocol.requests.count == 3, "503 then timeout recovers on third attempt")
        let backup = AvatarImageLoader.backupURL(for: URL(string: seed)!)!
        check(AvatarMockProtocol.requests[0].url?.absoluteString == seed, "Original image is requested first")
        check(AvatarMockProtocol.requests.dropFirst().allSatisfy { $0.url == backup }, "Unavailable Picsum uses a stable alternate provider")
        check(AvatarMockProtocol.requests[0].timeoutInterval == 5, "Unavailable origin has a short timeout")

        AvatarMockProtocol.configure([.init(data: png)])
        _ = try await loader.load(seed)
        check(AvatarMockProtocol.requests.count == 1, "Success needs no retry")

        AvatarMockProtocol.configure([.init(status: 503)])
        do { _ = try await loader.load(seed); fatalError("503 accepted") } catch {}
        check(AvatarMockProtocol.requests.count == 3, "Permanent failure stops at three attempts")

        AvatarMockProtocol.configure([.init(mime: "text/html", data: Data("<html>error</html>".utf8))])
        do { _ = try await loader.load(seed); fatalError("HTML accepted") } catch {}
        check(AvatarMockProtocol.requests.count == 3, "HTTP 200 HTML is not treated as an image")

        AvatarMockProtocol.configure([.init(data: Data("not an image".utf8))])
        do { _ = try await loader.load(seed); fatalError("Invalid image accepted") } catch {}
        check(AvatarMockProtocol.requests.count == 3, "Invalid image data is rejected")

        AvatarMockProtocol.configure([.init(error: URLError(.cancelled))])
        do { _ = try await loader.load(seed); fatalError("Cancellation ignored") } catch {}
        check(AvatarMockProtocol.requests.count == 1, "Cancellation does not retry")

        AvatarMockProtocol.configure([.init(data: png)])
        do { _ = try await loader.load("file:///private/tmp/avatar.png"); fatalError("File URL accepted") } catch {}
        check(AvatarMockProtocol.requests.isEmpty, "Non-HTTPS URLs are rejected without networking")

        let cdn = URL(string: "https://fastly.picsum.photos/id/237/150/150.jpg?blur=2&hmac=old")!
        let alternative = AvatarImageLoader.retryURL(for: cdn)
        check(alternative.host == "picsum.photos" && alternative.path == cdn.path, "CDN recovery keeps exact image ID and size")
        check(alternative.query == "blur=2", "CDN recovery discards stale signature but retains image options")
        check(AvatarImageLoader.retryURL(for: URL(string: seed)!).absoluteString == seed, "Stable seed URL is not rewritten")
        let unrelated = URL(string: "https://example.com/photo.jpg?token=private")!
        check(AvatarImageLoader.retryURL(for: unrelated) == unrelated, "Other services are unchanged")
        check(AvatarImageLoader.backupURL(for: unrelated) == nil, "Unrelated providers are not replaced")
        check(backup == AvatarImageLoader.backupURL(for: URL(string: seed)!), "Backup identity is stable")
        let newSignature = URL(string: "https://fastly.picsum.photos/id/237/150/150.jpg?hmac=new")!
        check(AvatarImageLoader.backupURL(for: cdn) == AvatarImageLoader.backupURL(for: newSignature), "Signed URL changes preserve backup identity")
        print("PASS: \(checks) avatar image checks; networking mocked, no disk image storage.")
    }
}
