import SwiftUI
import Combine

struct Reply: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    let authorName: String
    let text: String
    let img: String
    let isHater: Bool
    let isDefender: Bool
}

struct PostModel: Identifiable, Codable {
    var id: UUID = UUID()
    let content: String
    var imageData: Data?
    var likes: Int
    var replies: [Reply]
    let time: String
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
    @Published var followers: Int = 0
    @Published var totalPosts: Int = 0
    @Published var posts: [PostModel] = [] {
        didSet { if !isInOnboarding { savePosts() } }
    }
    
    @Published var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var onboardingStatusReady: Bool = false
    @Published var isInOnboarding: Bool = false
    @Published var onboardingExpectedReplies: Int = 0
    
    @Published var userName: String = UserDefaults.standard.string(forKey: "userName") ?? "みずき（あなた）" {
        didSet { UserDefaults.standard.set(userName, forKey: "userName") }
    }
    @Published var userAvatarData: Data? = nil {
        didSet { saveAvatar() }
    }
    @Published var userBio: String = UserDefaults.standard.string(forKey: "userBio") ?? "今日も息してるだけでえらい。全肯定SNS「ZEN-KOTEI」で承認欲求の海に溺れるアカウント。" {
        didSet { UserDefaults.standard.set(userBio, forKey: "userBio") }
    }
    
    @Published var isHaterEnabled: Bool = UserDefaults.standard.object(forKey: "isHaterEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isHaterEnabled, forKey: "isHaterEnabled")
        }
    }
    
    private var likeTimer: AnyCancellable?
    private var replyTimer: AnyCancellable?
    private var pendingReplies: [Reply] = []
    
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

    init() { 
        loadAvatar()
        loadPosts()
        registerUser()
        fetchUser()
    }
    
    private func registerUser() {
        guard let url = URL(string: "\(userApiUrl)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["user_id": userId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data else {
                DispatchQueue.main.async { self?.onboardingStatusReady = true }
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let dbFlag = parseJSONBool(json["has_completed_onboarding"])
                DispatchQueue.main.async {
                    if self.hasCompletedOnboarding != dbFlag {
                        self.hasCompletedOnboarding = dbFlag
                    }
                    self.onboardingStatusReady = true
                }
            } else {
                DispatchQueue.main.async { self.onboardingStatusReady = true }
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
    
    func submitOnboardingPost(text: String) {
        isInOnboarding = true
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
        
        requestAiReplies(content: text, imageData: nil, followers: 20_000_000)
    }
    
    func completeOnboarding() {
        likeTimer?.cancel()
        replyTimer?.cancel()
        pendingReplies = []
        isInOnboarding = false
        posts = []
        followers = 0
        totalPosts = 0
        hasCompletedOnboarding = true
        syncUser(includeOnboarding: true)
    }
    
    func submitPost(text: String, imageData: Data? = nil) {
        let newPost = PostModel(content: text, imageData: imageData, likes: 0, replies: [], time: "今")
        posts.insert(newPost, at: 0)
        
        let rank = currentRank
        totalPosts += 1
        
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
    
    // API関連
    let userId: String = {
        if let stored = UserDefaults.standard.string(forKey: "userId") {
            return stored
        } else {
            let newId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newId, forKey: "userId")
            return newId
        }
    }()
    private let apiUrl = "http://127.0.0.1:8000/api/posts"
    private let userApiUrl = "http://127.0.0.1:8000/api/users"
    
    func fetchUser() {
        guard let url = URL(string: "\(userApiUrl)/\(userId)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    self.followers = json["total_followers"] as? Int ?? 0
                    self.totalPosts = json["total_posts"] as? Int ?? 0
                    let dbFlag = parseJSONBool(json["has_completed_onboarding"])
                    if self.hasCompletedOnboarding != dbFlag {
                        self.hasCompletedOnboarding = dbFlag
                    }
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

    private func requestAiReplies(content: String, imageData: Data?, followers: Int) {
        pendingReplies = []
        
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
            "is_onboarding": isInOnboarding
        ]
        
        if let data = imageData {
            body["image_base64"] = data.base64EncodedString()
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "success",
               let repliesJson = json["replies"] as? [[String: Any]] {
                DispatchQueue.main.async {
                    var pending: [Reply] = []
                    for r in repliesJson {
                        let author = r["author_name"] as? String ?? "名無し"
                        let content = r["content"] as? String ?? ""
                        let isHater = jsonReplyBool(r, snake: "is_hater", camel: "isHater")
                        let isDefender = jsonReplyBool(r, snake: "is_defender", camel: "isDefender")
                        let img = r["author_img"] as? String ?? self.avatars[0]
                        pending.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender))
                    }
                    self.pendingReplies = pending
                    self.startReplyDrainTimer()
                }
            }
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
            if self.isInOnboarding {
                withAnimation(.easeIn(duration: 0.3)) {
                    self.posts[0].replies.insert(reply, at: 0)
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.posts[0].replies.append(reply)
                }
            }
            
            if self.pendingReplies.isEmpty {
                // 最後のリプライ → タイマー停止、目標値にピッタリ合わせてDB同期
                self.likeTimer?.cancel()
                self.posts[0].likes = self.buzzInitialLikes + self.buzzTargetLikes
                self.followers = self.buzzInitialFollowers + self.buzzTargetFollowers
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
