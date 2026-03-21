import SwiftUI
import PhotosUI

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
                
                HStack(spacing: 16) {
                    StatCard(title: "累計投稿数", value: "\(appState.totalPosts)", color: .green)
                    let totalLikes = appState.posts.reduce(0) { $0 + $1.likes }
                    StatCard(title: "累計いいね", value: "\(totalLikes)", color: .orange)
                    let totalReplies = appState.posts.reduce(0) { $0 + $1.replies.count }
                    StatCard(title: "累計リプライ", value: "\(totalReplies)", color: .purple)
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
        .refreshable {
            appState.fetchUser()
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
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(color.opacity(0.1))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isEditingName = false
    @State private var isEditingBio = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Image
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.indigo.opacity(0.5), Color.purple.opacity(0.5), .black]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 180)
                    
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        ZStack {
                            if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AsyncImage(url: URL(string: Theme.myAvatar)) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color.gray)
                                }
                            }
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 6))
                        .overlay(
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .background(Circle().fill(Theme.hotPink))
                                .offset(x: 30, y: 30)
                        )
                    }
                    .offset(x: 24, y: 45)
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                DispatchQueue.main.async {
                                    appState.userAvatarData = data
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if isEditingName {
                            TextField("ユーザー名", text: $appState.userName, onCommit: { isEditingName = false })
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            Text(appState.userName)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: { withAnimation { isEditingName.toggle() } }) {
                            Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.title2)
                                .foregroundColor(Theme.hotPink)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        if isEditingBio {
                            TextEditor(text: $appState.userBio)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .frame(minHeight: 80)
                        } else {
                            Text(appState.userBio)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .lineSpacing(6)
                        }
                        
                        Spacer()
                        
                        Button(action: { withAnimation { isEditingBio.toggle() } }) {
                            Image(systemName: isEditingBio ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 4)
                    }
                    

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)
                
                // Settings Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("SETTINGS")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(2)
                    
                    Toggle(isOn: $appState.isHaterEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アンチ・炎上の発生")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("高ランク到達時のアンチ登場をON/OFFします")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.hotPink))
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
            }
            .padding(.bottom, 40)
        }
        .refreshable {
            appState.fetchUser()
        }
    }
}
