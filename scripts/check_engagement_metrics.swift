// Run with:
// xcrun swiftc -D DEBUG -parse-as-library AppCode/Analytics.swift AppCode/UserProgressSync.swift AppCode/AppState.swift scripts/check_engagement_metrics.swift -o /private/tmp/upme-engagement-checks
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
        func reply(_ text: String, user: Bool = false, hater: Bool = false) -> Reply {
            Reply(authorName: "Test", text: text, img: "", isHater: hater, isDefender: false, isUserReply: user)
        }
        let excluded = PostModel(content: "current", imageData: nil, likes: 0,
                                 replies: [reply("current-only")], time: "")
        let history = [excluded, PostModel(content: "old", imageData: nil, likes: 0, replies: [
            reply("User's private words", user: true), reply("critic", hater: true),
            reply("  A recent reply  "), reply("a recent reply"), reply(String(repeating: "x", count: 400))
        ], replyThreads: [ReplyThread(targetReplyID: UUID(), replies: [reply("from a thread")])], time: "")]
        let context = recentAIReplyTexts(from: history, excluding: excluded.id)
        check(context.count == 3 && context.contains("from a thread"), "Style history includes AI thread replies and removes duplicates")
        check(!context.contains("User's private words") && !context.contains("critic") && !context.contains("current-only"),
              "Style history excludes the user's text, critics and the current post")
        check(context.allSatisfy { $0.count <= 160 }, "Style history limits each excerpt to 160 characters")
        let manyPosts = (0..<5).map { index in
            PostModel(content: "", imageData: nil, likes: 0,
                      replies: (0..<10).map { reply("Post \(index), reply \($0)") }, time: "")
        }
        let sampled = recentAIReplyTexts(from: manyPosts)
        check(sampled.count == 8 && sampled.contains("Post 2, reply 0"), "Eight excerpts are sampled across several posts")
        let viralState = AppState(restorePersistedState: false)
        viralState.followers = 60
        let viralPost = PostModel(content: "viral", imageData: nil, likes: 0, replies: [], time: "")
        let otherPost = PostModel(content: "normal", imageData: nil, likes: 0, replies: [], time: "")
        viralState.posts = [viralPost, otherPost]
        viralState.beginPostReaction(postID: viralPost.id, replies: (0..<10).map { reply("viral \($0)") },
                                     response: ["is_viral": true, "rank": 1, "likes": 1400, "follower_gain": 200])
        let began = viralState.posts[0].reaction!.startedAt
        check(viralState.posts[0].replies.count == 1 && viralState.followers == 60, "First reply arrives immediately without an early rank-up")
        check(!viralState.isViralRevealed(viralState.posts[0]), "Viral badge waits for the surprise")
        viralState.updatePostReactions(at: began.addingTimeInterval(5))
        check(viralState.isViralAnimating(viralState.posts[0]) && viralState.displayedLikes(for: viralState.posts[0]) > 0,
              "At five seconds the viral reveal and count-up are active")
        check(viralState.posts[1].replies.isEmpty && viralState.posts[1].likes == 0, "Reactions belong to their post, not the top row")
        // A second post can receive its response while the first animation is in progress.
        viralState.beginPostReaction(postID: otherPost.id, replies: [reply("normal 1"), reply("normal 2")],
                                     response: ["is_viral": false, "rank": 1, "likes": 100, "follower_gain": 30])
        viralState.updatePostReactions(at: began.addingTimeInterval(60))
        check(viralState.posts[0].likes == 1400 && viralState.posts[0].replies.count == 10, "Viral outcome reaches its exact total")
        check(viralState.posts[1].likes == 100 && viralState.posts[1].replies.count == 2 && viralState.followers == 290,
              "Concurrent posts receive separate rewards exactly once")
        viralState.updatePostReactions(at: began.addingTimeInterval(120))
        check(viralState.followers == 290 && !viralState.hasPendingReplies, "Repeated foreground updates do not re-credit rewards")
        let restoredViral = AppState(restorePersistedState: false)
        restoredViral.posts = try JSONDecoder().decode([PostModel].self, from: JSONEncoder().encode(viralState.posts))
        restoredViral.followers = 60
        restoredViral.restorePostReactions()
        restoredViral.restorePostReactions()
        check(restoredViral.followers == 290 && restoredViral.posts[0].replies.count == 10,
              "A persisted credit ledger repairs an interrupted follower write without duplication")
        let interrupted = AppState(restorePersistedState: false)
        interrupted.posts = [PostModel(content: "test", imageData: nil, likes: 0, replies: [], time: "")]
        interrupted.beginPostReaction(postID: interrupted.posts[0].id, replies: [reply("one"), reply("two")],
                                      response: ["is_viral": true, "rank": 1, "likes": 1400, "follower_gain": 200])
        let restartedPost = AppState(restorePersistedState: false)
        restartedPost.posts = try JSONDecoder().decode([PostModel].self, from: JSONEncoder().encode(interrupted.posts))
        restartedPost.restorePostReactions()
        restartedPost.restorePostReactions()
        check(restartedPost.posts[0].replies.count == 2 && restartedPost.posts[0].likes == 1400 && restartedPost.followers == 200,
              "Relaunch settles saved pending replies without regenerating or replaying")
        let legacy = Data("{\"content\":\"old\",\"likes\":12,\"time\":\"Now\"}".utf8)
        check(try JSONDecoder().decode(PostModel.self, from: legacy).reaction == nil, "Old saved posts remain readable")
        let foreignRewards = AppState(restorePersistedState: false)
        var foreignPost = PostModel(content: "dev post", imageData: nil, likes: 0, replies: [], time: "")
        foreignPost.reaction = PostReaction(environment: "https://other-environment.invalid", isViral: true,
                                           rank: 1, targetLikes: 1400, followerGain: 200, startedAt: Date(),
                                           replyOffsets: [0], remainingReplies: [reply("saved reply")])
        foreignRewards.followers = 10
        foreignRewards.posts = [foreignPost]
        foreignRewards.restorePostReactions()
        check(foreignRewards.followers == 10 && foreignRewards.posts[0].replies.count == 1,
              "Development post rewards are never credited to a production environment")
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
        check(inFlight.posts.first?.reaction?.isViral == true, "Onboarding always starts a viral reaction")
        check(inFlight.posts.first?.reaction?.targetLikes == 10_500_000 && inFlight.posts.first?.reaction?.followerGain == 1_500_000,
              "Onboarding uses the virtual rank-10 maximum times five")
        inFlight.completeOnboarding()
        check(inFlight.followers == 0 && inFlight.posts.first?.reaction?.followersAfter == 0,
              "Demo followers are never credited to the real account")

        MockRepliesProtocol.configure(.init(replies: (0..<32).map { ["author_name": "AI\($0)", "content": "Reply \($0)"] }))
        let earlyExit = AppState(restorePersistedState: false)
        earlyExit.prefetchOnboardingReplies(text: "test")
        earlyExit.submitOnboardingPost(text: "test")
        wait("Guaranteed viral batch arrives") { earlyExit.onboardingFirstReplyReceived }
        check(earlyExit.onboardingExpectedReplies == 32 && MockRepliesProtocol.requestCount == 1,
              "All onboarding replies arrive in one request")
        earlyExit.completeOnboarding()
        check(earlyExit.posts.first?.replies.count == 32 && earlyExit.posts.first?.likes == 10_500_000,
              "Exiting onboarding retains every generated reply and the final viral likes")
        earlyExit.restorePostReactions()
        check(earlyExit.followers == 0, "Restoring the onboarding post cannot credit demonstration followers")

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

        #if DEBUG
        let source = AppState(restorePersistedState: false)
        source.hasCompletedOnboarding = true
        source.followers = 1_482
        source.totalPosts = 89
        source.userName = "Replay source"
        source.appLanguage = .english
        source.posts = [PostModel(content: "Real post", imageData: nil, likes: 128, replies: [], time: "")]
        let postEncoder = JSONEncoder()
        postEncoder.outputFormatting = [.sortedKeys]
        let sourcePosts = try postEncoder.encode(source.posts)
        let replay = AppState.onboardingReplay(from: source)
        check(replay.isDebugOnboardingReplay && !replay.hasCompletedOnboarding && replay.posts.isEmpty,
              "Replay opens as a fresh, separate onboarding session")
        check(replay.userName == source.userName && replay.appLanguage == .english,
              "Replay inherits the display name and selected language")
        MockRepliesProtocol.configure(.init(replies: (0..<32).map { ["author_name": "AI\($0)", "content": "Reply \($0)"] }))
        replay.prefetchOnboardingReplies(text: "Replay test")
        replay.submitOnboardingPost(text: "Replay test")
        wait("Replay uses the actual onboarding flow") { replay.onboardingFirstReplyReceived }
        replay.completeOnboarding()
        check(replay.posts.first?.reaction?.isViral == true && replay.posts.first?.replies.count == 32,
              "Replay includes the guaranteed viral post")
        check(source.followers == 1_482 && source.totalPosts == 89 && source.hasCompletedOnboarding,
              "Completing replay preserves the real account progress")
        check(try postEncoder.encode(source.posts) == sourcePosts, "Completing replay preserves real posts")
        replay.cancelOnboardingReplay()
        MockRepliesProtocol.configure(.init(delay: 0.15))
        let canceledReplay = AppState.onboardingReplay(from: source)
        canceledReplay.prefetchOnboardingReplies(text: "Canceled test")
        canceledReplay.submitOnboardingPost(text: "Canceled test")
        wait("Replay request begins") { MockRepliesProtocol.requestCount == 1 }
        canceledReplay.cancelOnboardingReplay()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        canceledReplay.submitOnboardingPost(text: "Late callback")
        check(canceledReplay.posts.first?.replies.isEmpty == true && MockRepliesProtocol.requestCount == 1,
              "Closing replay blocks late replies, retries and delayed resubmission")
        #endif

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
