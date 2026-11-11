// Run with:
// xcrun swiftc -parse-as-library AppCode/Analytics.swift AppCode/AppState.swift scripts/check_engagement_metrics.swift -o /private/tmp/upme-engagement-checks
// /private/tmp/upme-engagement-checks
import Foundation
import CoreGraphics

// This executable never reads/writes app files or configures the PostHog SDK.
enum DesignPreview {
    static let isActive = true
}

private final class MockRepliesProtocol: URLProtocol {
    struct Response {
        var status = 200
        var replies: [[String: Any]] = [["author_name": "Test AI", "content": "Test reply"]]
        var delay = 0.0
        var networkError = false
    }

    private static let lock = NSLock()
    private static var response = Response()
    private static var replyRequestCount = 0

    static func configure(_ next: Response) {
        lock.lock()
        response = next
        replyRequestCount = 0
        lock.unlock()
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return replyRequestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let isReplyRequest = request.url?.path == "/api/posts"
        let response = isReplyRequest ? Self.response : Response()
        if isReplyRequest { Self.replyRequestCount += 1 }
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) {
            if response.networkError {
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let http = HTTPURLResponse(url: self.request.url!, statusCode: response.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            let data = try! JSONSerialization.data(withJSONObject: ["status": "success", "replies": response.replies])
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@main
struct EngagementChecks {
    private static var checks = 0

    private static func check(_ condition: Bool, _ description: String) {
        precondition(condition, description)
        checks += 1
    }

    private static func wait(_ description: String, timeout: TimeInterval = 2, until predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(predicate(), description)
    }

    static func main() throws {
        if CommandLine.arguments.count == 3 {
            try childPersistenceCheck(mode: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }

        let suite = "UPME.EngagementChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = EngagementMetricsStore(defaults: defaults)
        store.seedPostCount(userID: "new", totalPosts: 1)
        check(store.recordNormalPost(userID: "new").numberAfterOnboarding == 1, "First real post is first")
        let restarted = EngagementMetricsStore(defaults: defaults)
        restarted.seedPostCount(userID: "new", totalPosts: 1)
        check(restarted.recordNormalPost(userID: "new").numberAfterOnboarding == 2,
              "A stale DB after interrupted AI generation cannot make the next post first")
        restarted.seedPostCount(userID: "existing", totalPosts: 12)
        check(restarted.recordNormalPost(userID: "existing").numberAfterOnboarding == 12, "Migrate existing history")
        let unknown = restarted.recordNormalPost(userID: "unknown")
        check(unknown.numberAfterOnboarding == nil && unknown.trackedNumber == 1, "Unknown history is not called first")
        restarted.seedPostCount(userID: "unknown", totalPosts: 1)
        let unknownSecond = EngagementMetricsStore(defaults: defaults).recordNormalPost(userID: "unknown")
        check(unknownSecond.numberAfterOnboarding == nil && unknownSecond.trackedNumber == 2,
              "Late history cannot turn an observed second post into first")

        check(store.markRepliesViewed(userID: "new", postFlowID: "flow-1"), "First impression recorded")
        check(!restarted.markRepliesViewed(userID: "new", postFlowID: "flow-1"), "Repeated impression suppressed")
        check(restarted.markRepliesViewed(userID: "other", postFlowID: "flow-1"), "Users have separate impression history")
        check(!restarted.markRepliesViewed(userID: "new", postFlowID: ""), "Empty flow IDs rejected")

        for mode in ["--write-persistence", "--read-persistence"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [mode, suite]
            try process.run()
            process.waitUntilExit()
            check(process.terminationStatus == 0, "Persistence survives a separate process: \(mode)")
        }

        let viewport = CGRect(x: 0, y: 0, width: 390, height: 700)
        check(AnalyticsReplyVisibility.isVisible(frame: CGRect(x: 20, y: 100, width: 300, height: 100), viewport: viewport), "Visible reply")
        for frame in [CGRect.zero, .null, .infinite,
                      CGRect(x: 20, y: 100, width: 300, height: 0),
                      CGRect(x: 20, y: 900, width: 300, height: 100),
                      CGRect(x: 500, y: 100, width: 300, height: 100),
                      CGRect(x: 389, y: 100, width: 300, height: 100),
                      CGRect(x: 20, y: 699, width: 300, height: 100)] {
            check(!AnalyticsReplyVisibility.isVisible(frame: frame, viewport: viewport), "Hidden/invalid frame rejected: \(frame)")
        }
        check(!AnalyticsReplyVisibility.isVisible(frame: viewport, viewport: .zero), "Zero viewport rejected")

        check(URLProtocol.registerClass(MockRepliesProtocol.self), "Mock networking installed")
        defer {
            URLProtocol.unregisterClass(MockRepliesProtocol.self)
            UserDefaults.standard.removeObject(forKey: "posthog.engagement.v1.design-preview")
        }

        // Failed prefetch must not be cached as a successful empty response.
        MockRepliesProtocol.configure(.init(status: 503))
        let failedPrefetch = AppState(restorePersistedState: false)
        failedPrefetch.prefetchOnboardingReplies(text: "test")
        wait("Prefetch failure exposed") { failedPrefetch.onboardingReplyError != nil }
        MockRepliesProtocol.configure(.init())
        failedPrefetch.submitOnboardingPost(text: "test")
        wait("Submission retries failed prefetch") { failedPrefetch.posts.first?.replies.count == 1 }
        check(failedPrefetch.onboardingReplyError == nil, "Recovery clears error")
        check(failedPrefetch.onboardingFirstReplyReceived, "Recovered reply unlocks onboarding progress")
        failedPrefetch.completeOnboarding()

        MockRepliesProtocol.configure(.init(delay: 0.1))
        let inFlight = AppState(restorePersistedState: false)
        inFlight.prefetchOnboardingReplies(text: "test")
        inFlight.submitOnboardingPost(text: "test")
        wait("In-flight prefetch reused") { inFlight.posts.first?.replies.count == 1 }
        check(MockRepliesProtocol.requestCount == 1, "No duplicate request during prefetch")
        inFlight.completeOnboarding()

        MockRepliesProtocol.configure(.init(replies: [], delay: 0.05))
        let emptyResponse = AppState(restorePersistedState: false)
        emptyResponse.prefetchOnboardingReplies(text: "test")
        emptyResponse.submitOnboardingPost(text: "test")
        wait("An empty success response becomes a retryable error") { emptyResponse.onboardingReplyError != nil }
        MockRepliesProtocol.configure(.init())
        emptyResponse.retryOnboardingReplies()
        wait("Explicit retry recovers empty response") { emptyResponse.posts.first?.replies.count == 1 }
        check(emptyResponse.onboardingReplyError == nil, "Retry clears failure")
        emptyResponse.completeOnboarding()

        MockRepliesProtocol.configure(.init(networkError: true))
        let networkFailure = AppState(restorePersistedState: false)
        networkFailure.prefetchOnboardingReplies(text: "test")
        networkFailure.submitOnboardingPost(text: "test")
        wait("Terminal network failure exposed", timeout: 9) { networkFailure.onboardingReplyError != nil }
        check(MockRepliesProtocol.requestCount == 3, "Network retries bounded to three attempts")
        networkFailure.completeOnboarding()
        check(networkFailure.hasCompletedOnboarding && !networkFailure.isInOnboarding,
              "A user can continue after a terminal network failure")

        MockRepliesProtocol.configure(.init(status: 503))
        let skipped = AppState(restorePersistedState: false)
        skipped.prefetchOnboardingReplies(text: "test")
        skipped.submitOnboardingPost(text: "test")
        wait("Failure before leaving onboarding") { skipped.onboardingReplyError != nil }
        MockRepliesProtocol.configure(.init(delay: 0.1))
        skipped.retryOnboardingReplies()
        skipped.completeOnboarding()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(skipped.posts.first?.replies.isEmpty == true && !skipped.isInOnboarding,
              "Late response cannot resume onboarding after leaving")

        print("PASS: \(checks) engagement and onboarding checks; all networking mocked.")
    }

    private static func childPersistenceCheck(mode: String, suite: String) throws {
        let defaults = UserDefaults(suiteName: suite)!
        let store = EngagementMetricsStore(defaults: defaults)
        if mode == "--write-persistence" {
            store.seedPostCount(userID: "process", totalPosts: 1)
            check(store.recordNormalPost(userID: "process").numberAfterOnboarding == 1, "Child first post")
            check(store.markRepliesViewed(userID: "process", postFlowID: "saved-flow"), "Child first impression")
            defaults.synchronize()
        } else {
            check(store.recordNormalPost(userID: "process").numberAfterOnboarding == 2, "New process remembers first post")
            check(!store.markRepliesViewed(userID: "process", postFlowID: "saved-flow"), "New process remembers viewed reply")
        }
    }
}
