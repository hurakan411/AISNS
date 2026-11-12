// xcrun swiftc -parse-as-library AppCode/UserProgressSync.swift scripts/check_startup_sync.swift -o /private/tmp/upme-startup-checks
// /private/tmp/upme-startup-checks
import Foundation

/// Requests remain pending until explicitly answered; no server or AI API is contacted.
private final class StartupProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var pending: [StartupProtocol] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.pending.append(self)
        Self.lock.unlock()
    }
    override func stopLoading() {}

    static func take(_ method: String) -> StartupProtocol? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = pending.firstIndex(where: { $0.request.httpMethod == method }) else { return nil }
        return pending.remove(at: index)
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func reply(_ json: [String: Any], status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocolDidFinishLoading(self)
    }

    var body: [String: Any] {
        if let data = request.httpBody { return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        guard let stream = request.httpBodyStream else { return [:] }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

@main
struct StartupChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    private static func wait(_ message: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        check(condition(), message)
    }

    private static func request(_ method: String) -> StartupProtocol {
        var found: StartupProtocol?
        wait("\(method) request arrives") {
            if found == nil { found = StartupProtocol.take(method) }
            return found != nil
        }
        return found!
    }

    private static func read(_ posts: Int, followers: Int = 0, completed: Bool = true, status: Int = 200) {
        request("GET").reply(["total_posts": posts, "total_followers": followers,
                              "has_completed_onboarding": completed], status: status)
    }

    static func main() {
        let suite = "UPME.StartupChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StartupProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
        }
        let base = URL(string: "https://startup.invalid")!
        func make(_ id: String, completed: Bool = false, baseURL: URL? = nil) -> UserProgressSync {
            UserProgressSync(baseURL: baseURL ?? base, userID: id, onboardingCompleted: completed,
                             session: session, defaults: defaults)
        }

        // An absolute reward ledger repairs a missing cache without treating old rewards
        // as new gains on top of a server total that already includes them.
        let rewardRepair = make("repaired")
        rewardRepair.recoverFollowerTotal(atLeast: 200)
        rewardRepair.recoverFollowerTotal(atLeast: 100)
        check(rewardRepair.progress.followers == 200, "Ledger repair never reduces a follower total")
        rewardRepair.refresh()
        request("POST").reply(["has_completed_onboarding": false])
        read(0, followers: 200, completed: false)
        let repairedWrite = request("PUT")
        check(repairedWrite.body["total_followers"] as? Int == 200, "An already-synced reward is not added twice after the first read")
        repairedWrite.reply(["status": "success"])
        wait("Repaired state remains persisted") { make("repaired").progress.followers == 200 }

        // Both first-time and returning users can choose a screen before any response arrives.
        let fresh = make("fresh")
        check(!fresh.progress.hasCompletedOnboarding && fresh.progress.totalPosts == 0, "New user immediately has onboarding state")
        fresh.refresh()
        let delayedRegistration = request("POST")
        fresh.updateLocal(followers: 0, totalPosts: 1, onboardingCompleted: true)
        fresh.sync()
        check(fresh.progress.hasCompletedOnboarding, "Completing onboarding never waits for registration")
        check(StartupProtocol.count == 0, "No PUT or GET races the held registration")
        delayedRegistration.reply(["has_completed_onboarding": false])
        read(0, completed: false)
        let completionWrite = request("PUT")
        check(completionWrite.body["has_completed_onboarding"] as? Bool == true, "Late false cannot undo completion")
        check(completionWrite.body["total_posts"] as? Int == 1, "Completion is written after row creation")
        completionWrite.reply(["status": "success"])
        wait("Initial read completes") { fresh.hasReadServer }
        check(make("fresh").progress.hasCompletedOnboarding, "Completed onboarding persists for the next launch")

        // Existing users with a missing local flag skip provisional onboarding as soon as it is confirmed.
        let existing = make("existing")
        var received = UserProgress()
        existing.onProgressChange = { progress in
            check(Thread.isMainThread, "App state callbacks run on the main thread")
            received = progress
        }
        existing.refresh()
        request("POST").reply(["has_completed_onboarding": true])
        wait("Server completion opens Home before the stats read finishes") { received.hasCompletedOnboarding }
        check(!existing.hasReadServer, "Registration alone does not pretend to know post history")
        read(12, followers: 1_482)
        wait("Existing stats restored") { received.totalPosts == 12 }
        check(StartupProtocol.count == 0, "Reading existing stats does not overwrite them")
        let cached = make("existing")
        check(cached.progress == received, "Returning user immediately restores rank, count and completion from cache")
        check(make("existing", baseURL: URL(string: "https://other.invalid")!).progress == UserProgress(),
              "Development and production caches are isolated")
        check(make("other-user").progress == UserProgress(), "Users do not share a progress cache")

        // A post can be created during the first slow read without losing the existing baseline.
        let posting = make("posting", completed: true)
        posting.refresh()
        let held = request("POST")
        posting.updateLocal(followers: 35, totalPosts: 1, onboardingCompleted: true)
        posting.sync()
        held.reply(["has_completed_onboarding": true])
        read(12, followers: 1_482)
        let firstPostWrite = request("PUT")
        check(posting.progress.totalPosts == 13 && posting.progress.followers == 1_517,
              "Posts and followers earned during startup are added to the server baseline")
        firstPostWrite.reply(["status": "success"])
        // A newer local update must be queued behind an in-flight PUT, not overwritten by it.
        posting.updateLocal(followers: 1_552, totalPosts: 14, onboardingCompleted: true)
        posting.sync()
        let newerWrite = request("PUT")
        check(newerWrite.body["total_posts"] as? Int == 14, "Queued write uses the newest progress")
        newerWrite.reply(["status": "success"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        posting.refresh()
        let heldRead = request("GET")
        posting.updateLocal(followers: 1_587, totalPosts: 15, onboardingCompleted: true)
        heldRead.reply(["total_followers": 1_552, "total_posts": 14, "has_completed_onboarding": false])
        let concurrentWrite = request("PUT")
        check(posting.progress.totalPosts == 15 && posting.progress.followers == 1_587 && posting.progress.hasCompletedOnboarding,
              "A delayed refresh cannot roll back counts or onboarding")
        concurrentWrite.reply(["status": "success"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))

        // Offline startup and failed writes keep durable local progress for the next foreground/launch.
        let offline = make("offline", completed: true)
        offline.refresh()
        request("POST").reply([:], status: 503)
        offline.updateLocal(followers: 70, totalPosts: 2, onboardingCompleted: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        check(offline.progress.hasCompletedOnboarding && StartupProtocol.count == 0, "Failed registration keeps Home usable and does not loop")
        offline.sync()
        request("POST").reply(["has_completed_onboarding": false])
        read(0, completed: false)
        let failedWrite = request("PUT")
        failedWrite.reply([:], status: 500)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let restarted = make("offline")
        check(restarted.progress.totalPosts == 2 && restarted.progress.followers == 70 && restarted.progress.hasCompletedOnboarding,
              "Failed write survives relaunch with local progress intact")
        restarted.refresh()
        request("POST").reply(["has_completed_onboarding": false])
        read(0, completed: false)
        let retryWrite = request("PUT")
        check(retryWrite.body["total_posts"] as? Int == 2, "Retry after relaunch does not double-count local posts")
        retryWrite.reply(["status": "success"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))

        // A failed GET must not replace unknown server counts with an empty cache.
        let readFailure = make("read-failure", completed: true)
        readFailure.refresh()
        request("POST").reply(["has_completed_onboarding": true])
        read(0, status: 500)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        check(!readFailure.hasReadServer && StartupProtocol.count == 0, "Failed GET sends no zero-count PUT")
        readFailure.refresh()
        read(20, followers: 2_000)
        let repaired = request("PUT")
        check(repaired.body["total_posts"] as? Int == 20, "GET retry preserves existing history")
        repaired.reply(["status": "success"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        check(StartupProtocol.count == 0, "Every mocked request is drained")
        print("PASS: \(checks) startup and progress-sync checks; all networking mocked.")
    }
}
