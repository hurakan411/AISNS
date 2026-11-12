import SwiftUI
import PhotosUI

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    var guide: HomeGuideCoordinator? = nil
    @State private var showsRankGuide = false

    private var currentInfo: RankInfo { rankData[appState.currentRank - 1] }

    var body: some View {
        GeometryReader { geometry in
            // Fit the available space after the safe areas, tab bar and ad banners.
            // Smaller displays use a smaller illustration and tighter spacing, without scrolling.
            ViewThatFits(in: .vertical) {
                statisticsContent(ringSize: min(300, geometry.size.width * 0.72), compact: false)
                statisticsContent(ringSize: min(300, geometry.size.width * 0.72), compact: true)
                statisticsContent(ringSize: min(260, geometry.size.width * 0.64), compact: true)
                statisticsContent(ringSize: min(240, geometry.size.width * 0.60), compact: true)
                statisticsContent(ringSize: min(210, geometry.size.width * 0.54), compact: true)
                statisticsContent(ringSize: min(180, geometry.size.width * 0.48), compact: true)
                statisticsContent(ringSize: min(140, max(72, geometry.size.height - 390)), compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { if !DesignPreview.isActive { appState.fetchUser() } }
        }
        .sheet(isPresented: $showsRankGuide) {
            NavigationStack {
                ScrollView { RankGuideSection(currentRank: appState.currentRank).padding(.bottom, 32) }
                    .background(StatsTheme.bgDeepBlack)
                    .navigationTitle(appState.text("ランク一覧", "All ranks"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showsRankGuide = false }
                                .tint(StatsTheme.hotPink)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .homeGuideViewport()
        .preference(key: HomeGuideModalPreference.self, value: showsRankGuide)
    }

    private func statisticsContent(ringSize: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: compact ? 8 : 10) {
                RankProgressRing(rank: appState.currentRank,
                                 progress: RankProgress.fraction(followers: appState.followers, rank: appState.currentRank))
                    .frame(width: ringSize, height: ringSize)

                Text(appState.text("ランク \(appState.currentRank)", "Rank \(appState.currentRank)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StatsTheme.lavender)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(StatsTheme.purpleAccent.opacity(0.14), in: Capsule())

                Text(LocalizedStringKey(currentInfo.name))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .homeGuideTarget(.statsRank)
            .frame(maxWidth: .infinity)

            RankBenefits(info: currentInfo)
                .homeGuideTarget(.statsBenefits)
                .padding(.top, compact ? 12 : 20)

            statisticsSummary(compact: compact)
                .homeGuideTarget(.statsSummary)
                .padding(.top, compact ? 12 : 24)

            Button { showsRankGuide = true } label: {
                HStack(spacing: 8) {
                    Text(appState.text("ランク一覧を見る", "View all ranks"))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StatsTheme.secondaryText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("stats.rankGuide")
            .homeGuideTarget(.statsRankList)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, compact ? 4 : 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, compact ? 6 : 16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statisticsSummary(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(appState.text("あなたの記録", "Your activity"))
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.text("AIフォロワー", "AI followers"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(StatsTheme.secondaryText)
                        statisticValue(appState.followers, unit: appState.text("人", ""), size: compact ? 32 : 36)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(appState.nextRankFollowers == nil ? appState.text("最高ランク", "Top rank") : appState.text("次のランクまで", "Next rank"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(StatsTheme.hotPink.opacity(0.85))
                        if let next = appState.nextRankFollowers {
                            let remaining = max(0, next - appState.followers).formatted(.number.locale(appState.locale))
                            Text(appState.text("あと\(remaining)人", "\(remaining) to go"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        } else {
                            Text(appState.text("最高ランク到達済み", "Top rank reached"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .combine)
                }

                HStack(alignment: .top, spacing: compact ? 8 : 12) {
                    summaryMetric(appState.text("投稿数", "Posts"), value: appState.totalPosts,
                                  icon: "pencil", color: StatsTheme.lavender, compact: compact)
                    summaryMetric(appState.text("もらったいいね", "Likes received"), value: appState.posts.reduce(0) { $0 + $1.likes },
                                  icon: "heart", color: StatsTheme.hotPink, compact: compact)
                    summaryMetric(appState.text("AIからの返信", "AI replies"),
                                  value: appState.posts.reduce(0) { $0 + $1.replies.count + $1.replyThreads.reduce(0) { $0 + $1.replies.filter { !$0.isUserReply }.count } },
                                  icon: "bubble.left", color: StatsTheme.lavender, compact: compact)
                }
            }
            .padding(compact ? 14 : 22)
            .background(StatsTheme.surfaceGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text(appState.text("いいね・返信は保存済みの投稿を集計", "Likes and replies are counted from posts saved on this device."))
                .font(.system(size: 10))
                .foregroundStyle(StatsTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    private func summaryMetric(_ title: String, value: Int, icon: String, color: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(color.opacity(0.9))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(StatsTheme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            statisticValue(value, unit: appState.text("件", ""), size: compact ? 24 : 27)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statisticValue(_ value: Int, unit: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value, format: .number.grouping(.automatic).locale(appState.locale))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(StatsTheme.secondaryText)
                    .fixedSize()
            }
        }
    }
}

struct RankBenefits: View {
    @EnvironmentObject private var appState: AppState
    let info: RankInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            benefit("heart", title: appState.text("いいね / 投稿", "Likes / post"), value: likesRange)
            benefit("bubble.left", title: appState.text("返信 / 投稿", "Replies / post"), value: appState.text(info.replies, info.replies.replacingOccurrences(of: "〜", with: "–")))
            benefit("star", title: appState.text("常連枠", "Regular slots"), value: appState.text("\(info.regularFollowerLimit)人", "\(info.regularFollowerLimit)"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(appState.text("いいねと返信は1投稿あたりの目安です", "Likes and replies are estimates per post."))
    }

    private var likesRange: String {
        info.likes.components(separatedBy: "〜").map { part in
            guard let number = Int(part.replacingOccurrences(of: ",", with: "")), number >= 10_000 else { return part }
            return number.formatted(.number.notation(.compactName).locale(appState.locale))
        }.joined(separator: appState.text("〜", "–"))
    }

    private func benefit(_ icon: String, title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
                .foregroundStyle(StatsTheme.hotPink.opacity(0.75))
            Text(title).font(.system(size: 10)).foregroundStyle(StatsTheme.secondaryText)
            Text(value).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RankInfo {
    let level: Int
    let name: String
    let followers: String
    let replies: String
    let haters: String
    let likes: String
    let regularFollowerLimit: Int

    var hatersEnglish: String {
        switch haters {
        case "なし": return "None"
        case "最大1": return "Up to 1"
        case "最大2": return "Up to 2"
        case "最大3": return "Up to 3"
        default: return haters
        }
    }
}

let rankData: [RankInfo] = [
    RankInfo(level: 1,  name: "名もなき市民",             followers: "0〜99",          replies: "3〜5",   haters: "なし",     likes: "100〜280",         regularFollowerLimit: 1),
    RankInfo(level: 2,  name: "クラスの人気者",           followers: "100〜499",       replies: "4〜7",   haters: "なし",     likes: "270〜770",         regularFollowerLimit: 1),
    RankInfo(level: 3,  name: "プチ・インフルエンサー",    followers: "500〜1,999",     replies: "4〜7",   haters: "なし",     likes: "510〜1,470",       regularFollowerLimit: 1),
    RankInfo(level: 4,  name: "マイクロ・インフルエンサー", followers: "2,000〜9,999",   replies: "5〜8",   haters: "最大1",    likes: "1,500〜3,990",     regularFollowerLimit: 2),
    RankInfo(level: 5,  name: "ネットのカリスマ",          followers: "10,000〜49,999", replies: "5〜9",   haters: "最大1",    likes: "3,600〜10,150",    regularFollowerLimit: 2),
    RankInfo(level: 6,  name: "オピニオンリーダー",        followers: "50,000〜199,999", replies: "7〜10",  haters: "最大1",    likes: "10,500〜28,000",   regularFollowerLimit: 2),
    RankInfo(level: 7,  name: "時代の寵児",               followers: "200,000〜999,999", replies: "7〜12", haters: "最大2",    likes: "45,000〜119,000",  regularFollowerLimit: 3),
    RankInfo(level: 8,  name: "宗派の祖",                 followers: "1,000,000〜4,999,999", replies: "8〜13", haters: "最大2", likes: "114,000〜294,000", regularFollowerLimit: 3),
    RankInfo(level: 9,  name: "預言者",                   followers: "5,000,000〜19,999,999", replies: "9〜14", haters: "最大2", likes: "270,000〜770,000", regularFollowerLimit: 3),
    RankInfo(level: 10, name: "デジタル・ゴッド",          followers: "20,000,000〜",   replies: "10〜16", haters: "最大3",    likes: "450,000〜2,100,000", regularFollowerLimit: 3),
]

struct RankGuideSection: View {
    @EnvironmentObject var appState: AppState
    let currentRank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ランク一覧")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)

            ForEach(rankData, id: \.level) { info in
                let isCurrent = info.level == currentRank
                let isNext = info.level == currentRank + 1
                let isPast = info.level < currentRank
                let isHidden = info.level > currentRank + 1

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RankArtwork(rank: info.level)
                            .frame(width: 44, height: 44)
                            .opacity(isHidden ? 0.12 : 1)
                        Text("Lv.\(info.level)")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(isCurrent ? StatsTheme.hotPink : (isNext ? StatsTheme.cyan : (isPast ? StatsTheme.cyan : .gray.opacity(0.3))))
                        Text(isHidden ? LocalizedStringKey("？？？") : LocalizedStringKey(info.name))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isCurrent ? .white : (isNext ? .white.opacity(0.8) : (isPast ? .white.opacity(0.8) : .gray.opacity(0.3))))
                        Spacer()
                        if isCurrent {
                            Text("NOW")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(StatsTheme.hotPink)
                                .cornerRadius(6)
                        } else if isNext {
                            Text("NEXT")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(StatsTheme.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(StatsTheme.cyan.opacity(0.15))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(StatsTheme.cyan.opacity(0.3), lineWidth: 1))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        RankDetailLabel(icon: "person.2.fill", text: isHidden ? "???" : info.followers, dimmed: isHidden)
                        RankDetailLabel(icon: "bubble.left.fill", text: isHidden ? "???" : info.replies, dimmed: isHidden)
                        RankDetailLabel(icon: "heart.fill", text: isHidden ? "???" : info.likes, dimmed: isHidden)
                    }

                    HStack(spacing: 16) {
                        RankDetailLabel(
                            icon: "flame.fill",
                            text: isHidden
                                ? appState.text("アンチ: ???", "Haters: ???")
                                : appState.text("アンチ: \(info.haters)", "Haters: \(info.hatersEnglish)"),
                            dimmed: isHidden
                        )
                        RankDetailLabel(
                            icon: "star.fill",
                            text: isHidden
                                ? appState.text("常連: ???", "Regulars: ???")
                                : appState.text("常連: 最大\(info.regularFollowerLimit)人", "Regulars: up to \(info.regularFollowerLimit)"),
                            dimmed: isHidden
                        )
                    }
                }
                .padding(16)
                .background(
                    isCurrent
                        ? StatsTheme.hotPink.opacity(0.08)
                        : (isNext ? StatsTheme.cyan.opacity(0.04) : Color.white.opacity(isHidden ? 0.008 : 0.03))
                )
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCurrent ? StatsTheme.hotPink.opacity(0.3) : (isNext ? StatsTheme.cyan.opacity(0.15) : Color.clear), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

struct RankDetailLabel: View {
    let icon: String
    let text: String
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(dimmed ? .gray.opacity(0.3) : StatsTheme.cyan.opacity(0.7))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(dimmed ? .gray.opacity(0.3) : .white.opacity(0.6))
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .tracking(2)
            
            Text(value)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospaced()
                .neonShadow(color: color, radius: 8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(color.opacity(0.1))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct ProfileView: View {
    var onReplayGuide: ((GuideScreen) -> Void)? = nil
    var guide: HomeGuideCoordinator? = nil
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var storeManager: StoreManager
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isEditingName = false
    @State private var isEditingBio = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var followerPendingRemoval: RegularFollower?
    #if DEBUG
    @State private var showsOnboardingReplay = false
    #endif

    private var onboardingReplayPresented: Bool {
        #if DEBUG
        showsOnboardingReplay
        #else
        false
        #endif
    }
    
    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 0) {
                // Header Image
                ZStack(alignment: .bottomLeading) {
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(LinearGradient(gradient: Gradient(colors: [Theme.deepPurple, Theme.purpleAccent.opacity(0.55), .black]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        LottieAnimationUIView(name: "Technology isometric ai robot brain (1)")
                            .frame(height: 120)
                            .opacity(0.24)
                            .padding(.bottom, 5)
                    }
                    .frame(height: 180)
                    .clipped()
                    
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        ZStack {
                            if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AsyncImage(url: URL(string: Theme.myAvatar)) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color.gray)
                                }
                            }
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 6))
                        .overlay(
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .background(Circle().fill(Theme.hotPink))
                                .offset(x: 30, y: 30)
                        )
                    }
                    .homeGuideTarget(.profileAvatar)
                    .offset(x: 24, y: 45)
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                DispatchQueue.main.async {
                                    guard selectedItem == newItem else { return }
                                    appState.userAvatarData = data
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if isEditingName {
                            TextField("ユーザー名", text: $appState.userName, onCommit: { isEditingName = false })
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            Text(appState.userName)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: { withAnimation { isEditingName.toggle() } }) {
                            Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.title2)
                                .foregroundColor(Theme.hotPink)
                        }
                    }
                    
                    Text("ID: \(appState.userId)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    HStack(alignment: .top) {
                        if isEditingBio {
                            TextEditor(text: $appState.userBio)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .frame(minHeight: 80)
                        } else {
                            Text(appState.userBio)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .lineSpacing(6)
                        }
                        
                        Spacer()
                        
                        Button(action: { withAnimation { isEditingBio.toggle() } }) {
                            Image(systemName: isEditingBio ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 4)
                    }
                    

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .homeGuideTarget(.profileIdentity)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CURRENT RANK")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(Theme.lavender.opacity(0.75))
                                .tracking(1.6)
                            Text(appState.rankName)
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.hotPink)
                    }

                    if let nextRank = appState.nextRankFollowers {
                        ProgressView(value: Double(appState.followers), total: Double(nextRank))
                            .tint(Theme.purpleAccent)
                        Text(appState.text("次のランクまであと \(max(0, nextRank - appState.followers)) 人", "\(max(0, nextRank - appState.followers)) followers to the next rank"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
                .background(Theme.aiCardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.subtleBorder, lineWidth: 1))
                .homeGuideTarget(.profileRank)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REGULAR FOLLOWERS")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.gray)
                                .tracking(2)
                            Text("常連AIフォロワー")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text("\(appState.regularFollowers.count) / \(appState.maxRegularFollowers)")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(Theme.lavender)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.purpleAccent.opacity(0.18))
                            .cornerRadius(10)
                    }

                    if appState.regularFollowers.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "star.circle")
                                .font(.system(size: 28))
                                .foregroundColor(.gray.opacity(0.6))
                            Text("返信右上の☆ボタンから、覚えてほしいフォロワーを常連にできます。")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .background(Theme.deepPurple.opacity(0.65))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.subtleBorder, lineWidth: 1))
                    } else {
                        ForEach(appState.regularFollowers) { follower in
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: follower.avatarURL)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .foregroundColor(Theme.hotPink)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.purpleAccent.opacity(0.75), lineWidth: 2))

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text("@\(follower.authorName)")
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundColor(.white)
                                        Text("REGULAR")
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundColor(Theme.lavender)
                                    }
                                    Text(follower.recentInteractions.last ?? appState.text("次の投稿から記憶を使って返信します", "Memory will be used starting with your next post."))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button("解除") {
                                    followerPendingRemoval = follower
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.red.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .padding(14)
                            .background(Theme.aiCardBackground.opacity(0.86))
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.subtleBorder, lineWidth: 1))
                        }
                    }

                    if appState.maxRegularFollowers < 3 {
                        Text(
                            appState.maxRegularFollowers == 1
                                ? appState.text("Lv.4で常連枠が2人に増えます", "Reach Lv.4 to unlock 2 regular slots.")
                                : appState.text("Lv.7で常連枠が3人に増えます", "Reach Lv.7 to unlock 3 regular slots.")
                        )
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.lavender.opacity(0.85))
                    }
                }
                .homeGuideTarget(.profileRegulars)
                .padding(.horizontal, 32)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)
                
                // Settings Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("SETTINGS")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(2)

                    #if DEBUG
                    Button { showsOnboardingReplay = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(Theme.lavender)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.text("オンボーディングを再生", "Replay onboarding"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(appState.text("DEBUG・現在のデータは保持されます", "DEBUG · Your current data is preserved"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.lavender)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Theme.aiCardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.subtleBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.replayOnboarding")
                    #endif

                    if let onReplayGuide {
                        Menu {
                            ForEach(GuideScreen.allCases) { screen in
                                Button(screen.title(japanese: appState.appLanguage == .japanese)) {
                                    onReplayGuide(screen)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(Theme.lavender)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appState.text("使い方ガイド", "How to use UPME"))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(appState.text("見直したい画面を選べます", "Choose a screen to replay"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.lavender)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Theme.aiCardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.subtleBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.homeGuide")
                        .homeGuideTarget(.profileGuide)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("表示言語")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("UIと今後のAI返信に使用します")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "globe")
                                .foregroundColor(Theme.lavender)
                        }

                        Picker("表示言語", selection: $appState.appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(14)
                    .background(Theme.aiCardBackground.opacity(0.7))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.subtleBorder, lineWidth: 1))
                    .homeGuideTarget(.profileSettings)
                    
                    Toggle(isOn: $appState.isHaterEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アンチ・炎上の発生")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("高ランク到達時のアンチ登場をON/OFFします")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.hotPink))
                    .homeGuideTarget(.profileHaters)
                    
                    VStack(alignment: .leading, spacing: 12) {
                    if !storeManager.isAdsRemoved {
                        if let product = storeManager.products.first {
                            Button(action: {
                                Task {
                                    await storeManager.purchase(product)
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("広告を消す (買い切り)")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("バナー広告を非表示にします")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.system(size: 15, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Theme.cyan.opacity(0.2))
                                        .foregroundColor(Theme.cyan)
                                        .cornerRadius(8)
                                }
                            }
                            
                            Button(action: {
                                Task {
                                    await storeManager.restorePurchases()
                                }
                            }) {
                                Text("購入の復元")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 4)
                        } else {
                            Text("広告削除の読み込み中...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    } else {
                        HStack {
                            Text("広告を消す (買い切り)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("購入済み")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .homeGuideTarget(.profileAds)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)

                VStack(alignment: .leading, spacing: 16) {
                    Text("SUPPORT")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(2)

                    Link(destination: URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSc4bsVO9vTgucDU0w-RviLQK4Ap1tQxD45JlZ4OZplu35ouRw/viewform?hl=\(appState.appLanguage == .japanese ? "ja" : "en")")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(Theme.hotPink)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.text("お問い合わせ", "Contact Us"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Text(appState.text("不具合の報告・ご意見・ご要望はこちら", "Report a problem or share feedback"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.lavender)
                        }
                        .padding(14)
                        .background(Theme.aiCardBackground.opacity(0.7))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.subtleBorder, lineWidth: 1))
                    }
                    .homeGuideTarget(.profileContact)
                }
                .padding(.horizontal, 32)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)

                VStack(alignment: .leading, spacing: 16) {
                    Text("LEGAL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(2)

                    Button(action: { showTerms = true }) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.gray)
                            Text("利用規約")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }

                    Button(action: { showPrivacy = true }) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.gray)
                            Text("プライバシーポリシー")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
                .homeGuideTarget(.profileLegal)
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 40)
        }
        .refreshable {
            appState.fetchUser()
        }
        .task(id: guide?.activeStep) {
            guard let step = guide?.activeStep, step.screen == .profile else { return }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(step, anchor: .center) }
        }
        }
        .homeGuideViewport()
        #if DEBUG
        .fullScreenCover(isPresented: $showsOnboardingReplay) {
            DebugOnboardingReplayView(source: appState)
        }
        #endif
        .preference(key: HomeGuideModalPreference.self, value: showTerms || showPrivacy || followerPendingRemoval != nil || onboardingReplayPresented)
        .alert(item: $followerPendingRemoval) { follower in
            Alert(
                title: Text(appState.text("@\(follower.authorName)の常連を解除しますか？", "Remove @\(follower.authorName) as a regular?")),
                message: Text(appState.text("このフォロワーの会話記憶も端末から削除されます。", "This follower’s conversation memory will also be deleted from this device.")),
                primaryButton: .destructive(Text("解除する")) {
                    appState.removeRegularFollower(id: follower.id)
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        }
        .sheet(isPresented: $showTerms) {
            LegalTextView(
                title: appState.text("利用規約", "Terms of Service"),
                text: appState.appLanguage == .japanese ? termsOfServiceText : termsOfServiceTextEnglish
            )
        }
        .sheet(isPresented: $showPrivacy) {
            LegalTextView(
                title: appState.text("プライバシーポリシー", "Privacy Policy"),
                text: appState.appLanguage == .japanese ? privacyPolicyText : privacyPolicyTextEnglish
            )
        }
    }
}

struct LegalTextView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(6)
                    .padding(24)
            }
            .background(Theme.bgDeepBlack.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Theme.hotPink)
                }
            }
        }
    }
}

private let termsOfServiceText = """
UPME! | AI SNS 利用規約

最終更新日: 2026年3月28日

第1条（適用）
本規約は、UPME! | AI SNS（以下「本アプリ」）の利用に関する条件を定めるものです。ユーザーは、本アプリを利用することにより、本規約に同意したものとみなされます。

第2条（サービスの内容）
本アプリは、ユーザーが投稿したテキストに対してAI（人工知能）が仮想的なフォロワーの返信を生成するエンターテインメントアプリです。
・表示されるフォロワー、いいね数、返信はすべてAIによる架空のものであり、実在の人物・団体とは一切関係ありません。
・本アプリ内での数値（フォロワー数、いいね数等）は本アプリ内でのみ有効であり、現実のSNSとは無関係です。

第3条（禁止事項）
ユーザーは、以下の行為を行ってはなりません。
1. 個人情報（本名、住所、電話番号、メールアドレス等）を投稿する行為
2. 第三者の権利を侵害する内容を投稿する行為
3. 違法行為、公序良俗に反する内容を投稿する行為
4. 本アプリのサーバーやネットワークに過度な負荷をかける行為
5. 本アプリの運営を妨害する行為

第4条（知的財産権）
本アプリに関するすべての知的財産権は、運営者に帰属します。AIが生成した返信の著作権についても、ユーザーに帰属するものではありません。

第5条（免責事項）
1. 運営者は、本アプリの提供の中断、停止、終了、利用不能について、いかなる責任も負いません。
2. AIが生成する返信の内容について、運営者は一切の責任を負いません。
3. 本アプリの利用により生じた損害について、運営者は一切の責任を負いません。

第6条（サービスの変更・終了）
運営者は、事前の通知なく、本アプリの内容を変更し、または提供を終了することができるものとします。

第7条（規約の変更）
運営者は、必要に応じて本規約を変更できるものとします。変更後の規約は、本アプリ内に掲示した時点で効力を生じます。
"""

let privacyPolicyText = """
UPME! | AI SNS プライバシーポリシー

最終更新日: 2026年8月19日

1. はじめに
UPME! | AI SNS（以下「本アプリ」）は、ユーザーのプライバシーを尊重し、個人情報の保護に努めます。本ポリシーでは、本アプリが取り扱う情報について説明します。

2. ユーザーの同意について
本アプリの初回起動時に、下記「3. 情報の利用目的」と「4. 第三者への提供」に記載する通り、インターネット上のサーバー（OpenAI）へデータが送信される旨を明示し、ユーザーから同意を得た上でサービスを提供します。

3. 収集する情報
本アプリでは、以下の情報を取り扱います。

【自動的に生成・保存される情報】
・ユーザーID（アプリ初回起動時に端末上で自動生成されるランダムなUUID）
・アプリ内の進行データ（フォロワー数、投稿数、ランク、オンボーディング完了フラグ）
・常連AIフォロワー情報（名前、アバターURL、会話から生成された記憶と直近のやり取りの要約 — 端末内にのみ保存）

【利用状況の計測情報】
・匿名のユーザーIDに紐づく、アプリ起動・日次利用・画面閲覧・投稿・AI返信・ランクアップ・常連設定のイベント
・投稿・返信本文、添付画像、ユーザー名、自己紹介文などの内容は利用状況の計測サービスへ送信しません

【ユーザーが入力する情報】
・投稿・返信テキスト（AI返信生成のためサーバーに送信されます）
・投稿に添付した画像（任意。選択した場合のみAI返信生成のためサーバーに送信されます）
・プロフィール情報（ユーザー名、自己紹介文、アバター画像 — 端末内にのみ保存、サーバーへの送信はしません）

4. 情報の利用目的
・投稿・返信テキスト・画像: AI返信を生成するために、OpenAI社のAPIへ送信されます。送信されたデータはAI処理後、本アプリのサーバーには保存されません。
・常連AIフォロワーの会話記憶: 過去のやり取りを踏まえた返信を生成するため、常連設定中のみ投稿とあわせてOpenAI社のAPIへ送信されます。本アプリのサーバーには保存されません。
・ユーザーID・進行データ: アプリの状態を管理し、端末間でのデータ同期に利用します。

・利用状況の計測情報: アプリの継続利用状況、機能ごとの利用状況、離脱箇所を把握し、サービス改善に利用します。計測にはPostHogを使用します。

5. 第三者への提供
・投稿・返信テキストおよび添付画像は、AI返信生成の目的でOpenAI社のAPIに送信されます。
・常連設定中は、常連AIフォロワーの会話記憶と直近のやり取りの要約も、継続性のあるAI返信を生成する目的でOpenAI社のAPIに送信されます。
・OpenAI社のデータ取り扱いについては、同社のプライバシーポリシー (https://openai.com/policies/privacy-policy) をご確認ください。同社は本アプリと同等以上のプライバシー保護基準を適用しています。
・利用状況の計測情報は、計測サービス提供者であるPostHogへ送信されます。PostHogのデータ取り扱いについては、同社のプライバシーポリシー (https://posthog.com/privacy) をご確認ください。
・上記を除き、ユーザーの情報を第三者に提供・販売することはありません。

6. データの保存
・投稿データ（テキスト・返信）は端末内にのみ保存され、直近5件を超えるデータは自動的に削除されます。
・常連AIフォロワーの設定と会話記憶は端末内にのみ保存され、プロフィール画面から常連を解除すると削除されます。
・サーバー（Supabase）には、ユーザーID・フォロワー数・投稿数・オンボーディングフラグのみが保存されます。

7. データの削除
・アプリをアンインストールすることで、端末内のすべてのデータが削除されます。
・サーバー上のデータの削除を希望される場合は、運営者までご連絡ください。

8. お子様のプライバシー
本アプリは、13歳未満のお子様を対象としていません。

9. ポリシーの変更
本ポリシーは、必要に応じて改定されることがあります。重要な変更がある場合は、アプリ内で通知します。

10. お問い合わせ
本ポリシーに関するご質問は、アプリの運営者までお問い合わせください。
"""

private let termsOfServiceTextEnglish = """
UPME! | AI SNS Terms of Service

Last updated: March 28, 2026

1. Scope
These Terms govern use of UPME! | AI SNS (the “App”). By using the App, you agree to these Terms.

2. Service
The App is an entertainment service in which artificial intelligence generates replies from fictional followers to text posted by users.
• All followers, likes, and replies shown in the App are fictional and AI-generated. They are not connected to real people or organizations.
• Follower counts, likes, and other values are valid only inside the App and have no relationship to real social networks.

3. Prohibited Conduct
You must not:
1. Post personal information such as a real name, address, phone number, or email address.
2. Post content that infringes the rights of another party.
3. Post illegal content or content contrary to public order and morals.
4. Place an excessive load on the App’s servers or networks.
5. Interfere with operation of the App.

4. Intellectual Property
All intellectual property rights related to the App belong to the operator. Copyright in AI-generated replies does not transfer to users.

5. Disclaimer
The operator is not liable for interruption, suspension, termination, or unavailability of the App; for the content of AI-generated replies; or for damages arising from use of the App.

6. Changes and Termination
The operator may change or discontinue the App without prior notice.

7. Changes to These Terms
The operator may update these Terms when necessary. Updated Terms take effect when posted in the App.
"""

let privacyPolicyTextEnglish = """
UPME! | AI SNS Privacy Policy

Last updated: August 19, 2026

1. Introduction
UPME! | AI SNS (the “App”) respects user privacy and works to protect personal information. This Policy explains the information handled by the App.

2. Consent
On first launch, the App explains that data is sent to internet services, including OpenAI, for the purposes described below. The service is provided after the user gives consent.

3. Information We Handle
Automatically generated or stored information:
• A random user ID generated on the device at first launch.
• Progress data such as follower count, post count, rank, and onboarding status.
• Regular AI follower information, including names, avatar URLs, memories generated from conversations, and summaries of recent interactions. This is stored only on the device.

Usage analytics:
• Events linked to an anonymous user ID, including launches, daily activity, screen views, posts, AI replies, rank-ups, and regular-follower settings.
• Post and reply text, attached images, user names, and profile biographies are not sent to the analytics service.

User-provided information:
• Post and reply text, sent to the server to generate AI replies.
• Images attached to posts, sent only when selected and only to generate AI replies.
• Profile information, including user name, biography, and avatar, is stored only on the device and is not sent to the server.

4. How Information Is Used
• Post text, reply text, and selected images are sent to the OpenAI API to generate AI replies. The App’s server does not retain this data after processing.
• While a regular AI follower is enabled, its conversation memory is sent with the post to OpenAI to create continuous replies. The App’s server does not retain this memory.
• User ID and progress data are used to manage app state and synchronization.
• Usage analytics are used to understand retention, feature usage, and drop-off points. PostHog provides the analytics service.

5. Third Parties
Post and reply text, selected images, and enabled regular-follower memory may be sent to OpenAI solely to generate AI replies. Usage analytics are sent to PostHog. Except for these purposes, user information is not provided or sold to third parties.
OpenAI privacy policy: https://openai.com/policies/privacy-policy
PostHog privacy policy: https://posthog.com/privacy

6. Storage
• The five most recent posts and their replies are stored only on the device.
• Regular-follower settings and memories are stored only on the device and are deleted when the follower is removed from the profile screen.
• Supabase stores only the user ID, follower count, post count, and onboarding status.

7. Deletion
Uninstalling the App deletes all data stored on the device. Contact the operator to request deletion of server-side data.

8. Children
The App is not intended for children under 13.

9. Policy Changes
This Policy may be revised when necessary. Important changes will be announced in the App.

10. Contact
Contact the App operator with questions about this Policy.
"""
