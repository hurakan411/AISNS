import SwiftUI
import GoogleMobileAds
import StoreKit

@main
struct UPMEAISNSApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var storeManager = StoreManager()
    
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(storeManager)
                .preferredColorScheme(.dark)
        }
    }
}
