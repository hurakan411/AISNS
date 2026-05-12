import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView(adSize: GADAdSizeBanner)
        // Production Ad Unit ID
        bannerView.adUnitID = "ca-app-pub-1732522218412052/6848967659"
        
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        bannerView.rootViewController = windowScene?.windows.first?.rootViewController
        
        bannerView.load(GADRequest())
        return bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
