import Foundation

#if canImport(PostHog)
import PostHog
#endif

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

    private init() {}

    static func start(userID: String) {
        shared.startIfPossible(userID: userID)
    }

    static func capture(_ event: String, properties: [String: Any] = [:]) {
        shared.captureIfPossible(event, properties: properties)
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
