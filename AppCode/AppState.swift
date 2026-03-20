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
    
    init() { }
    
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
        
        generateMockReplies(forRank: rank)
        
        var increments = 0
        likeTimer?.cancel()
        likeTimer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            var boost = Int.random(in: 10...30)
            if rank >= 4 { boost *= 10 }
            if rank >= 8 { boost *= 100 }
            
            if !self.posts.isEmpty {
                self.posts[0].likes += boost
            }
            
            // フォロワー数の増加はいいねの増加量に比例させる
            let followerBoost = Int(Double(boost) * Double.random(in: 0.05...0.20))
            self.followers += max(1, followerBoost)
            
            increments += 1
            if increments >= 45 { self.likeTimer?.cancel() }
        }
        
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
    
    private func generateMockReplies(forRank rank: Int) {
        pendingReplies = []
        let totalCount = rank * 2 + 3
        let haterCount = (rank < 4) ? 0 : 1
        
        var generated = 0
        for i in 1...min(3, totalCount) {
            pendingReplies.append(Reply(authorName: "ファン\(i)", text: "最高すぎます！✨", img: avatars.randomElement()!, isHater: false, isDefender: false))
            generated += 1
        }
        
        if generated < totalCount && haterCount > 0 {
            pendingReplies.append(Reply(authorName: "匿名ユーザー", text: "わざわざ投稿する内容？日記にでも書けばｗ", img: haterAvatar, isHater: true, isDefender: false))
            generated += 1
            if rank >= 4 && generated < totalCount {
                pendingReplies.append(Reply(authorName: "ひまり", text: "こういう何気ない日常が一番癒やされるんだよ。分かってないな。", img: avatars.randomElement()!, isHater: false, isDefender: true))
                generated += 1
            }
        }
        
        while generated < totalCount {
            pendingReplies.append(Reply(authorName: "信者\(generated)", text: "勇気もらいました！ありがとうございます😭", img: avatars.randomElement()!, isHater: false, isDefender: false))
            generated += 1
        }
    }
}
