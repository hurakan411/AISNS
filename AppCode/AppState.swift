import SwiftUI
import Combine

struct Reply: Identifiable, Equatable {
    let id = UUID()
    let authorName: String
    let text: String
    let img: String
    let isHater: Bool
    let isDefender: Bool
}

struct PostModel: Identifiable {
    let id = UUID()
    let content: String
    var likes: Int
    var replies: [Reply]
    let time: String
}

class AppState: ObservableObject {
    @Published var followers: Int = 0
    @Published var totalPosts: Int = 0
    @Published var posts: [PostModel] = []
    
    private var likeTimer: AnyCancellable?
    private var replyTimer: AnyCancellable?
    private var pendingReplies: [Reply] = []
    
    let avatars = [
        "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1554151228-14d9def656e4?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=150&h=150&fit=crop",
        "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150&h=150&fit=crop"
    ]
    let haterAvatar = "https://images.unsplash.com/photo-1511367461989-f85a21fda167?w=32&h=32&fit=crop"
    init() { 
        fetchUser()
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
    
    func submitPost(text: String) {
        let newPost = PostModel(content: text, likes: 0, replies: [], time: "今")
        posts.insert(newPost, at: 0)
        if posts.count > 10 { posts.removeLast() }
        
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
        
        let initialLikes = self.posts.first?.likes ?? 0
        let initialFollowers = self.followers
        let totalTicks = 45
        var increments = 0
        
        likeTimer?.cancel()
        likeTimer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            increments += 1
            
            let currentLikesTarget = initialLikes + Int(Double(totalLikes) * Double(increments) / Double(totalTicks))
            let currentFollowersTarget = initialFollowers + Int(Double(totalFollowers) * Double(increments) / Double(totalTicks))
            
            if !self.posts.isEmpty {
                self.posts[0].likes = currentLikesTarget
            }
            self.followers = currentFollowersTarget
            
            if increments >= totalTicks { 
                self.likeTimer?.cancel() 
                self.syncUser()
            }
        }

        // 実APIへ生成リクエスト
        requestAiReplies(content: text, followers: self.followers)
    }
    
    // API関連
    private let testUserId = "11111111-1111-1111-1111-111111111111"
    private let apiUrl = "http://127.0.0.1:8000/api/posts"
    private let userApiUrl = "http://127.0.0.1:8000/api/users"
    
    func fetchUser() {
        guard let url = URL(string: "\(userApiUrl)/\(testUserId)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                DispatchQueue.main.async {
                    self.followers = json["total_followers"] ?? 0
                    self.totalPosts = json["total_posts"] ?? 0
                }
            }
        }.resume()
    }

    private func syncUser() {
        guard let url = URL(string: "\(userApiUrl)/\(testUserId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["total_followers": self.followers, "total_posts": self.totalPosts]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }

    private func requestAiReplies(content: String, followers: Int) {
        pendingReplies = []
        
        guard let url = URL(string: apiUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "user_id": testUserId,
            "content": content,
            "followers": followers
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let postId = json["post_id"] as? String {
                self.pollForReplies(postId: postId)
            }
        }.resume()
    }
    
    private func pollForReplies(postId: String) {
        guard let url = URL(string: "\(apiUrl)/\(postId)") else { return }
        
        func check() {
            URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { check() }
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    if status == "completed", let repliesJson = json["replies"] as? [[String: Any]] {
                        DispatchQueue.main.async {
                            var pending: [Reply] = []
                            for r in repliesJson {
                                let author = r["author_name"] as? String ?? "名無し"
                                let content = r["content"] as? String ?? ""
                                let isHater = r["is_hater"] as? Bool ?? false
                                let isDefender = r["is_defender"] as? Bool ?? false
                                let img = r["author_img"] as? String ?? self.avatars[0]
                                pending.append(Reply(authorName: author, text: content, img: img, isHater: isHater, isDefender: isDefender))
                            }
                            self.pendingReplies = pending
                            self.startReplyDrainTimer()
                        }
                    } else if status == "failed" {
                        print("AI Engine failed")
                    } else {
                        // generating状態 -> 再度ポーリング
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { check() }
                    }
                }
            }.resume()
        }
        check()
    }
    
    private func startReplyDrainTimer() {
        replyTimer?.cancel()
        replyTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            if !self.pendingReplies.isEmpty, !self.posts.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.posts[0].replies.append(self.pendingReplies.removeFirst())
                }
            } else {
                self.replyTimer?.cancel()
            }
        }
    }
}
