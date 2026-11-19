import SwiftUI
import StoreKit

enum Tab: String {
    case home, post, stats, profile, settings

    var guideScreen: GuideScreen? { GuideScreen(rawValue: rawValue) }
}

struct ContentView: View {
    var updateNoticeEligible = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var storeManager: StoreManager
    @EnvironmentObject private var reminders: DailyReminderManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var homeGuide = HomeGuideCoordinator(
        store: HomeGuideProgressStore(persists: !DesignPreview.isActive),
        automaticEnabled: !DesignPreview.isActive || DesignPreview.argument("--ui-guide") == "true",
        previewStart: HomeGuideStep(rawValue: DesignPreview.argument("--ui-guide-step") ?? "")
    )
    @State private var hasCheckedStartupNotice = false
    @State private var homeContentModalPresented = false
    @State private var hasCheckedReminderPermission = false
    @State private var activeTab: Tab = {
        switch DesignPreview.argument("--ui-tab") {
        case "stats": return .stats
        case "post": return .post
        case "profile": return .profile
        case "settings": return .settings
        default: return .home
        }
    }()

    @AppStorage("lastSeenRank") private var lastSeenRank: Int = 1
    @AppStorage("lastSeenUpdateNoticeVersion") private var lastSeenUpdateNoticeVersion: String = ""
    @State private var showRankUpPopup: Bool = false
    @State private var showUpdateNotice: Bool = false
    @State private var newlyAchievedRank: Int = 1

    private var guideAllowed: Bool {
        activeTab.guideScreen != nil && scenePhase == .active && hasCheckedStartupNotice
            && !showUpdateNotice && !showRankUpPopup && !homeContentModalPresented
            && appState.replyErrorMessage == nil
            && !reminders.busy
    }

    private var canRequestReminderPermission: Bool {
        !DesignPreview.isActive && activeTab == .home && guideAllowed && !homeGuide.isPresenting
            && appState.totalPosts > 0 && !hasCheckedReminderPermission
            && reminders.enabled && !reminders.pendingPostOpen
    }

    private var shouldShowBannerAds: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        !storeManager.isAdsRemoved
        #endif
    }

    /// プライバシーポリシー同意フラグ（未同意ならまず同意画面を表示）
    @State private var hasAcceptedPrivacyPolicy: Bool =
        DesignPreview.isActive || UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")

    var body: some View {
        if !hasAcceptedPrivacyPolicy {
            // ── Step 0: プライバシー同意画面 ──
            PrivacyConsentView(hasAccepted: $hasAcceptedPrivacyPolicy, userID: appState.userId)
        } else if !appState.hasCompletedOnboarding {
            // Use local progress immediately; server reconciliation runs in the background.
            OnboardingView()
                .environmentObject(appState)
        } else {
            mainContent
        }
    }
    
    private var mainContent: some View {
        ZStack {
            ParticleNetworkBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if shouldShowBannerAds {
                    BannerAdView()
                        .frame(width: 320, height: 50)
                } else if DesignPreview.argument("--ui-ad-space") == "true" {
                    Color.clear.frame(height: 50)
                }
                
                if activeTab == .home {
                    HStack(spacing: 12) {
                        if appState.designTemplate == .lofi {
                            PixelGlyph(name: "wordmark").fill(Theme.textPrimary, style: FillStyle(antialiased: false))
                                .frame(width: 110, height: 24).accessibilityLabel("UPME!")
                            TemplateIcon(systemName: "heart", size: 18).foregroundStyle(Theme.hotPink)
                        } else {
                        Text("UPME! | AI SNS")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.clear)
                            .background(
                                Theme.accentGradient
                                    .mask(Text("UPME! | AI SNS").font(.system(size: 20, weight: .black, design: .rounded)))
                            )
                            .neonShadow(color: Theme.hotPink, radius: 2)
                        }
                            
                        Spacer()

                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .zIndex(1)
                }
                
                ZStack {
                    switch activeTab {
                    case .home:
                        FeedView(guide: homeGuide) { activeTab = .post }
                            .transition(.opacity)
                    case .post:
                        PostView(onCancel: { activeTab = .home }, guide: homeGuide)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .stats:
                        StatsView(guide: homeGuide)
                            .transition(.opacity)
                    case .profile:
                        ProfileView(guide: homeGuide)
                            .transition(.opacity)
                    case .settings:
                        NavigationStack {
                            SettingsView(onReplayGuide: { screen in
                                homeGuide.requestReplay(for: screen)
                                withAnimation { activeTab = Tab(rawValue: screen.rawValue) ?? .home }
                            })
                        }
                        .tint(Theme.lavender)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if shouldShowBannerAds {
                    BannerAdView()
                        .frame(width: 320, height: 50)
                } else if DesignPreview.argument("--ui-ad-space") == "true" {
                    Color.clear.frame(height: 50)
                }
            }
            .accessibilityHidden(showUpdateNotice || (guideAllowed && homeGuide.isPresenting))
            .allowsHitTesting(!showUpdateNotice)
            
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
                NavBtn(icon: "plus.app.fill", label: "投稿", isActive: activeTab == .post, isCenter: true) { withAnimation { activeTab = .post } }
                NavBtn(icon: "chart.bar.fill", label: "統計", isActive: activeTab == .stats) { withAnimation { activeTab = .stats } }
                NavBtn(icon: "person.fill", label: "プロフ", isActive: activeTab == .profile) { withAnimation { activeTab = .profile } }
                NavBtn(icon: "gearshape.fill", label: "設定", isActive: activeTab == .settings) { withAnimation { activeTab = .settings } }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Theme.bgDeepBlack.opacity(0.94).background(Material.ultraThin).ignoresSafeArea(edges: .bottom))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.subtleBorder), alignment: .top)
            .accessibilityHidden(showUpdateNotice || (guideAllowed && homeGuide.isPresenting))
            .allowsHitTesting(!showUpdateNotice)
        }
        .overlayPreferenceValue(HomeGuideAnchorPreference.self) { anchors in
            if let screen = activeTab.guideScreen {
            GeometryReader { geometry in
                let targets = Dictionary(uniqueKeysWithValues: HomeGuideStep.ordered(for: screen).compactMap { step in
                    anchors[.step(step)].map { (step, geometry[$0]) }
                })
                HomeGuideHost(
                    guide: homeGuide,
                    allowed: guideAllowed,
                    targets: targets,
                    viewport: anchors[.viewport].map { geometry[$0] } ?? .zero,
                    canvas: geometry.size,
                    japanese: appState.appLanguage == .japanese,
                    screen: screen
                )
            }
            .allowsHitTesting(guideAllowed && homeGuide.isPresenting)
            }
        }
        .onPreferenceChange(HomeGuideModalPreference.self) { homeContentModalPresented = $0 }
        .task {
            var shouldPresent = updateNoticeEligible
                && lastSeenUpdateNoticeVersion != AppUpdateNotice.current.version
            #if DEBUG
            // Allow one test launch to preview a notice that was already seen.
            shouldPresent = shouldPresent || ProcessInfo.processInfo.arguments.contains("--preview-update-notice")
            #endif
            if !hasCheckedStartupNotice, shouldPresent {
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                guard !Task.isCancelled else { return }
                lastSeenUpdateNoticeVersion = AppUpdateNotice.current.version
                UPMEAnalytics.capture("update_notice_viewed", properties: ["version": AppUpdateNotice.current.version])
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    showUpdateNotice = true
                }
            }
            hasCheckedStartupNotice = true
            openPostFromReminderIfNeeded()
        }
        .onChange(of: reminders.pendingPostOpen) { _, _ in openPostFromReminderIfNeeded() }
        .task(id: canRequestReminderPermission) {
            guard canRequestReminderPermission else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard canRequestReminderPermission else { return }
            hasCheckedReminderPermission = true
            // Keep the OS permission request alive when changing UI state cancels this task.
            Task { await reminders.requestAuthorizationIfNeeded() }
        }
        .onChange(of: appState.currentRank) { _, newRank in
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
            case .settings: tabName = "settings"
            }
            UPMEAnalytics.capture("tab_viewed", properties: ["tab": tabName])
        }
    }

    private func openPostFromReminderIfNeeded() {
        guard reminders.pendingPostOpen else { return }
        activeTab = .post
        reminders.pendingPostOpen = false
    }
}

enum UpdateNoticeEligibility {
    /// Save the decision so a fresh install does not become an update on its next launch.
    static func prepare(version: String, installedVersion: String, defaults: UserDefaults = .standard) -> Bool {
        guard installedVersion == version else { return false }
        let key = "updateNoticeEligible.\(version)"
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        let existingInstallation = defaults.string(forKey: "userId")?.isEmpty == false
            || defaults.bool(forKey: "hasCompletedOnboarding")
            || defaults.bool(forKey: "hasAcceptedPrivacyPolicy")
        defaults.set(existingInstallation, forKey: key)
        return existingInstallation
    }
}

struct AppUpdateNotice {
    struct Item: Identifiable {
        let id: String
        let highlighted: Bool
        let detailJapanese: String
        let detailEnglish: String
    }

    let version: String
    let items: [Item]

    static let current = AppUpdateNotice(
        version: "1.1.3",
        items: [
            Item(
                id: "design-templates",
                highlighted: true,
                detailJapanese: "気分に合わせて選べる「ブラック」「ホワイト」「ドット」の3つのデザインを用意しました。",
                detailEnglish: "Choose a design to match your mood: Black, White or Dot."
            ),
            Item(
                id: "screen-design",
                highlighted: true,
                detailJapanese: "ホーム・投稿・統計画面のデザインをリニューアルしました。",
                detailEnglish: "The Home, Post and Stats screens have a fresh new look."
            ),
            Item(
                id: "regular-impressions",
                highlighted: true,
                detailJapanese: "「常連から見たあなた」機能を追加しました。会話を重ねると、あなたの魅力を紹介する文章が見られます。",
                detailEnglish: "Added How Your Regular Sees You. As you chat, discover a description of your qualities."
            ),
            Item(
                id: "posting-reminders",
                highlighted: true,
                detailJapanese: "フォロワーたちから通知が届くようになりました。2日に1回、20時に投稿へお誘いします。設定からオン・オフを切り替えられます。",
                detailEnglish: "Your followers can now invite you to post every other day at 8 p.m. Turn reminders on or off in Settings."
            ),
            Item(
                id: "ai-avatars",
                highlighted: false,
                detailJapanese: "AIのアイコンが表示されにくい問題を改善しました。",
                detailEnglish: "Improved loading of AI profile icons."
            ),
            Item(
                id: "supportive-replies",
                highlighted: false,
                detailJapanese: "アンチ設定がオフのとき、より温かく自然な返信が届くよう改善しました。",
                detailEnglish: "Replies are warmer and more natural when Hater replies are turned off."
            ),
            Item(
                id: "background-replies",
                highlighted: false,
                detailJapanese: "返信を待つ間に画面をロックしても、受信処理を一定時間続けられるよう改善しました。",
                detailEnglish: "Reply requests can now continue for a limited time after you lock the screen."
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
                VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT'S NEW  ·  v\(notice.version)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(Theme.lavender)
                            .tracking(1.5)

                        Text(appState.text("UPMEが\n新しくなりました", "UPME just\ngot better"))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                            .lineSpacing(2)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .background {
                    LinearGradient(
                        colors: [Theme.deepPurple.opacity(0.95), Theme.cardBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Theme.hotPink.opacity(0.12))
                            .frame(width: 150, height: 150)
                            .blur(radius: 18)
                            .offset(x: 45, y: -60)
                    }
                }
                .clipped()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(notice.items) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.highlighted ? "star.fill" : "circle.fill")
                                    .font(.system(size: item.highlighted ? 15 : 5, weight: .bold))
                                    .foregroundStyle(item.highlighted ? Theme.hotPink : Theme.lavender)
                                    .frame(width: 20, height: 22)
                                    .accessibilityHidden(true)
                                    Text(appState.text(item.detailJapanese, item.detailEnglish))
                                        .font(.system(size: 14, weight: item.highlighted ? .semibold : .regular))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .frame(maxHeight: 310)

                Button(action: onClose) {
                    Text(appState.text("はじめる", "Get started"))
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Theme.onAccent)
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
    @Environment(\.designTemplate) private var template
    let icon: String
    let label: LocalizedStringKey
    let isActive: Bool
    var isCenter: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                TemplateIcon(systemName: icon, size: 24)
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? Theme.hotPink : Theme.inactiveTab)
                    .neonShadow(color: isActive ? Theme.hotPink : .clear, radius: isActive ? 8 : 0)
                
                Text(label)
                    .font(.system(size: 9, weight: .black, design: template == .lofi ? .monospaced : .default))
                    .foregroundColor(isActive ? Theme.hotPink : Theme.inactiveTab)
                    .textCase(.uppercase)
            }
            .scaleEffect(isActive ? 1.05 : 1.0)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if isActive {
                    Capsule()
                        .fill(Theme.hotPink)
                        .frame(width: 30, height: 2)
                        .offset(y: 7)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
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
                        .foregroundColor(Theme.textPrimary)
                    
                    Text("Lv.\(rank)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
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
                        .foregroundColor(Theme.onAccent)
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
            .background(Theme.cardBackground.opacity(0.95).background(Material.ultraThin))
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
