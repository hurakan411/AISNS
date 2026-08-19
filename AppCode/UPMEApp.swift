import SwiftUI
import GoogleMobileAds
import StoreKit

@main
struct UPMEAISNSApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(storeManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    UPMEAnalytics.recordActiveSession(userID: appState.userId)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        UPMEAnalytics.recordActiveSession(userID: appState.userId)
                    } else {
                        UPMEAnalytics.markSessionInactive()
                    }
                }
        }
    }
}
