import SwiftUI

enum Tab {
    case home, post, stats, profile
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var activeTab: Tab = .home
    
    var body: some View {
        ZStack {
            Theme.bgDeepBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Status Bar Header
                if activeTab != .post && activeTab != .profile {
                    HStack(spacing: 12) {
                        Text("ZEN-KOTEI")
                            .font(.system(size: 20, weight: .black, design: .rounded)).italic()
                            .foregroundColor(.clear)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [Theme.hotPink, .purple, Theme.cyan]), startPoint: .leading, endPoint: .trailing)
                                    .mask(Text("ZEN-KOTEI").font(.system(size: 20, weight: .black, design: .rounded)).italic())
                            )
                            .neonShadow(color: Theme.hotPink, radius: 4)
                            
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Theme.hotPink).frame(width: 6, height: 6).neonShadow().animatePulse()
                            Text("LIVE SYNCED").font(.system(size: 10, weight: .black)).foregroundColor(.gray).tracking(1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.bgDeepBlack)
                    .zIndex(1)
                }
                
                // Maint Content
                ZStack {
                    switch activeTab {
                    case .home:
                        FeedView { activeTab = .post }
                            .transition(.opacity)
                    case .post:
                        PostView { activeTab = .home }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .stats:
                        StatsView()
                            .transition(.opacity)
                    case .profile:
                        ProfileView()
                            .transition(.opacity)
                            .ignoresSafeArea(edges: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                NavBtn(icon: "house.fill", label: "ホーム", isActive: activeTab == .home) { withAnimation { activeTab = .home } }
                Spacer()
                NavBtn(icon: "plus.app.fill", label: "", isActive: activeTab == .post, isCenter: true) { withAnimation { activeTab = .post } }
                Spacer()
                NavBtn(icon: "chart.bar.fill", label: "統計", isActive: activeTab == .stats) { withAnimation { activeTab = .stats } }
                Spacer()
                NavBtn(icon: "person.fill", label: "プロフ", isActive: activeTab == .profile) { withAnimation { activeTab = .profile } }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color.black.opacity(0.85).background(Material.ultraThin).ignoresSafeArea(edges: .bottom))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
        }
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
    let icon: String
    let label: String
    let isActive: Bool
    var isCenter: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isCenter ? 32 : 24))
                    .foregroundColor(isActive ? Theme.hotPink : .gray.opacity(0.5))
                    .neonShadow(color: isActive ? Theme.hotPink : .clear, radius: isActive ? 8 : 0)
                
                if !isCenter {
                    Text(label)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(isActive ? Theme.hotPink : .gray.opacity(0.5))
                        .textCase(.uppercase)
                }
            }
            .offset(y: isCenter ? -10 : 0)
            .scaleEffect(isActive ? 1.05 : 1.0)
        }
    }
}
