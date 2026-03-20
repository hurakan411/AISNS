import SwiftUI

struct Theme {
    static let bgDeepBlack = Color(red: 0.004, green: 0.004, blue: 0.008)
    static let hotPink = Color(red: 0.925, green: 0.282, blue: 0.6)
    static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933)
    static let cardBackground = Color(white: 0.08)
    
    static let myAvatar = "https://images.unsplash.com/photo-1502685104226-ee32379fefbe?w=150&h=150&fit=crop"
    static let fallbackImg = "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=1000"
}

extension View {
    func neonShadow(color: Color = Theme.hotPink, radius: CGFloat = 10) -> some View {
        self.shadow(color: color.opacity(0.6), radius: radius, x: 0, y: 0)
    }
}
