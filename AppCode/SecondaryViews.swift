import SwiftUI

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundColor(Theme.cyan)
                    Text("アルゴリズム解析").font(.title).fontWeight(.black).foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                HStack(spacing: 16) {
                    StatCard(title: "フォロワー数", value: "\(appState.followers)", color: Theme.hotPink)
                    StatCard(title: "承認ランク", value: "Lv.\(appState.currentRank)", color: Theme.cyan)
                }
                .padding(.horizontal, 24)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("ランクステータス").font(.headline).foregroundColor(.gray).padding(.horizontal, 24)
                    Text(appState.rankName).font(.title3).fontWeight(.bold).foregroundColor(Theme.cyan).padding(.horizontal, 24)
                    
                    if let nextRank = appState.nextRankFollowers {
                        let diff = nextRank - appState.followers
                        Text("次のランクまであと **\(diff)** 人")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 24)
                        
                        ProgressView(value: Double(appState.followers), total: Double(nextRank))
                            .tint(Theme.cyan)
                            .padding(.horizontal, 24)
                    } else {
                        Text("最高ランク到達済み").font(.subheadline).foregroundColor(.white.opacity(0.7)).padding(.horizontal, 24)
                    }
                }
                .padding(.top, 16)
            }
            .padding(.bottom, 40)
        }
    }
}

struct StatCard: View {
    let title: String
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
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(color.opacity(0.1))
        .cornerRadius(32)
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Image
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.indigo.opacity(0.5), Color.purple.opacity(0.5), .black]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 180)
                    
                    AsyncImage(url: URL(string: Theme.myAvatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray)
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 6))
                    .offset(x: 24, y: 45)
                }
                .padding(.bottom, 40)
                
                VStack(alignment: .leading, spacing: 32) {
                    Text("みずき（あなた）")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(.white)
                    
                    HStack {
                        VStack(alignment: .center, spacing: 8) {
                            Text("\(appState.followers)")
                                .font(.system(size: 32, weight: .black, design: .monospaced))
                                .foregroundColor(Theme.hotPink)
                            Text("FOLLOWERS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(2)
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 8) {
                            Text("\(appState.totalPosts)")
                                .font(.system(size: 32, weight: .black, design: .monospaced))
                                .foregroundColor(Theme.cyan)
                            Text("POSTS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(2)
                        }
                    }
                    .padding(.vertical, 32)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .top)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .bottom)
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
            }
            .padding(.bottom, 40)
        }
    }
}
