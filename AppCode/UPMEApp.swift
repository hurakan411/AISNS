import SwiftUI
import GoogleMobileAds
import StoreKit

@main
@MainActor
struct UPMEAISNSApp: App {
    @UIApplicationDelegateAdaptor(ReminderApplicationDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var reminders = DailyReminderManager.shared
    private let updateNoticeEligible: Bool
    @StateObject private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Capture installation history before AppState creates a new user ID.
        updateNoticeEligible = !DesignPreview.isActive && UpdateNoticeEligibility.prepare(
            version: AppUpdateNotice.current.version,
            installedVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        )
        _appState = StateObject(wrappedValue: AppState())
        if !DesignPreview.isActive {
            GADMobileAds.sharedInstance().start(completionHandler: nil)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(updateNoticeEligible: updateNoticeEligible)
                .environmentObject(appState)
                .environmentObject(storeManager)
                .environmentObject(reminders)
                .environment(\.locale, appState.locale)
                .environment(\.designTemplate, appState.designTemplate)
                .preferredColorScheme(appState.designTemplate.colorScheme)
                .onAppear {
                    UPMEAnalytics.recordActiveSession(userID: appState.userId)
                    configureReminders()
                    reminders.becameActive()
                }
                .onChange(of: appState.appLanguage) { _, _ in configureReminders() }
                .onChange(of: appState.regularFollowers) { _, _ in configureReminders() }
                .onChange(of: appState.posts.map(\.id)) { _, _ in configureReminders() }
                .onChange(of: appState.posts.flatMap { $0.fanShares.map {
                    "\($0.id.uuidString):\($0.readAt != nil):\($0.availableAt.timeIntervalSince1970)"
                } }) { _, _ in
                    configureReminders()
                }
                .onChange(of: appState.hasCompletedOnboarding) { _, _ in configureReminders() }
                .onChange(of: appState.totalPosts) { _, _ in configureReminders() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    reminders.reschedule()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        UPMEAnalytics.recordActiveSession(userID: appState.userId)
                        appState.fetchUser()
                        configureReminders()
                        reminders.becameActive()
                    } else {
                        UPMEAnalytics.markSessionInactive()
                    }
                }
        }
    }

    private func configureReminders() {
        reminders.configure(language: appState.languageCode, regulars: appState.regularFollowers,
            onboarded: appState.hasCompletedOnboarding, hasPosts: appState.totalPosts > 0,
            latestPost: appState.posts.compactMap(\.createdAt).max(), posts: appState.posts)
    }
}
