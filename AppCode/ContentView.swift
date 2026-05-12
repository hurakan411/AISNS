import SwiftUI
import StoreKit

enum Tab {
    case home, post, stats, profile
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var storeManager: StoreManager
    @State private var activeTab: Tab = .home

    @AppStorage("lastSeenRank") private var lastSeenRank: Int = 1
    @State private var showRankUpPopup: Bool = false
    @State private var newlyAchievedRank: Int = 1

    /// プライバシーポリシー同意フラグ（未同意ならまず同意画面を表示）
    @State private var hasAcceptedPrivacyPolicy: Bool =
        UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")

    var body: some View {
        if !hasAcceptedPrivacyPolicy {
            // ── Step 0: プライバシー同意画面 ──
            PrivacyConsentView(hasAccepted: $hasAcceptedPrivacyPolicy)
        } else if !appState.onboardingStatusReady {
            // ── Step 1: サーバー確認待ち ──
            Theme.bgDeepBlack.ignoresSafeArea()
        } else if !appState.hasCompletedOnboarding {
            // ── Step 2: オンボーディング ──
            OnboardingView()
                .environmentObject(appState)
        } else {
            // ── Step 3: メイン画面 ──
            mainContent
        }
    }
    
    private var mainContent: some View {
        ZStack {
            Theme.bgDeepBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                if !storeManager.isAdsRemoved {
                    BannerAdView()
                        .frame(width: 320, height: 50)
                }
                
                if activeTab != .post && activeTab != .profile {
                    HStack(spacing: 12) {
                        Text("UPME! | AI SNS")
                            .font(.system(size: 20, weight: .black, design: .rounded)).italic()
                            .foregroundColor(.clear)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [Theme.hotPink, .purple, Theme.cyan]), startPoint: .leading, endPoint: .trailing)
                                    .mask(Text("UPME! | AI SNS").font(.system(size: 20, weight: .black, design: .rounded)).italic())
                            )
                            .neonShadow(color: Theme.hotPink, radius: 4)
                            
                        Spacer()

                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.bgDeepBlack)
                    .zIndex(1)
                }
                
                ZStack {
                    switch activeTab {
                    case .home:
                        FeedView { activeTab = .post }
                            .transition(.opacity)
                    case .post:
                        PostView(onCancel: { activeTab = .home })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .stats:
                        StatsView()
                            .transition(.opacity)
                    case .profile:
                        ProfileView()
                            .transition(.opacity)
                            .ignoresSafeArea(edges: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if !storeManager.isAdsRemoved {
                    BannerAdView()
                        .frame(width: 320, height: 50)
                }
            }
            
            if showRankUpPopup {
                RankUpView(rank: newlyAchievedRank) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showRankUpPopup = false
                    }
                }
                .zIndex(100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                NavBtn(icon: "house.fill", label: "ホーム", isActive: activeTab == .home) { withAnimation { activeTab = .home } }
                Spacer()
                NavBtn(icon: "plus.app.fill", label: "投稿", isActive: activeTab == .post, isCenter: true) { withAnimation { activeTab = .post } }
                Spacer()
                NavBtn(icon: "chart.bar.fill", label: "統計", isActive: activeTab == .stats) { withAnimation { activeTab = .stats } }
                Spacer()
                NavBtn(icon: "person.fill", label: "プロフ", isActive: activeTab == .profile) { withAnimation { activeTab = .profile } }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color.black.opacity(0.85).background(Material.ultraThin).ignoresSafeArea(edges: .bottom))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
        }
        .onChange(of: appState.currentRank) { newRank in
            if newRank > lastSeenRank {
                newlyAchievedRank = newRank
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showRankUpPopup = true
                }
                lastSeenRank = newRank
            }
            
            if [2, 3, 4].contains(newRank) {
                let key = "hasRequestedReviewForRank\(newRank)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: windowScene)
                    }
                }
            }
        }
    }
}

extension View {
    func animatePulse() -> some View {
        self.modifier(PulseModifier())
    }
}

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

struct NavBtn: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isCenter: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? Theme.hotPink : .gray.opacity(0.5))
                    .neonShadow(color: isActive ? Theme.hotPink : .clear, radius: isActive ? 8 : 0)
                
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(isActive ? Theme.hotPink : .gray.opacity(0.5))
                    .textCase(.uppercase)
            }
            .scaleEffect(isActive ? 1.05 : 1.0)
        }
    }
}

struct RankUpView: View {
    let rank: Int
    var onClose: () -> Void
    
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotate: Double = -10
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .background(Material.ultraThin)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            
            VStack(spacing: 24) {
                Text("RANK UP!")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .italic()
                    .foregroundColor(Theme.hotPink)
                    .neonShadow(color: Theme.hotPink, radius: 15)
                    .scaleEffect(scale)
                
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.yellow)
                    .neonShadow(color: .yellow, radius: 20)
                    .rotationEffect(.degrees(rotate))
                
                VStack(spacing: 8) {
                    Text("新しいランクに到達しました")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Lv.\(rank)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .neonShadow(color: .white, radius: 10)
                    
                    if let info = rankData.first(where: { $0.level == rank }) {
                        Text(info.name)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Theme.cyan)
                            .neonShadow(color: Theme.cyan, radius: 8)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("【解放された効果】")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 16) {
                                RankDetailLabel(icon: "person.2.fill", text: info.followers)
                                RankDetailLabel(icon: "bubble.left.fill", text: info.replies)
                                RankDetailLabel(icon: "heart.fill", text: info.likes)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(rank >= 4 ? .orange.opacity(0.7) : .gray.opacity(0.3))
                                Text("アンチ: \(info.haters)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                        .padding(20)
                        .background(Theme.bgDeepBlack.opacity(0.8))
                        .cornerRadius(16)
                    }
                }
                
                Button(action: onClose) {
                    Text("OK")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 64)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(gradient: Gradient(colors: [Theme.hotPink, Theme.cyan]), startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .neonShadow(color: Theme.hotPink, radius: 10)
                }
                .padding(.top, 24)
            }
            .padding(32)
            .background(Color(white: 0.1).opacity(0.95).background(Material.ultraThin))
            .cornerRadius(32)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(LinearGradient(gradient: Gradient(colors: [Theme.hotPink, Theme.cyan]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
            )
            .shadow(color: Theme.hotPink.opacity(0.4), radius: 50, x: 0, y: 0)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                let baseAnimation = Animation.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0)
                withAnimation(baseAnimation) {
                    scale = 1.0
                    opacity = 1.0
                }
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    rotate = 10
                }
            }
        }
    }
}

