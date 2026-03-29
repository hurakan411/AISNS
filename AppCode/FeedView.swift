import SwiftUI

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    var onGoPost: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if appState.posts.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "plus.square.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("今の状況を呟いて、\n称賛の嵐を受け取ろう。")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray.opacity(0.6))
                        Button(action: onGoPost) {
                            Text("投稿を作成する")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(Theme.hotPink)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Theme.hotPink.opacity(0.1))
                                .overlay(Capsule().stroke(Theme.hotPink.opacity(0.3), lineWidth: 1))
                        }
                    }
                    .padding(.top, 120)
                } else {
                    VStack(spacing: 40) {
                        ForEach(appState.posts) { post in
                            PostCard(post: post)
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .refreshable {
            appState.fetchUser()
        }
    }
}

struct PostCard: View {
    @EnvironmentObject var appState: AppState
    let post: PostModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Post Area
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                    } else {
                        AsyncImage(url: URL(string: Theme.myAvatar)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.purple)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.userName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text(post.time)
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Text(post.content)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .lineSpacing(6)
                
                if let data = post.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(20)
                        .padding(.horizontal, 16)
                }
                
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill").foregroundColor(Theme.hotPink).font(.system(size: 18))
                        Text("\(post.likes)").font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(Theme.hotPink)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.right.fill").foregroundColor(Theme.cyan).font(.system(size: 16))
                        Text("\(post.replies.count)").font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(Theme.cyan)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3))
            }
            .background(Theme.cardBackground)
            .cornerRadius(28)
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 16)
            
            if !post.replies.isEmpty || (appState.posts.first?.id == post.id && (appState.hasPendingReplies || appState.isRequestingReplies)) {
                VStack(spacing: 12) {
                    // 返信0件かつリクエスト中、またはまだ保留返信がある間はLoading Dots表示
                    if appState.posts.first?.id == post.id && (appState.hasPendingReplies || (post.replies.isEmpty && appState.isRequestingReplies)) {
                        HStack {
                            Spacer()
                            LottieAnimationUIView(name: "Loading Pink Dots")
                                .frame(height: 70)
                                .frame(maxWidth: 140)
                            Spacer()
                        }
                    }

                    ForEach(post.replies) { reply in
                        ReplyRow(reply: reply)
                    }
                }
                .padding(.top, 20)
                .padding(.leading, 32)
                .overlay(
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.4), .clear]), startPoint: .top, endPoint: .bottom))
                        .frame(width: 2)
                        .padding(.leading, 22)
                        .padding(.top, 24)
                    , alignment: .topLeading
                )
            }
        }
    }
}

struct ReplyRow: View {
    let reply: Reply
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: reply.img)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(reply.isHater ? .gray : Theme.hotPink)
                } else {
                    Circle().fill(reply.isHater ? Color.gray : Color.purple)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(reply.isHater ? Color.red : Color.gray.opacity(0.3), lineWidth: reply.isHater ? 2 : 1))
            .shadow(color: reply.isHater ? Color.red.opacity(0.5) : .clear, radius: reply.isHater ? 6 : 0)
            .padding(.top, 16) // テキストのpadding(16)と高さを完全に揃えるため、アバターも同じだけ下げる
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("@\(reply.authorName)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(reply.isHater ? .red : reply.isDefender ? .green : Theme.hotPink)
                    
                    if reply.isHater {
                        Text("HATER")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    } else if reply.isDefender {
                        Text("GUARDIAN")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                    }
                    Spacer()
                    if reply.isHater {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 12))
                    } else if reply.isDefender {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green).font(.system(size: 12))
                    }
                }
                
                Text(reply.text)
                    .font(.system(size: 14, weight: reply.isHater ? .bold : .medium))
                    .foregroundColor(reply.isHater ? .white : .white.opacity(0.9))
                    .lineSpacing(4)
            }
            .padding(16)
            .background(
                reply.isHater ? Color(red: 0.2, green: 0, blue: 0).opacity(0.4) :
                reply.isDefender ? Color(red: 0, green: 0.2, blue: 0).opacity(0.2) :
                Color(white: 0.1).opacity(0.5)
            )
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(reply.isHater ? Color.red.opacity(0.5) : reply.isDefender ? Color.green.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1))
            
            Spacer(minLength: 16)
        }
        .padding(.trailing, 16)
    }
}
