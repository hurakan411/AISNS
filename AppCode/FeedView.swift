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
        .alert("返信を送信できませんでした", isPresented: Binding(
            get: { appState.replyErrorMessage != nil },
            set: { isPresented in
                if !isPresented { appState.replyErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.replyErrorMessage ?? "通信状態を確認して、もう一度お試しください。")
        }
    }
}

struct PostCard: View {
    @EnvironmentObject var appState: AppState
    let post: PostModel
    @State private var regularFollowerAlert: RegularFollowerAlert?
    @State private var replyTarget: Reply?
    
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
                        VStack(alignment: .leading, spacing: 10) {
                            ReplyRow(
                                reply: reply,
                                isRegular: !reply.isUserReply && appState.isRegularFollower(reply),
                                canManageRegulars: !appState.isInOnboarding && !reply.isUserReply,
                                canReply: !appState.isInOnboarding && reply.canReceiveUserReply,
                                showsThreadToggle: reply.hasUserReply,
                                isThreadExpanded: appState.isReplyThreadExpanded(reply.id),
                                onReplyTap: {
                                    replyTarget = reply
                                },
                                onThreadTap: {
                                    appState.toggleReplyThread(reply.id)
                                }
                            ) {
                                guard !appState.isRegularFollower(reply) else { return }
                                if appState.regularFollowers.count >= appState.maxRegularFollowers {
                                    regularFollowerAlert = .limitReached(maximum: appState.maxRegularFollowers)
                                } else {
                                    regularFollowerAlert = .confirm(reply: reply)
                                }
                            }

                            if appState.isReplyThreadExpanded(reply.id),
                               let thread = post.replyThreads.first(where: { $0.targetReplyID == reply.id }) {
                                ReplyThreadView(
                                    thread: thread,
                                    isLoading: appState.isReplyThreadLoading(reply.id)
                                )
                                .environmentObject(appState)
                            }
                        }
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
        .alert(item: $regularFollowerAlert) { alert in
            switch alert {
            case .confirm(let reply):
                return Alert(
                    title: Text("@\(reply.authorName)を常連にしますか？"),
                    message: Text("今後の投稿にも同じ名前と記憶を持って返信します。会話記憶は端末に保存され、返信生成時にOpenAIへ送信されます。"),
                    primaryButton: .default(Text("常連にする")) {
                        _ = appState.addRegularFollower(from: reply, postContent: post.content)
                    },
                    secondaryButton: .cancel(Text("キャンセル"))
                )
            case .limitReached(let maximum):
                return Alert(
                    title: Text("常連の上限に達しています"),
                    message: Text("現在のランクでは最大\(maximum)人まで設定できます。プロフィール画面から常連を解除してから、もう一度お試しください。"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(item: $replyTarget) { target in
            ReplyComposerView(post: post, target: target)
                .environmentObject(appState)
        }
    }
}

private enum RegularFollowerAlert: Identifiable {
    case confirm(reply: Reply)
    case limitReached(maximum: Int)

    var id: String {
        switch self {
        case .confirm(let reply): return "confirm-\(reply.id.uuidString)"
        case .limitReached(let maximum): return "limit-\(maximum)"
        }
    }
}

struct ReplyRow: View {
    @EnvironmentObject var appState: AppState
    let reply: Reply
    let isRegular: Bool
    let canManageRegulars: Bool
    let canReply: Bool
    let showsThreadToggle: Bool
    let isThreadExpanded: Bool
    let onReplyTap: () -> Void
    let onThreadTap: () -> Void
    let onRegularTap: () -> Void

    private var displayName: String {
        reply.isUserReply ? appState.userName : "@\(reply.authorName)"
    }

    private var nameColor: Color {
        if reply.isUserReply { return Theme.cyan }
        if reply.isHater { return .red }
        if reply.isDefender { return .green }
        return Theme.hotPink
    }

    private var avatarStrokeColor: Color {
        if reply.isUserReply { return Theme.cyan }
        if reply.isHater { return .red }
        return Color.gray.opacity(0.3)
    }

    private var avatarStrokeWidth: CGFloat {
        reply.isUserReply || reply.isHater ? 2 : 1
    }

    private var cardBackground: Color {
        if reply.isUserReply { return Theme.cyan.opacity(0.1) }
        if reply.isHater { return Color(red: 0.2, green: 0, blue: 0).opacity(0.4) }
        if reply.isDefender { return Color(red: 0, green: 0.2, blue: 0).opacity(0.2) }
        return Color(white: 0.1).opacity(0.5)
    }

    private var cardStrokeColor: Color {
        if reply.isUserReply { return Theme.cyan.opacity(0.5) }
        if reply.isHater { return Color.red.opacity(0.5) }
        if reply.isDefender { return Color.green.opacity(0.5) }
        return Color.white.opacity(0.05)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if reply.isUserReply,
                   let data = appState.userAvatarData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
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
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(avatarStrokeColor, lineWidth: avatarStrokeWidth))
            .shadow(color: reply.isHater ? Color.red.opacity(0.5) : .clear, radius: reply.isHater ? 6 : 0)
            .padding(.top, 16) // テキストのpadding(16)と高さを完全に揃えるため、アバターも同じだけ下げる
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(nameColor)

                    if reply.isUserReply {
                        Text("あなた")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.cyan.opacity(0.18))
                            .foregroundColor(Theme.cyan)
                            .cornerRadius(10)
                    }
                    
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
                    if isRegular {
                        Text("REGULAR")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.cyan.opacity(0.18))
                            .foregroundColor(Theme.cyan)
                            .cornerRadius(10)
                    }
                    Spacer()
                    if canReply {
                        Button(action: onReplyTap) {
                            Image(systemName: "arrowshape.turn.up.left.circle")
                                .foregroundColor(Theme.cyan)
                                .font(.system(size: 18, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("このAIに返信")
                    }
                    if showsThreadToggle {
                        Button(action: onThreadTap) {
                            HStack(spacing: 3) {
                                Image(systemName: isThreadExpanded ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                Text(isThreadExpanded ? "閉じる" : "会話")
                            }
                            .foregroundColor(Theme.cyan)
                            .font(.system(size: 10, weight: .black))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isThreadExpanded ? "会話を閉じる" : "会話を表示")
                    }
                    if canManageRegulars {
                        Button(action: onRegularTap) {
                            Image(systemName: isRegular ? "star.circle.fill" : "star.circle")
                                .foregroundColor(isRegular ? .yellow : .gray.opacity(0.8))
                                .font(.system(size: 18, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRegular)
                        .accessibilityLabel(isRegular ? "常連設定済み" : "常連に設定")
                    }
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
            .background(cardBackground)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardStrokeColor, lineWidth: 1))
            
            Spacer(minLength: 16)
        }
        .padding(.trailing, 16)
    }
}

struct ReplyThreadView: View {
    @EnvironmentObject var appState: AppState
    let thread: ReplyThread
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(Theme.cyan)
                Text("この返信から続く会話")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Theme.cyan)
                Spacer()
            }

            ForEach(thread.replies) { reply in
                ReplyRow(
                    reply: reply,
                    isRegular: !reply.isUserReply && appState.isRegularFollower(reply),
                    canManageRegulars: false,
                    canReply: false,
                    showsThreadToggle: false,
                    isThreadExpanded: false,
                    onReplyTap: {},
                    onThreadTap: {}
                ) {}
            }

            if isLoading {
                HStack {
                    Spacer()
                    LottieAnimationUIView(name: "Loading Pink Dots")
                        .frame(height: 58)
                        .frame(maxWidth: 130)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 12)
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.cyan.opacity(0.7))
                .frame(width: 2)
        }
        .cornerRadius(16)
    }
}

struct ReplyComposerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let post: PostModel
    let target: Reply
    @State private var text = ""
    @State private var isSending = false
    @State private var showError = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !appState.isSubmittingUserReply
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@\(target.authorName)に返信")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Theme.cyan)
                    Text(target.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(minHeight: 130)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("返信を書く…")
                                .foregroundColor(.gray.opacity(0.7))
                                .padding(.top, 20)
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }

                Text("返信は1回限りです。送信後、@\(target.authorName)を起点に他のAIも会話へ参加します。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(20)
            .background(Theme.bgDeepBlack.ignoresSafeArea())
            .navigationTitle("AIに返信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSending = true
                        appState.submitReply(to: target, postID: post.id, text: text, onStarted: {
                            dismiss()
                        }) { success in
                            if success {
                                // 送信直後に専用スレッドを表示し、AI返信はその中で到着順に表示する。
                            } else {
                                isSending = false
                                showError = true
                            }
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("送信")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .alert("返信を送信できませんでした", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("通信状態を確認して、もう一度お試しください。")
            }
        }
    }
}
