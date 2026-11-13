import Foundation
import Combine

enum GuideScreen: String, CaseIterable, Codable, Identifiable {
    case home, post, stats, profile

    var id: String { rawValue }

    func title(japanese: Bool) -> String {
        switch self {
        case .home: return japanese ? "ホーム" : "Home"
        case .post: return japanese ? "投稿" : "Post"
        case .stats: return japanese ? "統計" : "Statistics"
        case .profile: return japanese ? "プロフィール" : "Profile"
        }
    }
}

enum HomeGuideStep: String, CaseIterable, Codable, Identifiable {
    case compose, reactions, buzz, aiReply, reply, regular
    case postEditor, postImage, postSubmit
    case statsRank, statsBenefits, statsSummary, statsRankList
    case profileAvatar, profileIdentity, profileRank, profileRegulars, profileSettings
    case profileSettingsEntry
    // Keep the old settings IDs decodable so saved guide progress is not discarded.
    case profileHaters, profileAds, profileContact, profileLegal, profileGuide

    var id: String { rawValue }

    func title(japanese: Bool) -> String {
        switch self {
        case .postEditor: return japanese ? "投稿を書く" : "Write a post"
        case .postImage: return japanese ? "写真を添える" : "Add a photo"
        case .postSubmit: return japanese ? "投稿する" : "Post it"
        case .statsRank: return japanese ? "現在のランク" : "Current rank"
        case .statsBenefits: return japanese ? "ランクの特典" : "Rank benefits"
        case .statsSummary: return japanese ? "あなたの記録" : "Your activity"
        case .statsRankList: return japanese ? "ランク一覧" : "All ranks"
        case .profileAvatar: return japanese ? "プロフィール画像" : "Profile photo"
        case .profileIdentity: return japanese ? "プロフィール" : "Your profile"
        case .profileRank: return japanese ? "現在のランク" : "Current rank"
        case .profileRegulars: return japanese ? "常連AI" : "Regular AIs"
        case .profileSettings: return japanese ? "表示言語" : "Language"
        case .profileSettingsEntry: return japanese ? "設定" : "Settings"
        case .profileHaters: return japanese ? "アンチ設定" : "Hater settings"
        case .profileAds: return japanese ? "広告の非表示" : "Remove ads"
        case .profileContact: return japanese ? "お問い合わせ" : "Contact us"
        case .profileLegal: return japanese ? "規約とプライバシー" : "Terms & privacy"
        case .profileGuide: return japanese ? "使い方ガイド" : "How to use UPME"
        case .reactions: return japanese ? "リアクション" : "Reactions"
        case .buzz: return japanese ? "バズ" : "Going viral"
        case .aiReply: return japanese ? "AIの返信" : "AI replies"
        case .reply: return japanese ? "AIとの会話" : "Conversations"
        case .regular: return japanese ? "常連AI" : "Regular AIs"
        case .compose: return japanese ? "投稿" : "Posts"
        }
    }

    func detail(japanese: Bool) -> String {
        switch self {
        case .postEditor:
            return japanese ? "ここに、今日の出来事やいまの気持ちを書けます。" : "Write about your day or how you feel here."
        case .postImage:
            return japanese ? "写真を添えて投稿できます。" : "Add a photo to your post."
        case .postSubmit:
            return japanese ? "投稿すると、AIフォロワーから返信が届きます。" : "Post to receive replies from your AI followers."
        case .statsRank:
            return japanese ? "投稿を重ねるとフォロワーが増え、ランクが上がります。" : "Your followers and rank grow as you post."
        case .statsBenefits:
            return japanese ? "ランクごとに、投稿への反応や常連枠が変わります。" : "Your rank affects post reactions and regular follower slots."
        case .statsSummary:
            return japanese ? "AIフォロワーと投稿数を確認できます。いいね・返信は保存済みの投稿の集計です。" : "See your AI followers and post count. Likes and replies are counted from saved posts."
        case .statsRankList:
            return japanese ? "ランク一覧から、各ランクの条件と特典を見られます。" : "Open the rank list to see each rank’s requirements and benefits."
        case .profileAvatar:
            return japanese ? "画像をタップして、プロフィール写真を変更できます。" : "Tap your photo to change your profile picture."
        case .profileIdentity:
            return japanese ? "名前やプロフィールを編集できます。" : "Edit your name and profile here."
        case .profileRank:
            return japanese ? "現在のランクと、次のランクまでの進み具合です。" : "See your current rank and progress to the next one."
        case .profileRegulars:
            return japanese ? "常連AIは会話を覚えて返信します。ここから解除もできます。" : "Regular AIs remember your conversations. You can remove them here."
        case .profileSettings:
            return japanese ? "アプリの表示と、今後のAI返信に使う言語を切り替えられます。" : "Choose the language for the app and future AI replies."
        case .profileSettingsEntry:
            return japanese ? "言語やアンチの切り替え、使い方ガイドの再表示は、ここから開く設定画面で行えます。" : "Open Settings to change the language, toggle hater replies, or replay screen guides."
        case .profileHaters:
            return japanese ? "高ランクで登場するアンチを、ON・OFFで切り替えられます。" : "Turn hater replies on or off for higher ranks."
        case .profileAds:
            return japanese ? "広告を非表示にする購入や、購入状況を確認できます。" : "Purchase ad removal or check your purchase status here."
        case .profileContact:
            return japanese ? "不具合の報告や、ご意見・ご要望を送れます。" : "Report a problem or send feedback and requests."
        case .profileLegal:
            return japanese ? "利用規約と、個人情報の取り扱いを確認できます。" : "Read the terms of service and how your personal information is handled."
        case .profileGuide:
            return japanese ? "各画面のガイドを、いつでもここから見直せます。" : "Replay any screen guide here, whenever you like."
        case .reactions:
            return japanese ? "投稿に届いた、いいねや返信の数を確認できます。" : "See how many likes and replies your post has received."
        case .buzz:
            return japanese ? "バズると、いいねはランク上限の5倍、フォロワーの増加は3倍、AI返信は2倍になります。バズった後は24時間、通常の反応になります。" : "When a post goes viral, likes reach 5× your rank’s maximum, follower gains 3×, and AI replies 2×. Posts receive normal reactions for the next 24 hours."
        case .aiReply:
            return japanese ? "あなたの投稿に、AIフォロワーからの返信が届きます。" : "Replies from your AI followers appear here after you post."
        case .reply:
            return japanese ? "このAIに1回だけ返信できます。返信後は「会話」から続きを確認できます。" : "You can reply once to this AI. After replying, open Thread to see the conversation."
        case .regular:
            return japanese ? "常連AIは、これまでの会話を踏まえて返信してくれます。人数の上限はランクによって変わります。" : "Regular AIs remember past conversations when they reply. Your rank determines how many you can add."
        case .compose:
            return japanese ? "ここをタップして、今日の出来事やいまの気持ちを投稿できます。ひとことでも大丈夫です。" : "Tap here to share a moment from your day or how you feel. Even a few words are enough."
        }
    }

    static func ordered(for screen: GuideScreen) -> [HomeGuideStep] {
        switch screen {
        case .home: return [.compose, .reactions, .buzz, .aiReply, .reply, .regular]
        case .post: return [.postEditor, .postImage, .postSubmit]
        case .stats: return [.statsRank, .statsBenefits, .statsSummary, .statsRankList]
        case .profile: return [.profileAvatar, .profileIdentity, .profileRegulars]
        }
    }

    var screen: GuideScreen {
        switch self {
        case .compose, .reactions, .buzz, .aiReply, .reply, .regular: return .home
        case .postEditor, .postImage, .postSubmit: return .post
        case .statsRank, .statsBenefits, .statsSummary, .statsRankList: return .stats
        case .profileAvatar, .profileIdentity, .profileRank, .profileRegulars, .profileSettingsEntry, .profileSettings,
             .profileHaters, .profileAds, .profileContact, .profileLegal, .profileGuide: return .profile
        }
    }
}

/// Only acknowledged steps are saved. Missing reply controls remain pending.
final class HomeGuideProgressStore {
    private struct Progress: Codable {
        var acknowledged: Set<HomeGuideStep> = []
        var skipped = false
        var skippedScreens: Set<GuideScreen> = []

        private enum CodingKeys: String, CodingKey { case acknowledged, skipped, skippedScreens }

        init(acknowledged: Set<HomeGuideStep> = [], skipped: Bool = false, skippedScreens: Set<GuideScreen> = []) {
            self.acknowledged = acknowledged
            self.skipped = skipped
            self.skippedScreens = skippedScreens
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            acknowledged = try values.decodeIfPresent(Set<HomeGuideStep>.self, forKey: .acknowledged) ?? []
            skipped = try values.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
            skippedScreens = try values.decodeIfPresent(Set<GuideScreen>.self, forKey: .skippedScreens) ?? []
        }
    }

    private let defaults: UserDefaults
    private let key: String
    private let persists: Bool
    private var progress: Progress

    init(defaults: UserDefaults = .standard, key: String = "upme.homeGuide.v1", persists: Bool = true) {
        self.defaults = defaults
        self.key = key
        self.persists = persists
        if persists, let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(Progress.self, from: data) {
            progress = saved
        } else {
            progress = Progress()
        }
    }

    func pending(for screen: GuideScreen, in available: [HomeGuideStep]) -> [HomeGuideStep] {
        guard !progress.skipped, !progress.skippedScreens.contains(screen) else { return [] }
        return HomeGuideStep.ordered(for: screen).filter { available.contains($0) && !progress.acknowledged.contains($0) }
    }

    func acknowledge(_ step: HomeGuideStep) {
        progress.acknowledged.insert(step)
        save()
    }

    func skip(_ screen: GuideScreen) {
        progress.skippedScreens.insert(screen)
        save()
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class HomeGuideCoordinator: ObservableObject {
    @Published private(set) var activeStep: HomeGuideStep?
    @Published private(set) var steps: [HomeGuideStep] = []
    @Published private(set) var index = 0
    @Published private(set) var replayRevision = 0
    @Published private(set) var showsCompletion = false
    @Published private(set) var screen: GuideScreen = .home

    private let store: HomeGuideProgressStore
    private let automaticEnabled: Bool
    private var previewStart: HomeGuideStep?
    private var manualReplayScreen: GuideScreen?

    var isPresenting: Bool { activeStep != nil || showsCompletion }
    var canGoBack: Bool { index > 0 }
    var isLastStep: Bool { index == steps.count - 1 }

    init(store: HomeGuideProgressStore = HomeGuideProgressStore(), automaticEnabled: Bool = true,
         previewStart: HomeGuideStep? = nil) {
        self.store = store
        self.automaticEnabled = automaticEnabled
        self.previewStart = previewStart
    }

    func presentIfNeeded(screen: GuideScreen, available: [HomeGuideStep]) {
        guard !showsCompletion else { return }
        if let current = activeStep {
            guard self.screen == screen else { endSession(); return }
            // A live post/reply may disappear. Do not count its unseen explanation as read.
            let next = steps.dropFirst(index + 1).first { available.contains($0) }
            steps = steps.filter { available.contains($0) }
            if let newIndex = steps.firstIndex(of: current) {
                index = newIndex
            } else if let next, let nextIndex = steps.firstIndex(of: next) {
                index = nextIndex
                activeStep = next
            } else {
                endSession()
            }
            return
        }
        let replaying = manualReplayScreen == screen
        guard automaticEnabled || replaying else { return }
        let candidates = replaying
            ? HomeGuideStep.ordered(for: screen).filter { available.contains($0) }
            : store.pending(for: screen, in: available)
        guard !candidates.isEmpty else { return }
        self.screen = screen
        steps = candidates
        index = previewStart.flatMap { candidates.firstIndex(of: $0) } ?? 0
        previewStart = nil
        manualReplayScreen = nil
        activeStep = steps[index]
    }

    func next() {
        if showsCompletion {
            endSession()
            return
        }
        guard let current = activeStep else { return }
        store.acknowledge(current)
        if index + 1 < steps.count {
            index += 1
            activeStep = steps[index]
        } else {
            endSession()
            showsCompletion = true
        }
    }

    func back() {
        guard isPresenting, canGoBack else { return }
        index -= 1
        activeStep = steps[index]
    }

    func skip() {
        // Replaying is always available, including after completion or skipping.
        store.skip(screen)
        endSession()
    }

    func requestReplay(for screen: GuideScreen) {
        endSession()
        manualReplayScreen = screen
        self.screen = screen
        replayRevision += 1
    }

    private func endSession() {
        showsCompletion = false
        activeStep = nil
        steps = []
        index = 0
        manualReplayScreen = nil
    }
}
