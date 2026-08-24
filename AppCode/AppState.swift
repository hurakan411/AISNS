import SwiftUI
import Combine

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

struct PostModel: Identifiable, Codable {
    var id: UUID
    let content: String
    var imageData: Data?
    var likes: Int
    var replies: [Reply]
    var replyThreads: [ReplyThread]
    let time: String

    init(
        id: UUID = UUID(),
        content: String,
        imageData: Data?,
        likes: Int,
        replies: [Reply],
        replyThreads: [ReplyThread] = [],
        time: String
    ) {
        self.id = id
        self.content = content
        self.imageData = imageData
        self.likes = likes
        self.replies = replies
        self.replyThreads = replyThreads
        self.time = time
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, imageData, likes, replies, replyThreads, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try container.decode(String.self, forKey: .content)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        replies = try container.decodeIfPresent([Reply].self, forKey: .replies) ?? []
        replyThreads = try container.decodeIfPresent([ReplyThread].self, forKey: .replyThreads) ?? []
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(likes, forKey: .likes)
        try container.encode(replies, forKey: .replies)
        try container.encode(replyThreads, forKey: .replyThreads)
        try container.encode(time, forKey: .time)
    }
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

class AppState: ObservableObject {
    @Published var debugText: String = "---"
    @Published var followers: Int = 0
    @Published var totalPosts: Int = 0
    @Published var posts: [PostModel] = [] {
        didSet { if !isInOnboarding { savePosts() } }
    }
    @Published private(set) var regularFollowers: [RegularFollower] = [] {
        didSet { saveRegularFollowers() }
    }
    
    @Published var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var onboardingStatusReady: Bool = false
    @Published var isInOnboarding: Bool = false
    @Published var onboardingExpectedReplies: Int = 0
    @Published var isRequestingReplies: Bool = false
    @Published var isSubmittingUserReply: Bool = false
    @Published private(set) var expandedReplyThreadIDs: Set<UUID> = []
    @Published private(set) var loadingReplyThreadIDs: Set<UUID> = []
    @Published var replyErrorMessage: String?
    @Published var onboardingFirstReplyReceived: Bool = false
    
    // オンボーディング用プリフェッチ
    private var prefetchedOnboardingReplies: [Reply] = []
    @Published var prefetchedOnboardingText: String = ""
    
    @Published var userName: String = UserDefaults.standard.string(forKey: "userName") ?? "あなた" {
        didSet { UserDefaults.standard.set(userName, forKey: "userName") }
    }
    @Published var userAvatarData: Data? = nil {
        didSet { saveAvatar() }
    }
    @Published var userBio: String = UserDefaults.standard.string(forKey: "userBio") ?? "今日も息してるだけでえらい。UPME! | AI SNSで承認欲求の海に溺れるアカウント。" {
        didSet { UserDefaults.standard.set(userBio, forKey: "userBio") }
    }
    
    @Published var isHaterEnabled: Bool = UserDefaults.standard.object(forKey: "isHaterEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isHaterEnabled, forKey: "isHaterEnabled")
        }
    }
    
    private var likeTimer: AnyCancellable?
    private var replyTimer: AnyCancellable?
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

    init() { 
        let bio = UserDefaults.standard.string(forKey: "userBio") ?? ""
        if bio.contains("ZEN-KOTEI") || bio.contains("全肯定") {
            let newBio = "今日も息してるだけでえらい。UPME! | AI SNSで承認欲求の海に溺れるアカウント。"
            UserDefaults.standard.set(newBio, forKey: "userBio")
            self.userBio = newBio
        }
        
        let savedName = UserDefaults.standard.string(forKey: "userName") ?? ""
        if savedName == "みずき（あなた）" {
            UserDefaults.standard.set("あなた", forKey: "userName")
            self.userName = "あなた"
        }
        
        loadAvatar()
        loadPosts()
        loadRegularFollowers()
        registerUser() // 完了後に fetchUser() を呼ぶ（直列化でレースコンディション回避）
    }
    
    private func registerUser() {
        guard let url = URL(string: "\(userApiUrl)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let body: [String: Any] = ["user_id": userId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            // ネットワークエラーまたは HTTPエラー → サーバーの真値が不明なので安全側に倒す
            guard error == nil, (200..<300).contains(httpStatus), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    // サーバーに確認できなかった場合、UserDefaults のキャッシュ値をそのまま使う
                    self.onboardingStatusReady = true
                }
                return
            }
            
            let dbFlag = parseJSONBool(json["has_completed_onboarding"])
            DispatchQueue.main.async {
                if self.hasCompletedOnboarding != dbFlag {
                    self.hasCompletedOnboarding = dbFlag
                }
                self.onboardingStatusReady = true
                // onboarding判定確定後にフォロワー数などを取得
                self.fetchUser()
            }
        }.resume()
    }
    
    private func savePosts() {
        let trimmed = Array(posts.prefix(5))
        if posts.count > 5 { posts = trimmed }
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: postsURL)
        }
    }
    
    private func loadPosts() {
        if let data = try? Data(contentsOf: postsURL),
           let decoded = try? JSONDecoder().decode([PostModel].self, from: data) {
            self.posts = decoded
        }
    }
    
    private func saveAvatar() {
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
        case 1: return "Lv.1 名もなき市民"
        case 2: return "Lv.2 クラスの人気者"
        case 3: return "Lv.3 プチ・インフルエンサー"
        case 4: return "Lv.4 マイクロ・インフルエンサー"
        case 5: return "Lv.5 ネットのカリスマ"
        case 6: return "Lv.6 オピニオンリーダー"
        case 7: return "Lv.7 時代の寵児"
        case 8: return "Lv.8 宗派の祖"
        case 9: return "Lv.9 預言者"
        case 10: return "Lv.10 デジタル・ゴッド"
        default: return "名もなき市民"
        }
    }
    
    var nextRankFollowers: Int? {
        if currentRank >= 10 { return nil }
        let thresholds = [0, 100, 500, 2_000, 10_000, 50_000, 200_000, 1_000_000, 5_000_000, 20_000_000, 20_000_000]
        return thresholds[currentRank]
    }
    
    /// fakeCompose投稿時点でAIにリクエストを送り、返信を事前取得しておく
    func prefetchOnboardingReplies(text: String) {
        prefetchedOnboardingText = text
        prefetchedOnboardingReplies = []
        UPMEAnalytics.capture("onboarding_post_submitted")
        // is_onboarding=true で送信（オンボ専用プロンプト）
        fetchAiRepliesBackground(content: text, followers: 20_000_000) { [weak self] replies in
            guard let self = self else { return }
            self.prefetchedOnboardingReplies = replies
        }
    }
    
    func submitOnboardingPost(text: String) {
        isInOnboarding = true
        onboardingFirstReplyReceived = false
        let newPost = PostModel(content: text, imageData: nil, likes: 0, replies: [], time: "今")
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
        
        if !prefetchedOnboardingReplies.isEmpty {
            // プリフェッチ済み返信をそのまま使う
            let replies = prefetchedOnboardingReplies
            prefetchedOnboardingReplies = []
            pendingReplies = replies
            startReplyDrainTimer()
        } else {
            // まだ取得中ならそのまま待つ（fetchAiRepliesBackgroundのコールバックで自動反映）
            fetchAiRepliesBackground(content: text, followers: 20_000_000) { [weak self] replies in
                guard let self = self else { return }
                self.pendingReplies = replies
                self.startReplyDrainTimer()
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
        UPMEAnalytics.capture("onboarding_completed", properties: [
            "rank": currentRank
        ])
        syncUser(includeOnboarding: true)
    }
    
    func submitPost(text: String, imageData: Data? = nil) {
        let newPost = PostModel(content: text, imageData: imageData, likes: 0, replies: [], time: "今")
        posts.insert(newPost, at: 0)
        
        let rank = currentRank
        totalPosts += 1
        UPMEAnalytics.capture("post_created", properties: [
            "has_image": imageData != nil,
            "rank": rank,
            "regular_count": regularFollowers.count
        ])
        
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
        buzzInitialLikes = self.posts.first?.likes ?? 0
        buzzInitialFollowers = self.followers
        buzzTargetLikes = totalLikes
        buzzTargetFollowers = totalFollowers
        buzzCurrentReply = 0

        // 実APIへ生成リクエスト
        requestAiReplies(content: text, imageData: imageData, followers: self.followers)
        savePosts()
    }
    
    // Debugは本番Renderへ影響しないローカルAPIを使用する。
    // Xcode Schemeの UPME_API_BASE_URL でステージングURLへ上書き可能。
    private static let baseUrl: String = {
        if let override = ProcessInfo.processInfo.environment["UPME_API_BASE_URL"], !override.isEmpty {
            return override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        #if DEBUG
        return "http://127.0.0.1:8000"
        #else
        return "https://aisns-1.onrender.com"
        #endif
    }()
    private let apiUrl = "\(baseUrl)/api/posts"
    private let replyApiUrl = "\(baseUrl)/api/replies"
    private let userApiUrl = "\(baseUrl)/api/users"
    
    let userId: String = {
        if let stored = UserDefaults.standard.string(forKey: "userId") {
            return stored
        } else {
            let newId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newId, forKey: "userId")
            return newId
        }
    }()
    
    func fetchUser() {
        guard let url = URL(string: "\(userApiUrl)/\(userId)") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    self.followers = json["total_followers"] as? Int ?? 0
                    self.totalPosts = json["total_posts"] as? Int ?? 0
                    // hasCompletedOnboarding はここでは更新しない
                    //（onboarding判定は registerUser() が唯一の責務）
                }
            }
        }.resume()
    }

    private func syncUser(includeOnboarding: Bool = false) {
        guard !isInOnboarding || includeOnboarding else { return }
        guard let url = URL(string: "\(userApiUrl)/\(userId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["total_followers": self.followers, "total_posts": self.totalPosts]
        if includeOnboarding {
            body["has_completed_onboarding"] = self.hasCompletedOnboarding
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
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
            "is_regular": regularFollowers.contains { follower in
                if let regularID = reply.regularFollowerId { return follower.id == regularID }
                return follower.authorName == reply.authorName && follower.avatarURL == reply.img
            },
            "is_hater": reply.isHater,
            "is_defender": reply.isDefender
        ])

        guard let url = URL(string: replyApiUrl) else {
            isSubmittingUserReply = false
            failReplyThread(postID: postID, targetReplyID: reply.id, message: "返信先のAPI URLを確認できませんでした。")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "user_id": userId,
            "post_content": posts[postIndex].content,
            "ai_author_name": reply.authorName,
            "ai_author_img": reply.img,
            "ai_reply_content": reply.text,
            "user_reply": trimmed,
            "ai_is_hater": reply.isHater,
            "ai_is_defender": reply.isDefender,
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

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if error != nil {
                DispatchQueue.main.async {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: "通信状態を確認して、もう一度お試しください。")
                    UPMEAnalytics.capture("user_reply_failed", properties: ["reason": "network"])
                    completion(false)
                }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "success" else {
                DispatchQueue.main.async {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: "AIから返信を取得できませんでした。")
                    UPMEAnalytics.capture("user_reply_failed", properties: ["reason": "invalid_response"])
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
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: "AIから返信を取得できませんでした。")
                    UPMEAnalytics.capture("user_reply_failed", properties: ["reason": "missing_replies"])
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
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: "投稿が見つからないため、返信を表示できませんでした。")
                    completion(false)
                    return
                }
                guard self.posts[currentPostIndex].replyThreads.contains(where: { $0.targetReplyID == reply.id }) else {
                    self.isSubmittingUserReply = false
                    self.failReplyThread(postID: postID, targetReplyID: reply.id, message: "返信スレッドを表示できませんでした。")
                    completion(false)
                    return
                }
                self.pendingReplyThreadReplies[reply.id] = followUps
                self.isSubmittingUserReply = false
                UPMEAnalytics.capture("ai_thread_reply_received", properties: [
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

    private func requestAiReplies(content: String, imageData: Data?, followers: Int) {
        pendingReplies = []
        isRequestingReplies = true
        UPMEAnalytics.capture("ai_replies_request_started", properties: [
            "has_image": imageData != nil,
            "is_onboarding": isInOnboarding,
            "regular_count": regularFollowers.count
        ])
        
        guard let url = URL(string: apiUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        var body: [String: Any] = [
            "user_id": userId,
            "content": content,
            "followers": followers,
            "is_hater_enabled": isHaterEnabled,
            "is_onboarding": isInOnboarding,
            "regular_followers": isInOnboarding ? [] : regularFollowerPayload()
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
                    self?.isRequestingReplies = false
                    UPMEAnalytics.capture("ai_replies_failed", properties: [
                        "reason": "network",
                        "is_onboarding": self?.isInOnboarding ?? false
                    ])
                }
                return
            }
            guard let self = self, let data = data else {
                DispatchQueue.main.async {
                    self?.debugText = "NO DATA"
                    self?.isRequestingReplies = false
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
                    self.isRequestingReplies = false
                    self.applyRegularFollowerMemoryUpdates(memoryUpdates)
                    var pending: [Reply] = []
                    for r in repliesJson {
                        let author = r["author_name"] as? String ?? "名無し"
                        let content = r["content"] as? String ?? ""
                        let isHater = jsonReplyBool(r, snake: "is_hater", camel: "isHater")
                        let isDefender = jsonReplyBool(r, snake: "is_defender", camel: "isDefender")
                        let img = r["author_img"] as? String ?? self.avatars[0]
                        let regularFollowerID = r["regular_follower_id"] as? String
                        pending.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender, regularFollowerId: regularFollowerID))
                    }
                    UPMEAnalytics.capture("ai_replies_received", properties: [
                        "reply_count": pending.count,
                        "regular_reply_count": pending.filter { $0.regularFollowerId != nil }.count,
                        "is_onboarding": self.isInOnboarding
                    ])
                    self.pendingReplies = pending
                    self.startReplyDrainTimer()
                }
            } else {
                DispatchQueue.main.async {
                    self.debugText = "PARSE FAIL: \(String(raw.prefix(200)))"
                    self.isRequestingReplies = false
                    UPMEAnalytics.capture("ai_replies_failed", properties: [
                        "reason": "invalid_response",
                        "is_onboarding": self.isInOnboarding
                    ])
                }
            }
        }.resume()
    }
    
    private func fetchAiRepliesBackground(content: String, followers: Int, retryCount: Int = 0, completion: @escaping ([Reply]) -> Void) {
        guard let url = URL(string: apiUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        
        let body: [String: Any] = [
            "user_id": userId,
            "content": content,
            "followers": followers,
            "is_hater_enabled": isHaterEnabled,
            "is_onboarding": true    // オンボ専用プロンプト固定
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("fetchAiRepliesBackground error: \(error.localizedDescription)")
                // ネットワーク切断などは2回までリトライ
                if retryCount < 2 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        self.fetchAiRepliesBackground(content: content, followers: followers, retryCount: retryCount + 1, completion: completion)
                    }
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let st = json["status"] as? String, st == "success",
                  let repliesJson = json["replies"] as? [[String: Any]] else { return }
            
            var replies: [Reply] = []
            for r in repliesJson {
                let author = r["author_name"] as? String ?? "名無し"
                let content = r["content"] as? String ?? ""
                let isHater = jsonReplyBool(r, snake: "is_hater", camel: "isHater")
                let isDefender = jsonReplyBool(r, snake: "is_defender", camel: "isDefender")
                let img = r["author_img"] as? String ?? self.avatars[0]
                let regularFollowerID = r["regular_follower_id"] as? String
                replies.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender, regularFollowerId: regularFollowerID))
            }
            UPMEAnalytics.capture("ai_replies_received", properties: [
                "reply_count": replies.count,
                "regular_reply_count": replies.filter { $0.regularFollowerId != nil }.count,
                "is_onboarding": true
            ])
            DispatchQueue.main.async { completion(replies) }
        }.resume()
    }
    
    private func startReplyDrainTimer() {
        replyTimer?.cancel()
        likeTimer?.cancel()
        
        let count = pendingReplies.count
        guard count > 0 else { return }
        
        buzzTotalReplies = count
        buzzCurrentReply = 0
        if isInOnboarding { onboardingExpectedReplies = count }
        
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
            let animation: Animation = self.isInOnboarding
                ? .easeIn(duration: 0.3)
                : .spring(response: 0.4, dampingFraction: 0.7)
            withAnimation(animation) {
                self.posts[0].replies.insert(reply, at: 0)
            }
            
            // オンボ中：1件目のリプライが表示されたらローディングを消す
            if self.isInOnboarding && !self.onboardingFirstReplyReceived {
                self.onboardingFirstReplyReceived = true
            }
            
            if self.pendingReplies.isEmpty {
                // 最後のリプライ → タイマー停止、目標値にピッタリ合わせてDB同期
                self.likeTimer?.cancel()
                self.posts[0].likes = self.buzzInitialLikes + self.buzzTargetLikes
                self.followers = self.buzzInitialFollowers + self.buzzTargetFollowers
                UPMEAnalytics.capture("ai_replies_displayed", properties: [
                    "reply_count": self.buzzTotalReplies,
                    "is_onboarding": self.isInOnboarding
                ])
                self.syncUser()
            } else {
                let randomInterval = self.isInOnboarding ? Double.random(in: 1.5...4.0) : Double.random(in: 5.0...15.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
                    drainNext()
                }
            }
        }
        
        // 1件目は待たずにすぐ表示する
        drainNext()
    }
}
