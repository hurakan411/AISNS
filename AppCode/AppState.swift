import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    static var deviceDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ja") ? .japanese : .english
    }

    var locale: Locale { Locale(identifier: rawValue) }
    var displayName: String { self == .japanese ? "日本語" : "English" }
    var defaultUserName: String { self == .japanese ? "あなた" : "You" }
    var defaultBio: String {
        self == .japanese
            ? "今日も息してるだけでえらい。UPME! | AI SNSで承認欲求の海に溺れるアカウント。"
            : "Just making it through today is enough. An account floating in the sea of validation on UPME! | AI SNS."
    }
}

struct Reply: Identifiable, Equatable, Codable {
    var id: UUID
    let authorName: String
    let text: String
    let img: String
    let isHater: Bool
    let isDefender: Bool
    let regularFollowerId: String?
    let replyToId: UUID?
    let isUserReply: Bool
    var hasUserReply: Bool

    init(
        id: UUID = UUID(),
        authorName: String,
        text: String,
        img: String,
        isHater: Bool,
        isDefender: Bool,
        regularFollowerId: String? = nil,
        replyToId: UUID? = nil,
        isUserReply: Bool = false,
        hasUserReply: Bool = false
    ) {
        self.id = id
        self.authorName = authorName
        self.text = text
        self.img = img
        self.isHater = isHater
        self.isDefender = isDefender
        self.regularFollowerId = regularFollowerId
        self.replyToId = replyToId
        self.isUserReply = isUserReply
        self.hasUserReply = hasUserReply
    }

    private enum CodingKeys: String, CodingKey {
        case id, authorName, text, img, isHater, isDefender, regularFollowerId
        case replyToId, isUserReply, hasUserReply
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        authorName = try container.decode(String.self, forKey: .authorName)
        text = try container.decode(String.self, forKey: .text)
        img = try container.decode(String.self, forKey: .img)
        isHater = try container.decode(Bool.self, forKey: .isHater)
        isDefender = try container.decode(Bool.self, forKey: .isDefender)
        regularFollowerId = try container.decodeIfPresent(String.self, forKey: .regularFollowerId)
        replyToId = try container.decodeIfPresent(UUID.self, forKey: .replyToId)
        isUserReply = try container.decodeIfPresent(Bool.self, forKey: .isUserReply) ?? false
        hasUserReply = try container.decodeIfPresent(Bool.self, forKey: .hasUserReply) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(text, forKey: .text)
        try container.encode(img, forKey: .img)
        try container.encode(isHater, forKey: .isHater)
        try container.encode(isDefender, forKey: .isDefender)
        try container.encodeIfPresent(regularFollowerId, forKey: .regularFollowerId)
        try container.encodeIfPresent(replyToId, forKey: .replyToId)
        try container.encode(isUserReply, forKey: .isUserReply)
        try container.encode(hasUserReply, forKey: .hasUserReply)
    }

    var canReceiveUserReply: Bool {
        !isUserReply && replyToId == nil && !hasUserReply
    }
}

struct RegularFollower: Identifiable, Equatable, Codable {
    let id: String
    let authorName: String
    let avatarURL: String
    var memories: [String]
    var recentInteractions: [String]
    let createdAt: Date
    var lastInteractionAt: Date?
}

enum AddRegularFollowerResult {
    case added
    case alreadyRegistered
    case limitReached(maximum: Int)
}

struct ReplyThread: Identifiable, Equatable, Codable {
    let targetReplyID: UUID
    var replies: [Reply]

    var id: UUID { targetReplyID }
}

/// The generated replies and reward are saved before presentation begins.
struct PostReaction: Codable {
    let environment: String
    let isViral: Bool
    let rank: Int
    let targetLikes: Int
    let followerGain: Int
    let startedAt: Date
    let replyOffsets: [TimeInterval]
    var remainingReplies: [Reply]
    var followersAfter: Int?

    var duration: TimeInterval { max(replyOffsets.last ?? 0, isViral ? 12 : 1) }
    func elapsed(at date: Date) -> TimeInterval { max(0, date.timeIntervalSince(startedAt)) }
    func progress(at date: Date) -> Double {
        let p = min(1, elapsed(at: date) / duration)
        // A quiet start, a fast middle, then a gentle landing.
        guard isViral else { return p }
        if p < 0.25 { return p * 0.2 }
        if p < 0.75 { return 0.05 + (p - 0.25) * 1.7 }
        return 0.9 + (p - 0.75) * 0.4
    }
}

struct PostModel: Identifiable, Codable {
    var id: UUID
    var isOnboarding: Bool
    let content: String
    var imageData: Data?
    var likes: Int
    var replies: [Reply]
    var replyThreads: [ReplyThread]
    var reaction: PostReaction?
    let time: String

    init(
        id: UUID = UUID(),
        content: String,
        imageData: Data?,
        likes: Int,
        replies: [Reply],
        replyThreads: [ReplyThread] = [],
        isOnboarding: Bool = false,
        time: String
    ) {
        self.id = id
        self.isOnboarding = isOnboarding
        self.content = content
        self.imageData = imageData
        self.likes = likes
        self.replies = replies
        self.replyThreads = replyThreads
        self.time = time
    }

    private enum CodingKeys: String, CodingKey {
        case id, isOnboarding, content, imageData, likes, replies, replyThreads, reaction, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isOnboarding = try container.decodeIfPresent(Bool.self, forKey: .isOnboarding) ?? false
        content = try container.decode(String.self, forKey: .content)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        replies = try container.decodeIfPresent([Reply].self, forKey: .replies) ?? []
        replyThreads = try container.decodeIfPresent([ReplyThread].self, forKey: .replyThreads) ?? []
        reaction = try container.decodeIfPresent(PostReaction.self, forKey: .reaction)
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isOnboarding, forKey: .isOnboarding)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(likes, forKey: .likes)
        try container.encode(replies, forKey: .replies)
        try container.encode(replyThreads, forKey: .replyThreads)
        try container.encodeIfPresent(reaction, forKey: .reaction)
        try container.encode(time, forKey: .time)
    }
}

/// Send a small sample of AI wording from several saved posts, excluding the user's own replies.
func recentAIReplyTexts(from posts: [PostModel], excluding postID: UUID? = nil) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for post in posts where post.id != postID {
        var perPost = 0
        for reply in post.replies + post.replyThreads.flatMap(\.replies)
            where !reply.isUserReply && !reply.isHater && !reply.isDefender {
            let text = String(reply.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            result.append(text)
            perPost += 1
            if result.count == 8 { return result }
            if perPost == 3 { break }
        }
    }
    return result
}

/// JSONSerialization 経由の辞書で Bool が NSNumber や文字列になる場合があるため統一して解釈する
private func parseJSONBool(_ value: Any?) -> Bool {
    switch value {
    case let b as Bool:
        return b
    case let i as Int:
        return i != 0
    case let n as NSNumber:
        return n.boolValue
    case let s as String:
        let lower = s.lowercased()
        return lower == "true" || lower == "1" || lower == "yes"
    default:
        return false
    }
}

private func jsonReplyBool(_ r: [String: Any], snake: String, camel: String) -> Bool {
    if r[snake] != nil {
        return parseJSONBool(r[snake])
    }
    return parseJSONBool(r[camel])
}

private enum OnboardingReplyFetchError: String, Error {
    case invalidURL = "invalid_url"
    case network
    case invalidResponse = "invalid_response"
    case emptyReplies = "empty_replies"
}

class AppState: ObservableObject {
    @Published var appLanguage: AppLanguage = {
        guard let saved = UserDefaults.standard.string(forKey: "appLanguage"),
              let language = AppLanguage(rawValue: saved) else {
            return .deviceDefault
        }
        return language
    }() {
        didSet {
            guard !DesignPreview.isActive else { return }
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            if userName == oldValue.defaultUserName {
                userName = appLanguage.defaultUserName
            }
            if userBio == oldValue.defaultBio {
                userBio = appLanguage.defaultBio
            }
            UPMEAnalytics.capture("app_language_changed", properties: ["language": appLanguage.rawValue])
        }
    }

    var locale: Locale { appLanguage.locale }
    var languageCode: String { appLanguage.rawValue }

    func text(_ japanese: String, _ english: String) -> String {
        appLanguage == .japanese ? japanese : english
    }

    @Published var debugText: String = "---"
    @Published var followers: Int = 0 {
        didSet { cacheUserProgress() }
    }
    @Published var totalPosts: Int = 0 {
        didSet { cacheUserProgress() }
    }
    @Published var posts: [PostModel] = [] {
        didSet { if !isInOnboarding { savePosts() } }
    }
    @Published private(set) var regularFollowers: [RegularFollower] = [] {
        didSet { saveRegularFollowers() }
    }
    
    @Published var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            if !DesignPreview.isActive { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
            cacheUserProgress()
        }
    }
    @Published var isInOnboarding: Bool = false
    @Published var onboardingExpectedReplies: Int = 0
    @Published var isRequestingReplies: Bool = false
    @Published var isSubmittingUserReply: Bool = false
    @Published private(set) var expandedReplyThreadIDs: Set<UUID> = []
    @Published private(set) var loadingReplyThreadIDs: Set<UUID> = []
    @Published var replyErrorMessage: String?
    @Published var onboardingFirstReplyReceived: Bool = false
    @Published private(set) var onboardingReplyError: String?
    
    // オンボーディング用プリフェッチ
    private var prefetchedOnboardingReplies: [Reply] = []
    private var onboardingPostFlowID: UUID?
    @Published private(set) var onboardingRepliesRequestInFlight = false
    private var onboardingRepliesResponseFlowID: UUID?
    @Published var prefetchedOnboardingText: String = ""
    
    @Published var userName: String = UserDefaults.standard.string(forKey: "userName") ?? AppLanguage.deviceDefault.defaultUserName {
        didSet { if !DesignPreview.isActive { UserDefaults.standard.set(userName, forKey: "userName") } }
    }
    @Published var userAvatarData: Data? = nil {
        didSet { saveAvatar() }
    }
    @Published var userBio: String = UserDefaults.standard.string(forKey: "userBio") ?? AppLanguage.deviceDefault.defaultBio {
        didSet { if !DesignPreview.isActive { UserDefaults.standard.set(userBio, forKey: "userBio") } }
    }
    
    @Published var isHaterEnabled: Bool = UserDefaults.standard.object(forKey: "isHaterEnabled") as? Bool ?? true {
        didSet {
            guard !DesignPreview.isActive else { return }
            UserDefaults.standard.set(isHaterEnabled, forKey: "isHaterEnabled")
        }
    }
    
    private var likeTimer: AnyCancellable?
    private var replyTimer: AnyCancellable?
    private var reactionTimer: AnyCancellable?
    @Published private(set) var reactionNow = Date()
    private var requestingPostIDs: Set<UUID> = []
    private var fallbackReactions: [UUID: (rank: Int, likes: Int, gain: Int)] = [:]
    private var userProgressSync: UserProgressSync?
    private var applyingUserProgress = false
    private var pendingReplyThreadReplies: [UUID: [Reply]] = [:]
    @Published var hasPendingReplies: Bool = false
    private var pendingReplies: [Reply] = [] {
        didSet { hasPendingReplies = !pendingReplies.isEmpty }
    }
    
    // リプライ連動でいいね・フォロワーを増やすための一時変数
    private var buzzTargetLikes: Int = 0
    private var buzzTargetFollowers: Int = 0
    private var buzzInitialLikes: Int = 0
    private var buzzInitialFollowers: Int = 0
    private var buzzTotalReplies: Int = 0
    private var buzzCurrentReply: Int = 0
    
    // === 演出の調整パラメーター ===
    // 何分かけて「いいね」と「返信」を増やすか（秒数）。例: 5分 = 300.0
    let buzzDurationSeconds: Double = 300.0
    // いいね数がパラパラ上がるUIの間隔（秒数）。滑らかさ重視なら0.5程度
    let buzzUpdateInterval: Double = 0.5
    // ========================
    
    let avatars = [
        "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1554151228-14d9def656e4?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150&h=150&fit=crop"
    ]
    let haterAvatar = "https://images.unsplash.com/photo-1511367461989-f85a21fda167?w=32&h=32&fit=crop"
    private var postsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("posts_v1.json")
    }
    
    private var avatarURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("user_avatar.dat")
    }

    private var regularFollowersURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("regular_followers_v1.json")
    }

    init(restorePersistedState: Bool = true) {
        guard restorePersistedState else { return }
        #if DEBUG && targetEnvironment(simulator)
        if DesignPreview.isActive {
            appLanguage = DesignPreview.argument("--ui-language") == "en" ? .english : .japanese
            hasCompletedOnboarding = true
            userName = text("おんざべ", "Onzabe")
            userBio = text("何気ない日も、ここに残していこう。", "A little space for my everyday moments.")
            let rank = min(10, max(1, Int(DesignPreview.argument("--ui-rank") ?? "3") ?? 3))
            followers = rank == 3 ? 1_482 : RankProgress.thresholds[rank - 1]
            totalPosts = 2
            let first = Reply(authorName: text("ゆき", "Yuki"), text: text("おつかれさま。今日はゆっくり休んでね。", "You made it through today. Hope you get a little time to rest."), img: avatars[0], isHater: false, isDefender: false, regularFollowerId: "preview-yuki")
            let second = Reply(authorName: text("れん", "Ren"), text: text("帰り道に寄り道する時間、いいよね。", "Those little detours on the way home are the best."), img: avatars[1], isHater: false, isDefender: false)
            regularFollowers = [RegularFollower(id: "preview-yuki", authorName: first.authorName, avatarURL: first.img, memories: [], recentInteractions: [text("今日のできごとを話しました", "Talked about your day")], createdAt: Date(), lastInteractionAt: nil)]
            posts = [PostModel(content: text("今日も一日、がんばった。", "Made it through another day."), imageData: nil, likes: 128, replies: [first, second], time: text("今", "Now")), PostModel(content: text("帰り道、ちょっと寄り道。", "A little detour on the way home."), imageData: nil, likes: 256, replies: [], time: text("昨日", "Yesterday"))]
            if DesignPreview.argument("--ui-empty") == "true" { posts = []; totalPosts = 0 }
            if DesignPreview.argument("--ui-no-replies") == "true" {
                for index in posts.indices { posts[index].replies = [] }
            }
            if DesignPreview.argument("--ui-long-post") == "true", let post = posts.first {
                posts[0] = PostModel(id: post.id, content: Array(repeating: post.content, count: 14).joined(separator: "\n"),
                                     imageData: post.imageData, likes: post.likes, replies: post.replies, time: post.time)
            }
            if DesignPreview.argument("--ui-viral") == "true", let post = posts.first {
                posts[0].replies = []
                let previewReplies = (0..<10).map { index in
                    let source = index.isMultiple(of: 2) ? first : second
                    return Reply(authorName: source.authorName, text: source.text, img: source.img,
                                 isHater: false, isDefender: false)
                }
                beginPostReaction(postID: post.id, replies: previewReplies, response: [
                    "is_viral": true, "rank": rank, "likes": 7350, "follower_gain": 1050
                ])
            }
            return
        }
        #endif
        let bio = UserDefaults.standard.string(forKey: "userBio") ?? ""
        if bio.contains("ZEN-KOTEI") || bio.contains("全肯定") {
            let newBio = appLanguage.defaultBio
            UserDefaults.standard.set(newBio, forKey: "userBio")
            self.userBio = newBio
        }
        
        let savedName = UserDefaults.standard.string(forKey: "userName") ?? ""
        if savedName == "みずき（あなた）" {
            UserDefaults.standard.set(appLanguage.defaultUserName, forKey: "userName")
            self.userName = appLanguage.defaultUserName
        }
        
        loadAvatar()
        loadPosts()
        loadRegularFollowers()
        if let baseURL = URL(string: Self.baseUrl) {
            let sync = UserProgressSync(baseURL: baseURL, userID: userId,
                                        onboardingCompleted: hasCompletedOnboarding)
            userProgressSync = sync
            applyUserProgress(sync.progress)
            sync.onProgressChange = { [weak self] progress in self?.applyUserProgress(progress) }
            restorePostReactions()
            sync.refresh()
        }
    }

    private func cacheUserProgress() {
        guard !DesignPreview.isActive, !applyingUserProgress, !isInOnboarding else { return }
        userProgressSync?.updateLocal(followers: followers, totalPosts: totalPosts,
                                      onboardingCompleted: hasCompletedOnboarding)
    }

    private func applyUserProgress(_ progress: UserProgress) {
        applyingUserProgress = true
        defer { applyingUserProgress = false }
        if !hasCompletedOnboarding && progress.hasCompletedOnboarding {
            // The server may confirm completion while the provisional onboarding is playing.
            // Cancel its effects and restore real saved posts before opening Home.
            likeTimer?.cancel()
            replyTimer?.cancel()
            pendingReplies = []
            prefetchedOnboardingReplies = []
            onboardingPostFlowID = nil
            onboardingRepliesResponseFlowID = nil
            onboardingRepliesRequestInFlight = false
            onboardingReplyError = nil
            if isInOnboarding {
                posts = []
                loadPosts()
            }
            isInOnboarding = false
        }
        // Onboarding's simulated followers must not enter the real progress cache.
        guard !isInOnboarding else { return }
        followers = progress.followers
        totalPosts = progress.totalPosts
        hasCompletedOnboarding = progress.hasCompletedOnboarding
        if hasCompletedOnboarding && userProgressSync?.hasReadServer == true {
            UPMEAnalytics.seedPostCount(userID: userId, totalPosts: totalPosts)
        }
    }
    
    private func savePosts() {
        guard !DesignPreview.isActive else { return }
        // Keep unfinished posts until their generated replies and reward are delivered.
        let trimmed = posts.enumerated().filter { index, post in
            index < 5 || requestingPostIDs.contains(post.id)
                || (post.reaction != nil && post.reaction?.followersAfter == nil)
                || (post.reaction?.followersAfter ?? 0) > followers
        }.map(\.element)
        if posts.count != trimmed.count { posts = trimmed }
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: postsURL, options: .atomic)
        }
    }
    
    private func loadPosts() {
        if let data = try? Data(contentsOf: postsURL),
           let decoded = try? JSONDecoder().decode([PostModel].self, from: data) {
            self.posts = decoded
        }
    }
    
    private func saveAvatar() {
        guard !DesignPreview.isActive else { return }
        if let data = userAvatarData {
            try? data.write(to: avatarURL)
        } else {
            try? FileManager.default.removeItem(at: avatarURL)
        }
    }
    
    private func loadAvatar() {
        if let data = try? Data(contentsOf: avatarURL) {
            self.userAvatarData = data
        } else if let fallback = UserDefaults.standard.data(forKey: "userAvatarData") {
            self.userAvatarData = fallback // backward compatible
        }
    }

    private func saveRegularFollowers() {
        guard !DesignPreview.isActive else { return }
        if let data = try? JSONEncoder().encode(regularFollowers) {
            try? data.write(to: regularFollowersURL, options: .atomic)
        }
    }

    private func loadRegularFollowers() {
        guard let data = try? Data(contentsOf: regularFollowersURL),
              let decoded = try? JSONDecoder().decode([RegularFollower].self, from: data) else { return }
        regularFollowers = Array(decoded.prefix(3))
    }
    
    var currentRank: Int {
        if followers >= 20_000_000 { return 10 }
        if followers >= 5_000_000 { return 9 }
        if followers >= 1_000_000 { return 8 }
        if followers >= 200_000 { return 7 }
        if followers >= 50_000 { return 6 }
        if followers >= 10_000 { return 5 }
        if followers >= 2_000 { return 4 }
        if followers >= 500 { return 3 }
        if followers >= 100 { return 2 }
        return 1
    }

    /// Lv.1〜3は1人、Lv.4〜6は2人、Lv.7〜10は3人まで常連にできる。
    var maxRegularFollowers: Int {
        switch currentRank {
        case 1...3: return 1
        case 4...6: return 2
        default: return 3
        }
    }

    func isRegularFollower(_ reply: Reply) -> Bool {
        regularFollowers.contains { follower in
            if let regularID = reply.regularFollowerId {
                return follower.id == regularID
            }
            return follower.authorName == reply.authorName && follower.avatarURL == reply.img
        }
    }

    @discardableResult
    func addRegularFollower(from reply: Reply, postContent: String) -> AddRegularFollowerResult {
        if isRegularFollower(reply) {
            return .alreadyRegistered
        }
        guard regularFollowers.count < maxRegularFollowers else {
            UPMEAnalytics.capture("regular_follower_limit_reached", properties: [
                "rank": currentRank,
                "limit": maxRegularFollowers
            ])
            return .limitReached(maximum: maxRegularFollowers)
        }

        let postSummary = String(postContent.prefix(100))
        let replySummary = String(reply.text.prefix(120))
        let initialInteraction = "投稿「\(postSummary)」に「\(replySummary)」と返信した"
        let follower = RegularFollower(
            id: reply.regularFollowerId ?? UUID().uuidString.lowercased(),
            authorName: reply.authorName,
            avatarURL: reply.img,
            memories: [],
            recentInteractions: [initialInteraction],
            createdAt: Date(),
            lastInteractionAt: Date()
        )
        regularFollowers.append(follower)
        UPMEAnalytics.capture("regular_follower_added", properties: [
            "rank": currentRank,
            "regular_count": regularFollowers.count,
            "regular_limit": maxRegularFollowers
        ])
        return .added
    }

    func removeRegularFollower(id: String) {
        let hadFollower = regularFollowers.contains { $0.id == id }
        regularFollowers.removeAll { $0.id == id }
        if hadFollower {
            UPMEAnalytics.capture("regular_follower_removed", properties: [
                "rank": currentRank,
                "regular_count": regularFollowers.count,
                "regular_limit": maxRegularFollowers
            ])
        }
    }
    
    var rankName: String {
        switch currentRank {
        case 1: return text("Lv.1 名もなき市民", "Lv.1 Unknown Citizen")
        case 2: return text("Lv.2 クラスの人気者", "Lv.2 Class Favorite")
        case 3: return text("Lv.3 プチ・インフルエンサー", "Lv.3 Rising Influencer")
        case 4: return text("Lv.4 マイクロ・インフルエンサー", "Lv.4 Micro Influencer")
        case 5: return text("Lv.5 ネットのカリスマ", "Lv.5 Internet Icon")
        case 6: return text("Lv.6 オピニオンリーダー", "Lv.6 Opinion Leader")
        case 7: return text("Lv.7 時代の寵児", "Lv.7 Voice of the Moment")
        case 8: return text("Lv.8 宗派の祖", "Lv.8 Movement Founder")
        case 9: return text("Lv.9 預言者", "Lv.9 Prophet")
        case 10: return text("Lv.10 デジタル・ゴッド", "Lv.10 Digital God")
        default: return text("名もなき市民", "Unknown Citizen")
        }
    }
    
    var nextRankFollowers: Int? {
        if currentRank >= 10 { return nil }
        let thresholds = [0, 100, 500, 2_000, 10_000, 50_000, 200_000, 1_000_000, 5_000_000, 20_000_000, 20_000_000]
        return thresholds[currentRank]
    }
    
    /// fakeCompose投稿時点でAIにリクエストを送り、返信を事前取得しておく
    func prefetchOnboardingReplies(text: String) {
        guard !onboardingRepliesRequestInFlight else { return }
        prefetchedOnboardingText = text
        prefetchedOnboardingReplies = []
        let postFlowID = UUID()
        onboardingPostFlowID = postFlowID
        onboardingRepliesResponseFlowID = nil
        UPMEAnalytics.capture("onboarding_post_submitted", properties: [
            "post_flow_id": postFlowID.uuidString.lowercased()
        ])
        loadOnboardingReplies(content: text, postFlowID: postFlowID)
    }
    
    func submitOnboardingPost(text: String) {
        isInOnboarding = true
        onboardingFirstReplyReceived = false
        let postFlowID = onboardingPostFlowID ?? UUID()
        onboardingPostFlowID = postFlowID
        let newPost = PostModel(id: postFlowID, content: text, imageData: nil, likes: 0, replies: [], isOnboarding: true, time: self.text("今", "Now"))
        posts = [newPost]
        
        let targetFollowers = Int.random(in: 150000...300000)
        let targetLikes = Int(Double(targetFollowers) * Double.random(in: 5.0...10.0))
        
        buzzInitialLikes = 0
        buzzInitialFollowers = 0
        buzzTargetLikes = targetLikes
        buzzTargetFollowers = targetFollowers
        buzzCurrentReply = 0
        
        var ticks = 0
        let maxTicks = 200
        likeTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            ticks += 1
            let p = min(Double(ticks) / Double(maxTicks), 0.95)
            if !self.posts.isEmpty {
                self.posts[0].likes = Int(Double(targetLikes) * p)
            }
            self.followers = Int(Double(targetFollowers) * p)
        }
        
        if onboardingRepliesResponseFlowID == postFlowID {
            // 取得に成功したプリフェッチ結果だけを再利用する。
            let replies = prefetchedOnboardingReplies
            prefetchedOnboardingReplies = []
            pendingReplies = replies
            startReplyDrainTimer(postFlowID: postFlowID, isOnboarding: true)
        } else if onboardingRepliesRequestInFlight {
            // プリフェッチが進行中。完了時のコールバックが返信表示を開始する。
            return
        } else {
            loadOnboardingReplies(content: text, postFlowID: postFlowID)
        }
    }

    func retryOnboardingReplies() {
        guard isInOnboarding,
              !onboardingRepliesRequestInFlight,
              let post = posts.first, post.isOnboarding else { return }
        loadOnboardingReplies(content: post.content, postFlowID: post.id)
    }

    private func loadOnboardingReplies(content: String, postFlowID: UUID) {
        guard !onboardingRepliesRequestInFlight else { return }
        onboardingRepliesRequestInFlight = true
        onboardingReplyError = nil
        onboardingRepliesResponseFlowID = nil
        fetchAiRepliesBackground(content: content, followers: 20_000_000, postFlowID: postFlowID) { [weak self] result in
            guard let self = self, self.onboardingPostFlowID == postFlowID else { return }
            self.onboardingRepliesRequestInFlight = false
            switch result {
            case .success(let replies):
                self.prefetchedOnboardingReplies = replies
                self.onboardingRepliesResponseFlowID = postFlowID
                if self.isInOnboarding && self.posts.first?.id == postFlowID {
                    self.pendingReplies = replies
                    self.prefetchedOnboardingReplies = []
                    self.startReplyDrainTimer(postFlowID: postFlowID, isOnboarding: true)
                }
            case .failure:
                self.prefetchedOnboardingReplies = []
                self.onboardingRepliesResponseFlowID = nil
                self.onboardingReplyError = self.text(
                    "AIの返信を取得できませんでした。もう一度試すか、このまま始められます。",
                    "Couldn't load AI replies. You can try again or continue to UPME."
                )
                if self.isInOnboarding && self.posts.first?.id == postFlowID {
                    self.likeTimer?.cancel()
                }
            }
        }
    }
    
    func completeOnboarding() {
        likeTimer?.cancel()
        replyTimer?.cancel()
        pendingReplies = []
        isInOnboarding = false
        // posts = [] // オンボの投稿と返信を残す
        followers = 0
        totalPosts = 1
        hasCompletedOnboarding = true
        UPMEAnalytics.seedPostCount(userID: userId, totalPosts: 1)
        var properties: [String: Any] = [
            "rank": currentRank,
            "ai_reply_status": onboardingReplyError != nil ? "failed" : (onboardingFirstReplyReceived ? "received" : "pending")
        ]
        if let postFlowID = posts.first(where: \.isOnboarding)?.id.uuidString.lowercased() {
            properties["post_flow_id"] = postFlowID
        }
        UPMEAnalytics.capture("onboarding_completed", properties: properties)
        onboardingPostFlowID = nil
        onboardingRepliesRequestInFlight = false
        onboardingReplyError = nil
        savePosts()
        syncUser(includeOnboarding: true)
    }
    
    func submitPost(text: String, imageData: Data? = nil) {
        if DesignPreview.isActive {
            posts.insert(PostModel(content: text, imageData: imageData, likes: 0, replies: [], time: self.text("今", "Now")), at: 0)
            totalPosts += 1
            return
        }
        let newPost = PostModel(content: text, imageData: imageData, likes: 0, replies: [], time: self.text("今", "Now"))
        posts.insert(newPost, at: 0)
        
        let rank = currentRank
        var postProperties = UPMEAnalytics.recordNormalPost(userID: userId)
        totalPosts += 1
        postProperties.merge([
            "post_flow_id": newPost.id.uuidString.lowercased(),
            "has_image": imageData != nil,
            "rank": rank,
            "regular_count": regularFollowers.count
        ], uniquingKeysWith: { _, new in new })
        UPMEAnalytics.capture("post_created", properties: postProperties)
        
        // 確定した「累計〇回で昇格」を実現するため、必要な平均獲得フォロワー数を逆算して設定
        let totalFollowers: Int
        switch rank {
        case 1: totalFollowers = Int.random(in: 30...40)     // Avg 35 * 3回 = 105 (→ 100人突破)
        case 2: totalFollowers = Int.random(in: 90...110)    // Avg 100 * 4回 = 400 (前ランク分+105で500人突破)
        case 3: totalFollowers = Int.random(in: 170...210)   // Avg 190 * 8回 = 1520 (前+500で2000人突破)
        case 4: totalFollowers = Int.random(in: 500...570)   // Avg 535 * 15回 = 8025 (前+2000で1万人突破)
        case 5: totalFollowers = Int.random(in: 1200...1450) // Avg 1325 * 30回 = 39750 (前+1万で5万人突破)
        case 6: totalFollowers = Int.random(in: 3500...4000) // Avg 3750 * 40回 = 15万人 (前+5万で20万人突破)
        case 7: totalFollowers = Int.random(in: 15000...17000) // Avg 16000 * 50回 = 80万人 (前+20万で100万人突破)
        case 8: totalFollowers = Int.random(in: 38000...42000) // Avg 40000 * 100回 = 400万人 (前+100万で500万人突破)
        case 9: totalFollowers = Int.random(in: 90000...110000) // Avg 100000 * 150回 = 1500万人 (前+500万で2000万人突破)
        default: totalFollowers = Int.random(in: 150000...300000) // Rank 10以降
        }
        
        // いいねの数はフォロワーの獲得数に対して「3倍〜7倍」のランダムな値で派手に増やす
        let totalLikes = Int(Double(totalFollowers) * Double.random(in: 3.0...7.0))
        
        // リプライ表示と連動して増やすため、目標値を保存しておく
        fallbackReactions[newPost.id] = (rank, totalLikes, totalFollowers)

        // 実APIへ生成リクエスト
        requestAiReplies(content: text, imageData: imageData, followers: self.followers, postFlowID: newPost.id)
        savePosts()
    }
    
    // Debugは本番Renderへ影響しない開発Renderを使用する。
    // Xcode Schemeの UPME_API_BASE_URL でローカルAPI等へ上書き可能。
    private static let baseUrl: String = {
        if DesignPreview.isActive { return "http://127.0.0.1:9" }
        if let override = ProcessInfo.processInfo.environment["UPME_API_BASE_URL"], !override.isEmpty {
            return override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        #if DEBUG
        return "https://AISNS-dev.onrender.com"
        #else
        return "https://aisns-1.onrender.com"
        #endif
    }()
    private let apiUrl = "\(baseUrl)/api/posts"
    private let replyApiUrl = "\(baseUrl)/api/replies"
    
    let userId: String = {
        if DesignPreview.isActive { return "design-preview" }
        if let stored = UserDefaults.standard.string(forKey: "userId") {
            return stored
        } else {
            let newId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newId, forKey: "userId")
            return newId
        }
    }()
    
    func fetchUser() {
        guard !DesignPreview.isActive else { return }
        if !isInOnboarding { updatePostReactions(at: Date()) }
        userProgressSync?.refresh()
    }

    private func syncUser(includeOnboarding: Bool = false) {
        guard !DesignPreview.isActive, !isInOnboarding || includeOnboarding else { return }
        cacheUserProgress()
        userProgressSync?.sync()
    }

    private func regularFollowerPayload() -> [[String: Any]] {
        Array(regularFollowers.prefix(maxRegularFollowers)).map { follower in
            [
                "follower_id": follower.id,
                "author_name": follower.authorName,
                "avatar_url": follower.avatarURL,
                "memories": Array(follower.memories.suffix(8)),
                "recent_interactions": Array(follower.recentInteractions.suffix(3))
            ]
        }
    }

    private func applyRegularFollowerMemoryUpdates(_ updates: [[String: Any]]) {
        guard !updates.isEmpty else { return }
        var updatedFollowers = regularFollowers

        for update in updates {
            guard let followerID = update["follower_id"] as? String,
                  let index = updatedFollowers.firstIndex(where: { $0.id == followerID }) else { continue }

            let incomingMemories = (update["new_memories"] as? [String] ?? [])
                .map { String($0.prefix(160)) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            var mergedMemories = updatedFollowers[index].memories
            for memory in incomingMemories where !mergedMemories.contains(memory) {
                mergedMemories.append(memory)
            }
            updatedFollowers[index].memories = Array(mergedMemories.suffix(8))

            if let interaction = update["interaction_summary"] as? String {
                let trimmed = String(interaction.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    updatedFollowers[index].recentInteractions.append(trimmed)
                    updatedFollowers[index].recentInteractions = Array(updatedFollowers[index].recentInteractions.suffix(3))
                }
            }
            updatedFollowers[index].lastInteractionAt = Date()
        }

        regularFollowers = updatedFollowers
    }

    func isReplyThreadExpanded(_ replyID: UUID) -> Bool {
        expandedReplyThreadIDs.contains(replyID)
    }

    func isReplyThreadLoading(_ replyID: UUID) -> Bool {
        loadingReplyThreadIDs.contains(replyID)
    }

    func toggleReplyThread(_ replyID: UUID) {
        if expandedReplyThreadIDs.contains(replyID) {
            expandedReplyThreadIDs.remove(replyID)
        } else {
            expandedReplyThreadIDs.insert(replyID)
        }
    }

    private func addUserReplyToThread(_ userReply: Reply, postIndex: Int, targetReplyIndex: Int) {
        let targetReplyID = posts[postIndex].replies[targetReplyIndex].id
        posts[postIndex].replies[targetReplyIndex].hasUserReply = true
        if let threadIndex = posts[postIndex].replyThreads.firstIndex(where: { $0.targetReplyID == targetReplyID }) {
            posts[postIndex].replyThreads[threadIndex].replies = [userReply]
        } else {
            posts[postIndex].replyThreads.append(
                ReplyThread(targetReplyID: targetReplyID, replies: [userReply])
            )
        }
        expandedReplyThreadIDs.insert(targetReplyID)
        loadingReplyThreadIDs.insert(targetReplyID)
    }

    private func failReplyThread(postID: UUID, targetReplyID: UUID, message: String) {
        if let postIndex = posts.firstIndex(where: { $0.id == postID }) {
            if let replyIndex = posts[postIndex].replies.firstIndex(where: { $0.id == targetReplyID }) {
                posts[postIndex].replies[replyIndex].hasUserReply = false
            }
            posts[postIndex].replyThreads.removeAll { $0.targetReplyID == targetReplyID }
        }
        pendingReplyThreadReplies[targetReplyID] = nil
        loadingReplyThreadIDs.remove(targetReplyID)
        expandedReplyThreadIDs.remove(targetReplyID)
        replyErrorMessage = message
    }

    private func drainReplyThreadNext(postID: UUID, targetReplyID: UUID) {
        guard var pending = pendingReplyThreadReplies[targetReplyID], !pending.isEmpty else {
            pendingReplyThreadReplies[targetReplyID] = nil
            loadingReplyThreadIDs.remove(targetReplyID)
            return
        }

        let nextReply = pending.removeFirst()
        pendingReplyThreadReplies[targetReplyID] = pending.isEmpty ? nil : pending

        if let postIndex = posts.firstIndex(where: { $0.id == postID }),
           let threadIndex = posts[postIndex].replyThreads.firstIndex(where: { $0.targetReplyID == targetReplyID }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                posts[postIndex].replyThreads[threadIndex].replies.append(nextReply)
            }
        }

        if pending.isEmpty {
            loadingReplyThreadIDs.remove(targetReplyID)
            UPMEAnalytics.capture("ai_thread_replies_displayed", properties: [
                "post_flow_id": postID.uuidString.lowercased(),
                "reply_count": 1,
                "is_regular": nextReply.regularFollowerId != nil
            ])
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 3.0...8.0)) { [weak self] in
                self?.drainReplyThreadNext(postID: postID, targetReplyID: targetReplyID)
            }
        }
    }

    /// 1つのAIリプライに対して、ユーザーが1回だけ返信する。
    /// ユーザー返信は先に専用スレッドへ表示し、AIの複数返信を順番に追加する。
    func submitReply(
        to reply: Reply,
        postID: UUID,
        text: String,
        onStarted: @escaping () -> Void = {},
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isSubmittingUserReply,
              let postIndex = posts.firstIndex(where: { $0.id == postID }),
              let replyIndex = posts[postIndex].replies.firstIndex(where: { $0.id == reply.id }),
              posts[postIndex].replies[replyIndex].canReceiveUserReply else {
            completion(false)
            return
        }

        let userReplyID = UUID()
        let userReply = Reply(
            id: userReplyID,
            authorName: userName,
            text: trimmed,
            img: "",
            isHater: false,
            isDefender: false,
            replyToId: reply.id,
            isUserReply: true
        )

        let otherReplies = posts[postIndex].replies
            .filter { $0.id != reply.id && !$0.isUserReply && $0.replyToId == nil }
            .prefix(8)
            .map { otherReply -> [String: Any] in
                var payload: [String: Any] = [
                    "author_name": otherReply.authorName,
                    "content": otherReply.text,
                    "avatar_url": otherReply.img,
                    "is_hater": otherReply.isHater,
                    "is_defender": otherReply.isDefender
                ]
                if let regularID = otherReply.regularFollowerId {
                    payload["regular_follower_id"] = regularID
                }
                return payload
            }

        isSubmittingUserReply = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            addUserReplyToThread(userReply, postIndex: postIndex, targetReplyIndex: replyIndex)
        }
        onStarted()
        UPMEAnalytics.capture("user_reply_submitted", properties: [
            "post_flow_id": postID.uuidString.lowercased(),
            "is_regular": regularFollowers.contains { follower in
                if let regularID = reply.regularFollowerId { return follower.id == regularID }
                return follower.authorName == reply.authorName && follower.avatarURL == reply.img
            },
            "is_hater": reply.isHater,
            "is_defender": reply.isDefender
        ])

        guard let url = URL(string: replyApiUrl) else {
            isSubmittingUserReply = false
            failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("返信先のAPI URLを確認できませんでした。", "The reply API URL could not be resolved."))
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "user_id": userId,
            "user_display_name": userName,
            "post_content": posts[postIndex].content,
            "ai_author_name": reply.authorName,
            "ai_author_img": reply.img,
            "ai_reply_content": reply.text,
            "user_reply": trimmed,
            "ai_is_hater": reply.isHater,
            "ai_is_defender": reply.isDefender,
            "language": languageCode,
            "regular_followers": regularFollowerPayload(),
            "other_ai_replies": otherReplies
        ]

        let targetRegular = regularFollowers.first { follower in
            if let regularID = reply.regularFollowerId { return follower.id == regularID }
            return follower.authorName == reply.authorName && follower.avatarURL == reply.img
        }
        if let targetRegular {
            body["target_regular_follower"] = [
                "follower_id": targetRegular.id,
                "author_name": targetRegular.authorName,
                "avatar_url": targetRegular.avatarURL,
                "memories": Array(targetRegular.memories.suffix(8)),
                "recent_interactions": Array(targetRegular.recentInteractions.suffix(3))
            ]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let replyRequestStartedAt = Date()

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if error != nil {
                DispatchQueue.main.async {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("通信状態を確認して、もう一度お試しください。", "Check your connection and try again."))
                    UPMEAnalytics.capture("user_reply_failed", properties: [
                        "post_flow_id": postID.uuidString.lowercased(),
                        "reason": "network",
                        "duration_ms": Int(Date().timeIntervalSince(replyRequestStartedAt) * 1_000)
                    ])
                    completion(false)
                }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "success" else {
                DispatchQueue.main.async {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("AIから返信を取得できませんでした。", "Could not get replies from the AI."))
                    UPMEAnalytics.capture("user_reply_failed", properties: [
                        "post_flow_id": postID.uuidString.lowercased(),
                        "reason": "invalid_response",
                        "duration_ms": Int(Date().timeIntervalSince(replyRequestStartedAt) * 1_000)
                    ])
                    completion(false)
                }
                return
            }

            let replyJSONs: [[String: Any]]
            if let replies = json["replies"] as? [[String: Any]], !replies.isEmpty {
                replyJSONs = replies
            } else if let legacyReply = json["reply"] as? [String: Any] {
                replyJSONs = [legacyReply]
            } else {
                DispatchQueue.main.async {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("AIから返信を取得できませんでした。", "Could not get replies from the AI."))
                    UPMEAnalytics.capture("user_reply_failed", properties: [
                        "post_flow_id": postID.uuidString.lowercased(),
                        "reason": "missing_replies",
                        "duration_ms": Int(Date().timeIntervalSince(replyRequestStartedAt) * 1_000)
                    ])
                    completion(false)
                }
                return
            }

            let memoryUpdates = json["memory_updates"] as? [[String: Any]] ?? []
            let followUps = replyJSONs.enumerated().compactMap { index, replyJSON -> Reply? in
                let content = replyJSON["content"] as? String ?? ""
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let author = replyJSON["author_name"] as? String ?? (index == 0 ? reply.authorName : "名無し")
                let img = replyJSON["author_img"] as? String
                    ?? (index == 0 ? reply.img : self.avatars[index % self.avatars.count])
                let isHater = jsonReplyBool(replyJSON, snake: "is_hater", camel: "isHater")
                let isDefender = jsonReplyBool(replyJSON, snake: "is_defender", camel: "isDefender")
                let regularFollowerID = replyJSON["regular_follower_id"] as? String
                return Reply(
                    authorName: author,
                    text: content,
                    img: img,
                    isHater: isHater,
                    isDefender: isDefender,
                    regularFollowerId: regularFollowerID,
                    replyToId: userReplyID
                )
            }

            DispatchQueue.main.async {
                self.applyRegularFollowerMemoryUpdates(memoryUpdates)
                guard let currentPostIndex = self.posts.firstIndex(where: { $0.id == postID }) else {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("投稿が見つからないため、返信を表示できませんでした。", "The post could not be found, so the replies could not be shown."))
                    completion(false)
                    return
                }
                guard self.posts[currentPostIndex].replyThreads.contains(where: { $0.targetReplyID == reply.id }) else {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: self.text("返信スレッドを表示できませんでした。", "The reply thread could not be displayed."))
                    completion(false)
                    return
                }
                self.pendingReplyThreadReplies[reply.id] = followUps
                self.isSubmittingUserReply = false
                UPMEAnalytics.capture("ai_thread_reply_received", properties: [
                    "post_flow_id": postID.uuidString.lowercased(),
                    "duration_ms": Int(Date().timeIntervalSince(replyRequestStartedAt) * 1_000),
                    "reply_count": followUps.count,
                    "regular_reply_count": followUps.filter { $0.regularFollowerId != nil }.count
                ])
                if followUps.isEmpty {
                    self.loadingReplyThreadIDs.remove(reply.id)
                } else {
                    self.drainReplyThreadNext(postID: postID, targetReplyID: reply.id)
                }
                completion(true)
            }
        }.resume()
    }

    private func requestAiReplies(content: String, imageData: Data?, followers: Int, postFlowID: UUID) {
        requestingPostIDs.insert(postFlowID)
        isRequestingReplies = true
        replyErrorMessage = nil
        let requestStartedAt = Date()
        UPMEAnalytics.capture("ai_replies_request_started", properties: [
            "post_flow_id": postFlowID.uuidString.lowercased(),
            "has_image": imageData != nil,
            "is_onboarding": isInOnboarding,
            "regular_count": regularFollowers.count
        ])
        
        guard let url = URL(string: apiUrl) else {
            finishPostRequest(postFlowID)
            replyErrorMessage = text("AI返信の接続先を確認できませんでした。", "The AI reply endpoint could not be resolved.")
            UPMEAnalytics.capture("ai_replies_failed", properties: [
                "post_flow_id": postFlowID.uuidString.lowercased(),
                "reason": "invalid_url",
                "is_onboarding": isInOnboarding,
                "duration_ms": 0
            ])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        var body: [String: Any] = [
            "user_id": userId,
            "user_display_name": userName,
            "content": content,
            "followers": followers,
            "is_hater_enabled": isHaterEnabled,
            "is_onboarding": isInOnboarding,
            "language": languageCode,
            "regular_followers": isInOnboarding ? [] : regularFollowerPayload(),
            "recent_ai_replies": isInOnboarding ? [] : recentAIReplyTexts(from: posts, excluding: postFlowID),
            "supports_viral_posts": true
        ]
        
        if let data = imageData {
            body["image_base64"] = data.base64EncodedString()
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        DispatchQueue.main.async { self.debugText = "REQ→\(url)" }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.debugText = "ERR:\(error.localizedDescription)"
                    self?.finishPostRequest(postFlowID)
                    self?.replyErrorMessage = self?.text("AI返信を取得できませんでした。通信状態を確認して、もう一度お試しください。", "Could not load AI replies. Check your connection and try again.")
                    UPMEAnalytics.capture("ai_replies_failed", properties: [
                        "post_flow_id": postFlowID.uuidString.lowercased(),
                        "reason": "network",
                        "is_onboarding": self?.isInOnboarding ?? false,
                        "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
                    ])
                }
                return
            }
            guard let self = self, let data = data else {
                DispatchQueue.main.async {
                    self?.debugText = "NO DATA"
                    self?.finishPostRequest(postFlowID)
                    self?.replyErrorMessage = self?.text("AI返信のデータを受信できませんでした。もう一度お試しください。", "No AI reply data was received. Please try again.")
                    UPMEAnalytics.capture("ai_replies_failed", properties: [
                        "post_flow_id": postFlowID.uuidString.lowercased(),
                        "reason": "missing_data",
                        "is_onboarding": false,
                        "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
                    ])
                }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let raw = String(data: data, encoding: .utf8) ?? "(not utf8)"
            DispatchQueue.main.async { self.debugText = "HTTP\(status) len=\(data.count) \(String(raw.prefix(120)))" }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let st = json["status"] as? String, st == "success",
               let repliesJson = json["replies"] as? [[String: Any]] {
                let memoryUpdates = json["memory_updates"] as? [[String: Any]] ?? []
                DispatchQueue.main.async {
                    self.debugText = "OK \(repliesJson.count) replies"
                    self.finishPostRequest(postFlowID)
                    self.applyRegularFollowerMemoryUpdates(memoryUpdates)
                    var pending: [Reply] = []
                    for r in repliesJson {
                        let author = r["author_name"] as? String ?? self.text("名無し", "Anonymous")
                        let content = r["content"] as? String ?? ""
                        let isHater = jsonReplyBool(r, snake: "is_hater", camel: "isHater")
                        let isDefender = jsonReplyBool(r, snake: "is_defender", camel: "isDefender")
                        let img = r["author_img"] as? String ?? self.avatars[0]
                        let regularFollowerID = r["regular_follower_id"] as? String
                        pending.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender, regularFollowerId: regularFollowerID))
                    }
                    UPMEAnalytics.capture("ai_replies_received", properties: [
                        "post_flow_id": postFlowID.uuidString.lowercased(),
                        "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000),
                        "reply_count": pending.count,
                        "regular_reply_count": pending.filter { $0.regularFollowerId != nil }.count,
                        "is_onboarding": self.isInOnboarding
                    ])
                    self.beginPostReaction(postID: postFlowID, replies: pending, response: json["reaction"] as? [String: Any])
                }
            } else {
                DispatchQueue.main.async {
                    self.debugText = "PARSE FAIL: \(String(raw.prefix(200)))"
                    self.finishPostRequest(postFlowID)
                    self.replyErrorMessage = self.text("AI返信を読み込めませんでした。しばらくしてから、もう一度お試しください。", "AI replies could not be loaded. Please try again later.")
                    UPMEAnalytics.capture("ai_replies_failed", properties: [
                        "post_flow_id": postFlowID.uuidString.lowercased(),
                        "reason": "invalid_response",
                        "is_onboarding": self.isInOnboarding,
                        "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
                    ])
                }
            }
        }.resume()
    }
    
    private func finishPostRequest(_ postID: UUID) {
        requestingPostIDs.remove(postID)
        isRequestingReplies = !requestingPostIDs.isEmpty
    }

    func isWaitingForReplies(to post: PostModel) -> Bool {
        requestingPostIDs.contains(post.id) || !(post.reaction?.remainingReplies.isEmpty ?? true)
            || (post.isOnboarding && posts.first?.id == post.id && (hasPendingReplies || onboardingRepliesRequestInFlight))
    }

    func displayedLikes(for post: PostModel) -> Int {
        guard let reaction = post.reaction, reaction.followersAfter == nil else { return post.likes }
        return Int(Double(reaction.targetLikes) * reaction.progress(at: reactionNow))
    }

    func isViralRevealed(_ post: PostModel) -> Bool {
        guard let reaction = post.reaction, reaction.isViral else { return false }
        return reaction.followersAfter != nil || reaction.elapsed(at: reactionNow) >= 3
    }

    func isViralAnimating(_ post: PostModel) -> Bool {
        isViralRevealed(post) && post.reaction?.followersAfter == nil
    }

    func beginPostReaction(postID: UUID, replies: [Reply], response: [String: Any]?) {
        guard let index = posts.firstIndex(where: { $0.id == postID }), !replies.isEmpty else {
            fallbackReactions.removeValue(forKey: postID)
            replyErrorMessage = text("AI返信を読み込めませんでした。", "AI replies could not be loaded.")
            return
        }
        let fallback = fallbackReactions.removeValue(forKey: postID) ?? (rank: currentRank, likes: 280, gain: 40)
        let viral = response?["is_viral"] as? Bool ?? false
        var offset: TimeInterval = 0
        let offsets = replies.indices.map { position -> TimeInterval in
            if viral { return Double(position) / Double(max(1, replies.count - 1)) * 11 }
            if position > 0 { offset += Double.random(in: 5...15) }
            return offset
        }
        posts[index].reaction = PostReaction(
            environment: Self.baseUrl, isViral: viral, rank: response?["rank"] as? Int ?? fallback.rank,
            targetLikes: max(0, response?["likes"] as? Int ?? fallback.likes),
            followerGain: max(0, response?["follower_gain"] as? Int ?? fallback.gain),
            startedAt: Date(), replyOffsets: offsets, remainingReplies: replies
        )
        if viral {
            UPMEAnalytics.capture("post_went_viral", properties: [
                "post_flow_id": postID.uuidString.lowercased(), "rank": posts[index].reaction!.rank,
                "reply_count": replies.count
            ])
        }
        updatePostReactions(at: Date())
        if reactionTimer == nil {
            reactionTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] date in
                self?.updatePostReactions(at: date)
            }
        }
    }

    /// Uses wall-clock time so foregrounding never restarts the effect or generates again.
    func updatePostReactions(at date: Date) {
        reactionNow = date
        for id in posts.map(\.id) {
            guard let index = posts.firstIndex(where: { $0.id == id }),
                  var reaction = posts[index].reaction, reaction.followersAfter == nil else { continue }
            let elapsed = reaction.elapsed(at: date)
            let previousCount = reaction.remainingReplies.count
            var revealed: [Reply] = []
            while !reaction.remainingReplies.isEmpty {
                let position = reaction.replyOffsets.count - reaction.remainingReplies.count
                guard elapsed >= reaction.replyOffsets[position] else { break }
                revealed.append(reaction.remainingReplies.removeFirst())
            }
            let complete = elapsed >= reaction.duration
            if complete { reaction.followersAfter = followers + reaction.followerGain }
            if previousCount != reaction.remainingReplies.count || complete {
                // Store the absolute credited total before updating user progress. On relaunch,
                // max(local total, credited total) repairs an interrupted write without doubling it.
                var updated = posts[index]
                updated.replies.append(contentsOf: revealed)
                updated.reaction = reaction
                if complete { updated.likes = reaction.targetLikes }
                posts[index] = updated
            }
            if complete, let total = reaction.followersAfter {
                followers = max(followers, total)
                UPMEAnalytics.capture("ai_replies_displayed", properties: [
                    "post_flow_id": id.uuidString.lowercased(), "reply_count": reaction.replyOffsets.count,
                    "is_onboarding": false, "is_viral": reaction.isViral
                ])
                syncUser()
            }
        }
        let active = posts.contains { $0.reaction != nil && $0.reaction?.followersAfter == nil }
        hasPendingReplies = active
        if !active { reactionTimer?.cancel(); reactionTimer = nil }
    }

    func restorePostReactions() {
        // Opening the app again shows the settled outcome, without replaying the celebration.
        let recordedTotal = posts.compactMap { post -> Int? in
            guard post.reaction?.environment == Self.baseUrl else { return nil }
            return post.reaction?.followersAfter
        }.max() ?? followers
        userProgressSync?.recoverFollowerTotal(atLeast: recordedTotal)
        followers = max(followers, recordedTotal)
        for id in posts.map(\.id) {
            guard let index = posts.firstIndex(where: { $0.id == id }) else { continue }
            guard var reaction = posts[index].reaction else { continue }
            var updated = posts[index]
            guard reaction.environment == Self.baseUrl else {
                // Development and production may share app files, but never reward credits.
                updated.replies.append(contentsOf: reaction.remainingReplies)
                reaction.remainingReplies = []
                reaction.followersAfter = 0
                updated.likes = reaction.targetLikes
                updated.reaction = reaction
                posts[index] = updated
                continue
            }
            if reaction.followersAfter == nil {
                reaction.followersAfter = followers + reaction.followerGain
                updated.replies.append(contentsOf: reaction.remainingReplies)
                reaction.remainingReplies = []
                updated.likes = reaction.targetLikes
                updated.reaction = reaction
                posts[index] = updated
            }
            followers = max(followers, reaction.followersAfter ?? followers)
        }
    }

    private func fetchAiRepliesBackground(
        content: String,
        followers: Int,
        postFlowID: UUID,
        retryCount: Int = 0,
        requestStartedAt: Date? = nil,
        completion: @escaping (Result<[Reply], OnboardingReplyFetchError>) -> Void
    ) {
        let requestStartedAt = requestStartedAt ?? Date()
        let fail: (OnboardingReplyFetchError) -> Void = { failure in
            UPMEAnalytics.capture("ai_replies_failed", properties: [
                "post_flow_id": postFlowID.uuidString.lowercased(),
                "reason": failure.rawValue,
                "is_onboarding": true,
                "retry_count": retryCount,
                "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
            ])
            DispatchQueue.main.async { completion(.failure(failure)) }
        }
        if retryCount == 0 {
            UPMEAnalytics.capture("ai_replies_request_started", properties: [
                "post_flow_id": postFlowID.uuidString.lowercased(),
                "has_image": false,
                "is_onboarding": true,
                "regular_count": 0
            ])
        }
        guard let url = URL(string: apiUrl) else {
            fail(.invalidURL)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        
        let body: [String: Any] = [
            "user_id": userId,
            "user_display_name": userName,
            "content": content,
            "followers": followers,
            "is_hater_enabled": isHaterEnabled,
            "is_onboarding": true,    // オンボ専用プロンプト固定
            "language": languageCode
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("fetchAiRepliesBackground error: \(error.localizedDescription)")
                // ネットワーク切断などは2回までリトライ
                if retryCount < 2 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        self.fetchAiRepliesBackground(content: content, followers: followers, postFlowID: postFlowID, retryCount: retryCount + 1, requestStartedAt: requestStartedAt, completion: completion)
                    }
                } else {
                    fail(.network)
                }
                return
            }
            
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let st = json["status"] as? String, st == "success",
                  let repliesJson = json["replies"] as? [[String: Any]] else {
                fail(.invalidResponse)
                return
            }
            
            var replies: [Reply] = []
            for r in repliesJson {
                let author = r["author_name"] as? String ?? self.text("名無し", "Anonymous")
                let content = r["content"] as? String ?? ""
                let isHater = jsonReplyBool(r, snake: "is_hater", camel: "isHater")
                let isDefender = jsonReplyBool(r, snake: "is_defender", camel: "isDefender")
                let img = r["author_img"] as? String ?? self.avatars[0]
                let regularFollowerID = r["regular_follower_id"] as? String
                replies.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender, regularFollowerId: regularFollowerID))
            }
            guard !replies.isEmpty else {
                fail(.emptyReplies)
                return
            }
            UPMEAnalytics.capture("ai_replies_received", properties: [
                "post_flow_id": postFlowID.uuidString.lowercased(),
                "duration_ms": Int(Date().timeIntervalSince(requestStartedAt) * 1_000),
                "reply_count": replies.count,
                "regular_reply_count": replies.filter { $0.regularFollowerId != nil }.count,
                "is_onboarding": true
            ])
            DispatchQueue.main.async { completion(.success(replies)) }
        }.resume()
    }
    
    private func startReplyDrainTimer(postFlowID: UUID, isOnboarding: Bool) {
        replyTimer?.cancel()
        likeTimer?.cancel()
        
        let count = pendingReplies.count
        guard count > 0 else { return }
        
        buzzTotalReplies = count
        buzzCurrentReply = 0
        if isOnboarding { onboardingExpectedReplies = count }
        
        // リプライの推定所要時間を計算（1件目は即時、残りは10〜30秒 → 平均20秒）
        let estimatedDuration = Double(max(count - 1, 1)) * 20.0
        let totalTicks = Int(estimatedDuration / buzzUpdateInterval)
        var tickCount = 0
        
        // 0.5秒ごとにいいね・フォロワーをチロチロ増やすタイマーを開始
        likeTimer = Timer.publish(every: buzzUpdateInterval, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            tickCount += 1
            
            let progress = min(Double(tickCount) / Double(totalTicks), 1.0)
            let newLikes = self.buzzInitialLikes + Int(Double(self.buzzTargetLikes) * progress)
            let newFollowers = self.buzzInitialFollowers + Int(Double(self.buzzTargetFollowers) * progress)
            
            if !self.posts.isEmpty {
                self.posts[0].likes = newLikes
            }
            self.followers = newFollowers
        }
        
        func drainNext() {
            guard !self.pendingReplies.isEmpty, !self.posts.isEmpty else { return }
            
            let reply = self.pendingReplies.removeFirst()
            let animation: Animation = isOnboarding
                ? .easeIn(duration: 0.3)
                : .spring(response: 0.4, dampingFraction: 0.7)
            withAnimation(animation) {
                self.posts[0].replies.insert(reply, at: 0)
            }
            
            // オンボ中：1件目のリプライが表示されたらローディングを消す
            if isOnboarding && !self.onboardingFirstReplyReceived {
                self.onboardingFirstReplyReceived = true
            }
            
            if self.pendingReplies.isEmpty {
                // 最後のリプライ → タイマー停止、目標値にピッタリ合わせてDB同期
                self.likeTimer?.cancel()
                self.posts[0].likes = self.buzzInitialLikes + self.buzzTargetLikes
                self.followers = self.buzzInitialFollowers + self.buzzTargetFollowers
                UPMEAnalytics.capture("ai_replies_displayed", properties: [
                    "post_flow_id": postFlowID.uuidString.lowercased(),
                    "reply_count": self.buzzTotalReplies,
                    "is_onboarding": isOnboarding
                ])
                self.syncUser()
            } else {
                let randomInterval = isOnboarding ? Double.random(in: 1.5...4.0) : Double.random(in: 5.0...15.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
                    drainNext()
                }
            }
        }
        
        // 1件目は待たずにすぐ表示する
        drainNext()
    }
}
