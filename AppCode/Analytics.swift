import Foundation
import CoreGraphics

#if canImport(PostHog)
import PostHog
#endif

/// AI生成の成否に依存しない、端末内の計測用記録。
final class EngagementMetricsStore {
    struct PostSequence {
        let trackedNumber: Int
        let numberAfterOnboarding: Int?
    }

    private struct Progress: Codable {
        var normalPostCount: Int?
        var trackedPostCount = 0
        var viewedPostFlowIDs: [String] = []
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func seedPostCount(userID: String, totalPosts: Int) {
        guard !userID.isEmpty, totalPosts >= 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        var progress = load(userID: userID)
        let historicalCount = max(totalPosts - 1, 0)
        if let currentCount = progress.normalPostCount {
            progress.normalPostCount = max(currentCount, historicalCount)
        } else if progress.trackedPostCount == 0 {
            progress.normalPostCount = historicalCount
        }
        // 更新前の履歴が不明なまま投稿した既存ユーザーには、初回と断定しない。
        save(progress, userID: userID)
    }

    func recordNormalPost(userID: String) -> PostSequence {
        lock.lock()
        defer { lock.unlock() }
        var progress = load(userID: userID)
        progress.trackedPostCount += 1
        if let count = progress.normalPostCount {
            progress.normalPostCount = count + 1
        }
        save(progress, userID: userID)
        return PostSequence(trackedNumber: progress.trackedPostCount, numberAfterOnboarding: progress.normalPostCount)
    }

    func markRepliesViewed(userID: String, postFlowID: String) -> Bool {
        guard !userID.isEmpty, !postFlowID.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        var progress = load(userID: userID)
        guard !progress.viewedPostFlowIDs.contains(postFlowID) else { return false }
        progress.viewedPostFlowIDs.append(postFlowID)
        // 投稿は端末に直近5件だけ残るため、十分な履歴を保ちつつ保存量を制限する。
        progress.viewedPostFlowIDs = Array(progress.viewedPostFlowIDs.suffix(512))
        save(progress, userID: userID)
        return true
    }

    private func load(userID: String) -> Progress {
        guard let data = defaults.data(forKey: key(userID: userID)),
              let progress = try? JSONDecoder().decode(Progress.self, from: data) else { return Progress() }
        return progress
    }

    private func save(_ progress: Progress, userID: String) {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: key(userID: userID))
        }
    }

    private func key(userID: String) -> String {
        "posthog.engagement.v1.\(userID)"
    }
}

enum AnalyticsReplyVisibility {
    static func isVisible(frame: CGRect, viewport: CGRect) -> Bool {
        let values = [frame.origin.x, frame.origin.y, frame.width, frame.height,
                      viewport.origin.x, viewport.origin.y, viewport.width, viewport.height]
        guard !frame.isNull, !frame.isInfinite, !viewport.isNull, !viewport.isInfinite,
              values.allSatisfy({ $0.isFinite }),
              frame.width > 0, frame.height > 0,
              viewport.width > 0, viewport.height > 0 else { return false }
        let intersection = frame.intersection(viewport)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        return intersection.width >= min(60, frame.width * 0.25)
            && intersection.height >= min(60, frame.height * 0.25)
    }
}

/// PostHogへの計測を一箇所に集約するラッパー。
/// 投稿本文・画像・プロフィール情報はイベントに含めない。
final class UPMEAnalytics {
    static let shared = UPMEAnalytics()

    private static let projectTokenKeys = ["PostHogProjectToken", "POSTHOG_PROJECT_TOKEN"]
    private static let hostKey = "PostHogHost"
    private static let dailyActiveDateKey = "posthog.lastDailyActiveDate"

    private var isConfigured = false
    private var identifiedUserID: String?
    private var isSessionActive = false
    private let engagementStore = EngagementMetricsStore()

    private init() {}

    static func start(userID: String) {
        shared.startIfPossible(userID: userID)
    }

    static func capture(_ event: String, properties: [String: Any] = [:]) {
        shared.captureIfPossible(event, properties: properties)
    }

    static func captureAIRepliesViewed(postFlowID: String, properties: [String: Any]) {
        guard shared.isConfigured,
              let userID = shared.identifiedUserID,
              shared.engagementStore.markRepliesViewed(userID: userID, postFlowID: postFlowID) else { return }
        shared.captureIfPossible("ai_replies_viewed", properties: properties)
    }

    static func seedPostCount(userID: String, totalPosts: Int) {
        shared.engagementStore.seedPostCount(userID: userID, totalPosts: totalPosts)
    }

    static func recordNormalPost(userID: String) -> [String: Any] {
        let sequence = shared.engagementStore.recordNormalPost(userID: userID)
        var properties: [String: Any] = [
            "tracked_post_number": sequence.trackedNumber,
            "post_number_is_known": sequence.numberAfterOnboarding != nil
        ]
        if let number = sequence.numberAfterOnboarding {
            properties["post_number_after_onboarding"] = number
            properties["is_first_post_after_onboarding"] = number == 1
        }
        return properties
    }

    /// foregroundへ戻るたびに呼び出し、セッションと日次アクティブを記録する。
    static func recordActiveSession(userID: String) {
        shared.startIfPossible(userID: userID)
        guard shared.isConfigured else { return }

        if !shared.isSessionActive {
            shared.captureIfPossible("session_start")
            shared.isSessionActive = true
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: dailyActiveDateKey) != today {
            defaults.set(today, forKey: dailyActiveDateKey)
            shared.captureIfPossible("daily_active", properties: ["local_date": today])
        }
    }

    static func markSessionInactive() {
        shared.isSessionActive = false
    }

    private func startIfPossible(userID: String) {
        guard !DesignPreview.isActive else { return }
        guard UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy"), !userID.isEmpty else { return }

        #if canImport(PostHog)
        if !isConfigured {
            let token = Self.projectToken()
            guard !token.isEmpty,
                  !token.uppercased().contains("REPLACE"),
                  !token.uppercased().contains("PASTE_") else { return }

            let host = (Bundle.main.object(forInfoDictionaryKey: Self.hostKey) as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "https://us.i.posthog.com"
            let config = PostHogConfig(projectToken: token, host: host)
            PostHogSDK.shared.setup(config)
            isConfigured = true
        }

        if identifiedUserID != userID {
            PostHogSDK.shared.identify(userID)
            identifiedUserID = userID
        }
        #else
        _ = userID
        #endif
    }

    private func captureIfPossible(_ event: String, properties: [String: Any] = [:]) {
        guard isConfigured else { return }

        #if canImport(PostHog)
        PostHogSDK.shared.capture(event, properties: properties)
        #else
        _ = event
        _ = properties
        #endif
    }

    private static func projectToken() -> String {
        for key in projectTokenKeys {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               isUsableToken(value) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = ProcessInfo.processInfo.environment[key],
               isUsableToken(value) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func isUsableToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.uppercased().contains("REPLACE")
            && !trimmed.uppercased().contains("PASTE_")
    }
}
