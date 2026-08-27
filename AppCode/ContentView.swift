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
    @AppStorage("lastSeenUpdateNoticeVersion") private var lastSeenUpdateNoticeVersion: String = ""
    @State private var showRankUpPopup: Bool = false
    @State private var showUpdateNotice: Bool = false
    @State private var newlyAchievedRank: Int = 1

    /// プライバシーポリシー同意フラグ（未同意ならまず同意画面を表示）
    @State private var hasAcceptedPrivacyPolicy: Bool =
        UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")

    var body: some View {
        if !hasAcceptedPrivacyPolicy {
            // ── Step 0: プライバシー同意画面 ──
            PrivacyConsentView(hasAccepted: $hasAcceptedPrivacyPolicy, userID: appState.userId)
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
            ParticleNetworkBackground()
                .ignoresSafeArea()
            
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
                                Theme.accentGradient
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

            if showUpdateNotice {
                UpdateNoticeView(notice: AppUpdateNotice.current) {
                    lastSeenUpdateNoticeVersion = AppUpdateNotice.current.version
                    UPMEAnalytics.capture("update_notice_dismissed", properties: [
                        "version": AppUpdateNotice.current.version
                    ])
                    withAnimation(.easeOut(duration: 0.25)) {
                        showUpdateNotice = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(110)
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
            .background(Theme.bgDeepBlack.opacity(0.94).background(Material.ultraThin).ignoresSafeArea(edges: .bottom))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.subtleBorder), alignment: .top)
        }
        .onAppear {
            guard lastSeenUpdateNoticeVersion != AppUpdateNotice.current.version else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                UPMEAnalytics.capture("update_notice_viewed", properties: [
                    "version": AppUpdateNotice.current.version
                ])
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    showUpdateNotice = true
                }
            }
        }
        .onChange(of: appState.currentRank) { newRank in
            if newRank > lastSeenRank {
                UPMEAnalytics.capture("rank_up", properties: [
                    "rank": newRank
                ])
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
        .onChange(of: activeTab) { _, tab in
            let tabName: String
            switch tab {
            case .home: tabName = "home"
            case .post: tabName = "post"
            case .stats: tabName = "stats"
            case .profile: tabName = "profile"
            }
            UPMEAnalytics.capture("tab_viewed", properties: ["tab": tabName])
        }
    }
}

struct AppUpdateNotice {
    struct Item: Identifiable {
        let id: String
        let icon: String
        let titleJapanese: String
        let titleEnglish: String
        let detailJapanese: String
        let detailEnglish: String
    }

    let version: String
    let items: [Item]

    static let current = AppUpdateNotice(
        version: "1.1.1",
        items: [
            Item(
                id: "regular-followers",
                icon: "star.bubble.fill",
                titleJapanese: "常連AIフォロワー",
                titleEnglish: "Regular AI Followers",
                detailJapanese: "お気に入りのAIが、これまでの会話を覚えて返信するようになりました。",
                detailEnglish: "Your favorite AI followers can now remember past conversations when they reply."
            ),
            Item(
                id: "reply-threads",
                icon: "bubble.left.and.bubble.right.fill",
                titleJapanese: "返信から続く会話",
                titleEnglish: "Continue the Conversation",
                detailJapanese: "AIからの返信に一度だけ返事をして、その先の会話を楽しめます。",
                detailEnglish: "Reply once to an AI response and see the conversation continue."
            ),
            Item(
                id: "english",
                icon: "globe",
                titleJapanese: "英語表示に対応",
                titleEnglish: "English Support",
                detailJapanese: "端末の言語に合わせて表示し、プロフィールからいつでも切り替えられます。",
                detailEnglish: "The app follows your device language, and you can switch it anytime from your profile."
            ),
            Item(
                id: "visual-and-support",
                icon: "sparkles",
                titleJapanese: "新しいビジュアルとお問い合わせ",
                titleEnglish: "New Visuals and Support",
                detailJapanese: "光がつながる背景演出と、プロフィールのお問い合わせ窓口を追加しました。",
                detailEnglish: "Enjoy the new connected-light background and a contact option in your profile."
            )
        ]
    )
}

struct UpdateNoticeView: View {
    @EnvironmentObject private var appState: AppState
    let notice: AppUpdateNotice
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [Theme.deepPurple.opacity(0.95), Theme.cardBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Theme.hotPink.opacity(0.12))
                        .frame(width: 150, height: 150)
                        .blur(radius: 18)
                        .offset(x: 45, y: -60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT'S NEW  ·  v\(notice.version)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(Theme.lavender)
                            .tracking(1.5)

                        Text(appState.text("UPME!が\nアップデートされました", "UPME! just\ngot better"))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineSpacing(2)

                        Text(appState.text("もっと会話が続く、もっと自分らしい場所へ。", "More conversation. More of your own space."))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .frame(height: 178)
                .clipped()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(notice.items) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Theme.hotPink)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.hotPink.opacity(0.11))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(appState.text(item.titleJapanese, item.titleEnglish))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(appState.text(item.detailJapanese, item.detailEnglish))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.gray)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
                .frame(maxHeight: 310)

                Button(action: onClose) {
                    Text(appState.text("アップデートを楽しむ", "Explore the Update"))
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accentGradient)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Theme.purpleAccent.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: Theme.purpleAccent.opacity(0.22), radius: 30, y: 12)
            .padding(.horizontal, 22)
            .frame(maxWidth: 410)
        }
        .accessibilityAddTraits(.isModal)
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
    let label: LocalizedStringKey
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
    @EnvironmentObject var appState: AppState
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
                        Text(LocalizedStringKey(info.name))
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
                                Text(appState.text("アンチ: \(info.haters)", "Haters: \(info.hatersEnglish)"))
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
