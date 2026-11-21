import Foundation
import Combine
import CryptoKit
import UserNotifications
import UIKit

struct ReminderRegular: Equatable {
    let id: String
    let name: String
    let characterID: String

    static func characterID(_ saved: String?, regularID: String) -> String {
        if let saved, (1...30).contains(where: { saved == String(format: "v1-%02d", $0) }) { return saved }
        // Same legacy fallback as backend/character_catalog.py, without sending an API request.
        let digest = SHA256.hash(data: Data(("regular:" + regularID).utf8))
        let slot = digest.prefix(8).reduce(0) { ($0 * 256 + Int($1)) % 30 }
        return String(format: "v1-%02d", slot + 1)
    }
}

struct PlannedReminder: Codable, Equatable {
    let date: Date
    let dayID: String
    let senderID: String
    let characterID: String
    let messageIndex: Int
    let title: String
    let body: String
    let language: String

    var identifier: String { "upme.daily-reminder." + dayID }
}

struct PlannedFanShareNotification: Equatable {
    let postID: UUID
    let shareID: UUID
    let date: Date
    let author: String

    var identifier: String { "upme.fan-share." + shareID.uuidString.lowercased() }
}

struct DailyReminderPlanner {
    let copy: [String: [String: [String]]]

    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func excludingQuoteDays(_ reminders: [PlannedReminder], quoteDates: [Date],
                                   calendar: Calendar = Self.calendar()) -> [PlannedReminder] {
        let quoteDays = Set(quoteDates.map { calendar.startOfDay(for: $0) })
        return reminders.filter { !quoteDays.contains(calendar.startOfDay(for: $0.date)) }
    }

    func plan(now: Date, cadenceAnchor: Date, lastPost: Date?, regulars: [ReminderRegular],
              language: String, history: [PlannedReminder], seed: String,
              calendar: Calendar = Self.calendar(), limit: Int = 60) -> [PlannedReminder] {
        guard limit > 0 else { return [] }
        var result: [PlannedReminder] = []
        var previous = history.filter { $0.date <= now }.sorted { $0.date < $1.date }
        let senders = regulars.sorted { $0.id < $1.id }
        for offset in 0..<125 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let date = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day), date > now else { continue }
            let daysSinceEnabled = calendar.dateComponents([.day], from: calendar.startOfDay(for: cadenceAnchor), to: day).day ?? 0
            // Fixed alternate-day calendar: opening the app never postpones the next reminder.
            guard daysSinceEnabled >= 2 && daysSinceEnabled.isMultiple(of: 2) else { continue }
            if let lastPost, calendar.isDate(lastPost, inSameDayAs: date) { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let dayID = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            let choices = senders.count > 1 ? senders.filter { $0.id != previous.last?.senderID } : senders
            let sender = choices.isEmpty ? nil : choices[index(seed + dayID + ":sender", count: choices.count)]
            let character = sender?.characterID ?? "upme"
            let messages = copy[character]?[language] ?? Self.fallback(language: language)
            guard !messages.isEmpty else { continue }
            let recent = previous.filter { $0.characterID == character && $0.language == language }
                .suffix(max(0, messages.count - 1)).map(\.messageIndex)
            let candidates = messages.indices.filter { !recent.contains($0) }
            let pool = candidates.isEmpty ? Array(messages.indices) : candidates
            let messageIndex = pool[index(seed + dayID + ":" + character, count: pool.count)]
            let reminder = PlannedReminder(date: date, dayID: dayID, senderID: sender?.id ?? "upme",
                characterID: character, messageIndex: messageIndex, title: sender.map { "UPME!｜\($0.name)" } ?? "UPME!",
                body: messages[messageIndex], language: language)
            result.append(reminder)
            previous.append(reminder)
            if result.count >= limit { break }
        }
        return result
    }

    private func index(_ key: String, count: Int) -> Int {
        SHA256.hash(data: Data(key.utf8)).prefix(8).reduce(0) { ($0 * 256 + Int($1)) % count }
    }

    static func fallback(language: String) -> [String] {
        language == "en" ? [
            "How was your day? Share a little if you'd like.",
            "Something good or something to get off your chest? Leave a few words here.",
            "An ordinary day is welcome too. What would you like to share?"
        ] : [
            "今日もおつかれさま。どんな一日だった？",
            "うれしかったことも、ぼやきたいことも。今日は何を話す？",
            "何もなかった日も、ひとこと聞かせて。"
        ]
    }
}

@MainActor
final class DailyReminderManager: ObservableObject {
    static let shared = DailyReminderManager()
    static let prefix = "upme.daily-reminder."
    @Published private(set) var enabled: Bool
    @Published private(set) var permissionDenied = false
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published var pendingPostOpen = false
    @Published var pendingFanSharePostID: UUID?
    @Published var pendingFanShareID: UUID?
    #if DEBUG
    @Published private(set) var testNotificationMessage: String?
    #endif

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let planner: DailyReminderPlanner
    private var language = "ja"
    private var regulars: [ReminderRegular] = []
    private var fanShares: [PlannedFanShareNotification] = []
    private var fanShareDates: [Date] = []
    private var dismissedQuoteDay: Date?
    private var ready = false
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var lastPost: Date?
    private var cadenceAnchor: Date
    private var history: [PlannedReminder]
    private let seed: String

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        enabled = defaults.object(forKey: "dailyReminder.enabled") as? Bool ?? true
        cadenceAnchor = defaults.object(forKey: "dailyReminder.cadenceAnchor") as? Date ?? Date()
        lastPost = defaults.object(forKey: "dailyReminder.lastPost") as? Date
        dismissedQuoteDay = defaults.object(forKey: "dailyReminder.dismissedQuoteDay") as? Date
        seed = defaults.string(forKey: "dailyReminder.seed") ?? UUID().uuidString
        if !DesignPreview.isActive { defaults.set(seed, forKey: "dailyReminder.seed") }
        history = (defaults.data(forKey: "dailyReminder.history").flatMap {
            try? JSONDecoder().decode([PlannedReminder].self, from: $0)
        }) ?? []
        let copy = Bundle.main.url(forResource: "DailyReminderCopy", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: [String: [String]]].self, from: $0) } ?? [:]
        planner = DailyReminderPlanner(copy: copy)
        if enabled, !DesignPreview.isActive {
            defaults.set(cadenceAnchor, forKey: "dailyReminder.cadenceAnchor")
        }
    }

    func configure(language: String, regulars: [RegularFollower], onboarded: Bool,
                   hasPosts: Bool, latestPost: Date?, posts: [PostModel]) {
        guard !DesignPreview.isActive else { return }
        let nextRegulars = regulars.map {
            ReminderRegular(id: $0.id, name: $0.authorName,
                characterID: ReminderRegular.characterID($0.characterId, regularID: $0.id))
        }
        let nextReady = onboarded && hasPosts
        let nextFanShares = posts.flatMap { post in
            // A viral post can have two quotes at the same time; send only one alert for the post.
            post.fanShares.filter { $0.readAt == nil }.prefix(1).map { share in
                PlannedFanShareNotification(postID: post.id, shareID: share.id,
                                            date: share.availableAt, author: share.author.authorName)
            }
        }
        // Keep the day blocked after a quote arrives or is read, not just while its alert is pending.
        let nextFanShareDates = posts.flatMap { $0.fanShares.map(\.availableAt) }
        var changed = self.language != language || self.regulars != nextRegulars || ready != nextReady
            || fanShares != nextFanShares || fanShareDates != nextFanShareDates
        self.language = language
        self.regulars = nextRegulars
        fanShares = nextFanShares
        fanShareDates = nextFanShareDates
        ready = nextReady
        if let latestPost, latestPost <= Date(), latestPost > (lastPost ?? .distantPast) {
            lastPost = latestPost
            defaults.set(latestPost, forKey: "dailyReminder.lastPost")
            changed = true
        }
        if changed { reschedule() }
    }

    func becameActive() {
        guard !DesignPreview.isActive else { return }
        reschedule()
    }

    func requestAuthorizationIfNeeded() async {
        guard !DesignPreview.isActive, enabled, !busy else { return }
        let settings = await center.notificationSettings()
        guard enabled, !busy else { return }
        permissionDenied = settings.authorizationStatus == .denied
        if settings.authorizationStatus == .notDetermined {
            await setEnabled(true)
        }
    }

    func setEnabled(_ value: Bool) async {
        guard !DesignPreview.isActive else { enabled = value; return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        errorMessage = nil
        let wasEnabled = enabled
        if value {
            do {
                let settings = await center.notificationSettings()
                let granted = settings.authorizationStatus == .notDetermined
                    ? try await center.requestAuthorization(options: [.alert, .sound])
                    : [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
                enabled = granted
                permissionDenied = !granted
            } catch {
                enabled = false
                errorMessage = language == "en" ? "Couldn't enable notifications. Please try again." : "通知を有効にできませんでした。もう一度お試しください。"
            }
        } else {
            enabled = false
        }
        defaults.set(enabled, forKey: "dailyReminder.enabled")
        if enabled && !wasEnabled {
            cadenceAnchor = Date()
            defaults.set(cadenceAnchor, forKey: "dailyReminder.cadenceAnchor")
        }
        UPMEAnalytics.capture("daily_reminder_preference_changed", properties: ["enabled": enabled])
        reschedule()
    }

    func opened(_ info: [AnyHashable: Any]) {
        if info["destination"] as? String == "fan_share",
           let post = info["post_id"] as? String, let share = info["share_id"] as? String,
           let postID = UUID(uuidString: post), let shareID = UUID(uuidString: share) {
            pendingFanSharePostID = postID
            pendingFanShareID = shareID
            UPMEAnalytics.capture("fan_share_notification_opened", properties: [
                "post_flow_id": postID.uuidString.lowercased()
            ])
            return
        }
        pendingPostOpen = true
        #if DEBUG
        if info["debug_test"] as? Bool == true { return }
        #endif
        var properties: [String: Any] = [:]
        for key in ["character_id", "message_index", "language", "day"] {
            properties[key] = info[key]
        }
        // Do not send the regular's name, notification text, or conversation history.
        UPMEAnalytics.capture("daily_reminder_opened", properties: properties)
        defaults.set(Date(), forKey: "dailyReminder.lastOpened")
    }

    func consumedFanShare() {
        pendingFanSharePostID = nil
        pendingFanShareID = nil
    }

    func cancelFanShareNotifications(_ identifiers: [String], quoteDates: [Date] = []) {
        let now = Date()
        let calendar = DailyReminderPlanner.calendar()
        if quoteDates.contains(where: { $0 <= now && calendar.isDate($0, inSameDayAs: now) }) {
            dismissedQuoteDay = calendar.startOfDay(for: now)
            defaults.set(dismissedQuoteDay, forKey: "dailyReminder.dismissedQuoteDay")
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        reschedule()
    }

    #if DEBUG
    func sendTestNotification() async {
        guard !DesignPreview.isActive, !busy else { return }
        busy = true
        defer { busy = false }
        testNotificationMessage = nil
        do {
            let settings = await center.notificationSettings()
            let granted = settings.authorizationStatus == .notDetermined
                ? try await center.requestAuthorization(options: [.alert, .sound])
                : [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            permissionDenied = !granted
            guard granted else {
                testNotificationMessage = language == "en" ? "Allow UPME notifications in iPhone Settings first." : "iPhoneの設定でUPMEの通知を許可してください。"
                return
            }
            let now = Date()
            let calendar = DailyReminderPlanner.calendar()
            let anchor = calendar.date(byAdding: .day, value: -2, to: now) ?? now
            guard let entry = planner.plan(now: now, cadenceAnchor: anchor, lastPost: nil,
                regulars: regulars, language: language, history: history, seed: UUID().uuidString,
                calendar: calendar, limit: 1).first else { return }
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            content.userInfo = ["destination": "post", "debug_test": true]
            // Separate identifier: rescheduling daily reminders cannot cancel this test.
            let request = UNNotificationRequest(identifier: "upme.reminder-test.manual", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false))
            try await center.add(request)
            testNotificationMessage = language == "en"
                ? "Test notification scheduled in 10 seconds. Tap it to open Post."
                : "10秒後にテスト通知が届きます。タップすると投稿画面が開きます。"
        } catch {
            testNotificationMessage = language == "en" ? "Couldn't schedule the test notification. Please try again." : "テスト通知を予約できませんでした。もう一度お試しください。"
        }
    }
    #endif

    func postCreated(postID: UUID) {
        guard !DesignPreview.isActive else { return }
        let now = Date()
        lastPost = now
        defaults.set(now, forKey: "dailyReminder.lastPost")
        if let openedAt = defaults.object(forKey: "dailyReminder.lastOpened") as? Date,
           now.timeIntervalSince(openedAt) >= 0, now.timeIntervalSince(openedAt) <= 3600 {
            UPMEAnalytics.capture("daily_reminder_post_created", properties: [
                "post_flow_id": postID.uuidString.lowercased(),
                "seconds_since_open": Int(now.timeIntervalSince(openedAt))
            ])
            defaults.removeObject(forKey: "dailyReminder.lastOpened")
        }
        reschedule()
    }

    func reschedule() {
        guard !DesignPreview.isActive else { return }
        revision += 1
        guard worker == nil else { return }
        worker = Task {
            while true {
                let current = revision
                await rebuild(revision: current)
                if current == revision { break }
            }
            worker = nil
        }
    }

    private func rebuild(revision current: Int) async {
        let settings = await center.notificationSettings()
        guard current == revision else { return }
        permissionDenied = settings.authorizationStatus == .denied
        let pending = await center.pendingNotificationRequests()
        guard current == revision else { return }
        let ours = pending.filter {
            $0.identifier.hasPrefix(Self.prefix) || $0.identifier.hasPrefix("upme.fan-share.")
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard enabled, ready, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
                $0.hasPrefix(Self.prefix) || $0.hasPrefix("upme.fan-share.")
            })
            return
        }
        let now = Date()
        var scheduledShareCount = 0
        let shareCalendar = DailyReminderPlanner.calendar()
        for share in fanShares.sorted(by: { $0.date < $1.date }) where share.date > now {
            guard current == revision else { return }
            guard scheduledShareCount < max(0, 64 - (pending.count - ours.count)) else { break }
            let content = UNMutableNotificationContent()
            content.title = "UPME!｜\(share.author)"
            content.body = language == "en" ? "Shared your post. See what your followers are saying."
                : "あなたの投稿を紹介しました。フォロワーの反応を見てみよう。"
            content.sound = .default
            content.userInfo = ["destination": "fan_share", "post_id": share.postID.uuidString,
                                "share_id": share.shareID.uuidString]
            let components = shareCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: share.date)
            do {
                try await center.add(UNNotificationRequest(identifier: share.identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                scheduledShareCount += 1
            } catch { /* The in-app activity remains available without a notification. */ }
        }
        let past = Array(history.filter { $0.date <= now }.sorted { $0.date < $1.date }.suffix(60))
        let otherCount = pending.count - ours.count
        let plan = planner.plan(now: now, cadenceAnchor: cadenceAnchor, lastPost: lastPost, regulars: regulars,
            language: language, history: past, seed: seed, limit: min(60, max(0, 64 - otherCount - scheduledShareCount)))
        errorMessage = nil
        var scheduled: [PlannedReminder] = []
        for entry in DailyReminderPlanner.excludingQuoteDays(plan, quoteDates: fanShareDates
                                                             + [dismissedQuoteDay].compactMap { $0 },
                                                             calendar: shareCalendar) {
            guard current == revision else { return }
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            content.threadIdentifier = "upme.daily-reminder"
            content.userInfo = ["destination": "post", "character_id": entry.characterID,
                "message_index": entry.messageIndex, "language": entry.language, "day": entry.dayID]
            // No fixed timezone: each request follows the device's local wall-clock time.
            let components = DailyReminderPlanner.calendar().dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: entry.identifier, content: content, trigger: trigger))
                scheduled.append(entry)
            } catch {
                errorMessage = language == "en" ? "Couldn't schedule reminders. Please try again." : "通知を予約できませんでした。もう一度お試しください。"
            }
        }
        guard current == revision else { return }
        history = past + scheduled
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "dailyReminder.history") }
        UPMEAnalytics.capture("daily_reminder_scheduled", properties: ["count": scheduled.count, "language": language])
    }
}

final class ReminderApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        #if DEBUG
        if notification.request.identifier.hasPrefix("upme.reminder-test.") {
            completionHandler([.banner, .sound])
            return
        }
        #endif
        // Posting reminders stay quiet in-app; new follower quotes still deserve a banner.
        completionHandler(notification.request.identifier.hasPrefix("upme.daily-reminder.")
            ? [] : [.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        var isReminder = response.notification.request.identifier.hasPrefix("upme.daily-reminder.")
            || response.notification.request.identifier.hasPrefix("upme.fan-share.")
        #if DEBUG
        isReminder = isReminder || response.notification.request.identifier.hasPrefix("upme.reminder-test.")
        #endif
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier, isReminder else {
            completionHandler()
            return
        }
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            DailyReminderManager.shared.opened(info)
            completionHandler()
        }
    }
}
