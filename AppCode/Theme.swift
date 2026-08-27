import SwiftUI

struct Theme {
    static let bgDeepBlack = Color(red: 0.008, green: 0.006, blue: 0.018)
    static let hotPink = Color(red: 0.925, green: 0.282, blue: 0.6)
    static let deepPurple = Color(red: 0.105, green: 0.063, blue: 0.18)
    static let purpleAccent = Color(red: 0.435, green: 0.263, blue: 0.71)
    static let lavender = Color(red: 0.67, green: 0.49, blue: 0.88)
    // 既存画面の補助色は互換性を保ちつつ、シアンから紫へ統一する。
    static let cyan = purpleAccent
    static let cardBackground = Color(red: 0.052, green: 0.045, blue: 0.075)
    static let aiCardBackground = Color(red: 0.075, green: 0.052, blue: 0.12)
    static let subtleBorder = purpleAccent.opacity(0.24)
    static let accentGradient = LinearGradient(
        colors: [hotPink, purpleAccent, lavender],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let myAvatar = "https://images.unsplash.com/photo-1502685104226-ee32379fefbe?w=150&h=150&fit=crop"
    static let fallbackImg = "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=1000"
}

extension View {
    func neonShadow(color: Color = Theme.hotPink, radius: CGFloat = 10) -> some View {
        self.shadow(color: color.opacity(0.42), radius: radius, x: 0, y: 0)
    }
}
