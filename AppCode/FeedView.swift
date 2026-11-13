import SwiftUI

struct AIReplyVisibility: Equatable {
    let replyID: String
    let postFlowID: String
    let isOnboardingPost: Bool
    let isRegular: Bool
    let replyCount: Int
    let frame: CGRect
}

struct AIReplyVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [String: AIReplyVisibility] = [:]

    static func reduce(value: inout [String: AIReplyVisibility], nextValue: () -> [String: AIReplyVisibility]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct AIReplyVisibilityTracker: ViewModifier {
    let viewportSize: CGSize
    var isSuppressed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var replyFrames: [String: AIReplyVisibility] = [:]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "feedViewport")
            .onPreferenceChange(AIReplyVisibilityPreferenceKey.self) { replies in
                replyFrames = replies
                captureVisibleReplies(replies)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { captureVisibleReplies(replyFrames) }
            }
            .onChange(of: viewportSize) { _, _ in
                captureVisibleReplies(replyFrames)
            }
            .onChange(of: isSuppressed) { _, suppressed in
                if !suppressed { captureVisibleReplies(replyFrames) }
            }
    }

    private func captureVisibleReplies(_ replies: [String: AIReplyVisibility]) {
        guard scenePhase == .active, !isSuppressed else { return }
        let viewport = CGRect(origin: .zero, size: viewportSize)
        let visibleReplies = replies.values
            .filter { AnalyticsReplyVisibility.isVisible(frame: $0.frame, viewport: viewport) }
            .sorted { $0.frame.minY < $1.frame.minY }
        for reply in visibleReplies {
            UPMEAnalytics.captureAIRepliesViewed(postFlowID: reply.postFlowID, properties: [
                "post_flow_id": reply.postFlowID,
                "is_onboarding": reply.isOnboardingPost,
                "reply_count": reply.replyCount,
                "first_visible_reply_is_regular": reply.isRegular
            ])
        }
    }
}

struct HomeGuideSelection: Equatable {
    var postID: UUID?
    var aiReplyID: UUID?
    var replyActionID: UUID?
    var regularActionID: UUID?
}

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var guide: HomeGuideCoordinator
    @State private var frozenGuideSelection: HomeGuideSelection?
    var onGoPost: () -> Void

    private var liveGuideSelection: HomeGuideSelection {
        let replies = appState.posts.flatMap(\.replies).filter {
            !$0.isUserReply && $0.replyToId == nil && !$0.isHater && !$0.isDefender
        }
        return HomeGuideSelection(
            postID: appState.posts.first?.id,
            aiReplyID: replies.first?.id,
            replyActionID: replies.first(where: \.canReceiveUserReply)?.id,
            regularActionID: replies.first(where: { !appState.isRegularFollower($0) })?.id
        )
    }

    private var guideSelection: HomeGuideSelection { frozenGuideSelection ?? liveGuideSelection }
    
    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { scroll in
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
                                .homeGuideTarget(.compose)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                        } else {
                            Button(action: onGoPost) {
                                HStack(spacing: 12) {
                                    Image(systemName: "pencil.line")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Theme.hotPink)
                                    Text("いま、なに思ってる？")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Theme.lavender)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Theme.cardBackground)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.subtleBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .homeGuideTarget(.compose)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                            VStack(spacing: 32) {
                                ForEach(appState.posts) { post in
                                    PostCard(post: post, guideSelection: guideSelection)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .modifier(AIReplyVisibilityTracker(viewportSize: viewport.size, isSuppressed: guide.isPresenting))
                .task(id: guide.activeStep) {
                    guard let step = guide.activeStep else { return }
                    do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        scroll.scrollTo(step, anchor: .center)
                    }
                }
                .onChange(of: viewport.size) { _, _ in
                    if let step = guide.activeStep { scroll.scrollTo(step, anchor: .center) }
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
                    Text(appState.replyErrorMessage ?? appState.text("通信状態を確認して、もう一度お試しください。", "Check your connection and try again."))
                }
            }
        }
        .transformAnchorPreference(key: HomeGuideAnchorPreference.self, value: .bounds) { targets, anchor in
            targets[.viewport] = anchor
        }
        .onChange(of: guide.isPresenting) { _, presenting in
            frozenGuideSelection = presenting ? liveGuideSelection : nil
        }
    }
}

private struct ViralPostBorder: View {
    let startedAt: Date
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt) - 3)
            let angle = active && !reduceMotion ? elapsed * 40 : 0
            let colors = active
                ? [Theme.hotPink.opacity(0.5), Theme.purpleAccent.opacity(0.5), Theme.lavender, Theme.hotPink.opacity(0.5)]
                : [Theme.hotPink.opacity(0.35), Theme.purpleAccent.opacity(0.3)]
            RoundedRectangle(cornerRadius: 22)
                .stroke(AngularGradient(colors: colors, center: .center, angle: .degrees(angle)), lineWidth: active ? 1.8 : 1)
                .shadow(color: Theme.hotPink.opacity(active ? 0.24 : 0), radius: 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PostCard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let post: PostModel
    var guideSelection = HomeGuideSelection()
    @State private var regularFollowerAlert: RegularFollowerAlert?
    @State private var replyTarget: Reply?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Post Area
            VStack(alignment: .leading, spacing: 16) {
                if appState.isViralRevealed(post) {
                    Label(appState.isViralAnimating(post)
                          ? appState.text("この投稿、バズっています", "This post is going viral")
                          : appState.text("バズった投稿", "Viral post"), systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.hotPink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.hotPink.opacity(0.12), in: Capsule())
                        .padding(.horizontal, 20).padding(.top, 16)
                        .transition(.opacity)
                }
                HStack(alignment: .top, spacing: 12) {
                    if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.hotPink.opacity(0.75), lineWidth: 2))
                    } else {
                        Image(Theme.defaultAvatarAsset)
                            .resizable()
                            .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.hotPink.opacity(0.75), lineWidth: 2))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.userName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text((post.time == "今" || post.time == "Now") ? appState.text("今", "Now") : post.time)
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, appState.isViralRevealed(post) ? 0 : 20)
                
                Text(post.content)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .lineSpacing(6)
                
                if let data = post.imageData, let uiImage = UIImage(data: data) {
                    PostAttachmentImage(image: uiImage, height: 180, cornerRadius: 20)
                        .padding(.horizontal, 16)
                }
                
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill").foregroundColor(Theme.hotPink).font(.system(size: 18))
                            .symbolEffect(.bounce, options: .nonRepeating, value: appState.isViralAnimating(post) && !reduceMotion)
                        Text("\(appState.displayedLikes(for: post))").font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(Theme.hotPink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: appState.displayedLikes(for: post))
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
                .homeGuideTarget(guideSelection.postID == post.id ? .reactions : nil)

                if let reaction = post.reaction, reaction.isViral, reaction.followersAfter != nil {
                    Label(appState.text("フォロワー ＋\(reaction.followerGain)", "+\(reaction.followerGain) followers"), systemImage: "person.badge.plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.lavender)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.purpleAccent.opacity(0.14), in: Capsule())
                        .padding(.horizontal, 20).padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .background(Theme.cardBackground)
            .cornerRadius(22)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.subtleBorder, lineWidth: 1))
            .overlay {
                if appState.isViralRevealed(post) {
                    ViralPostBorder(startedAt: post.reaction?.startedAt ?? .distantPast,
                                    active: appState.isViralAnimating(post), reduceMotion: reduceMotion)
                }
            }
            .homeGuideTarget(guideSelection.postID == post.id ? .buzz : nil)
            .padding(.horizontal, 16)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: appState.isViralRevealed(post))
            .sensoryFeedback(.success, trigger: appState.isViralAnimating(post)) { _, active in active && !reduceMotion }
            
            if !post.replies.isEmpty || appState.isWaitingForReplies(to: post) {
                VStack(spacing: 12) {
                    // 返信0件かつリクエスト中、またはまだ保留返信がある間はLoading Dots表示
                    if appState.isWaitingForReplies(to: post) {
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
                                analyticsPostFlowID: post.id,
                                analyticsIsOnboardingPost: post.isOnboarding,
                                analyticsTopLevelReplyCount: post.replies.filter { !$0.isUserReply && $0.replyToId == nil }.count,
                                guideReplyCard: guideSelection.aiReplyID == reply.id,
                                guideReplyAction: guideSelection.replyActionID == reply.id,
                                guideRegularAction: guideSelection.regularActionID == reply.id,
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
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: post.replies.count)
                .padding(.top, 20)
                .padding(.leading, 32)
                .overlay(
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Theme.hotPink.opacity(0.7), Theme.purpleAccent.opacity(0.45), .clear]), startPoint: .top, endPoint: .bottom))
                        .frame(width: 2)
                        .padding(.leading, 22)
                        .padding(.top, 24)
                    , alignment: .topLeading
                )
            }
        }
        .preference(key: HomeGuideModalPreference.self, value: replyTarget != nil || regularFollowerAlert != nil)
        .alert(item: $regularFollowerAlert) { alert in
            switch alert {
            case .confirm(let reply):
                return Alert(
                    title: Text(appState.text("@\(reply.authorName)を常連にしますか？", "Make @\(reply.authorName) a regular?")),
                    message: Text(appState.text("今後の投稿にも同じ名前と記憶を持って返信します。会話記憶は端末に保存され、返信生成時にOpenAIへ送信されます。", "They will reply to future posts with the same name and memory. Conversation memory is stored on this device and sent to OpenAI when generating replies.")),
                    primaryButton: .default(Text("常連にする")) {
                        _ = appState.addRegularFollower(from: reply, postContent: post.content)
                    },
                    secondaryButton: .cancel(Text("キャンセル"))
                )
            case .limitReached(let maximum):
                return Alert(
                    title: Text(appState.text("常連の上限に達しています", "Regular follower limit reached")),
                    message: Text(appState.text("現在のランクでは最大\(maximum)人まで設定できます。プロフィール画面から常連を解除してから、もう一度お試しください。", "Your current rank allows up to \(maximum) regular followers. Remove one from your profile and try again.")),
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
    var analyticsPostFlowID: UUID? = nil
    var analyticsIsOnboardingPost: Bool = false
    var analyticsTopLevelReplyCount: Int = 0
    var guideReplyCard = false
    var guideReplyAction = false
    var guideRegularAction = false
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
        if reply.isUserReply { return Theme.hotPink }
        if reply.isHater { return .red }
        if reply.isDefender { return .green }
        return Theme.lavender
    }

    private var avatarStrokeColor: Color {
        if reply.isUserReply { return Theme.hotPink }
        if reply.isHater { return .red }
        return Theme.purpleAccent.opacity(0.65)
    }

    private var avatarStrokeWidth: CGFloat {
        reply.isUserReply || reply.isHater ? 2 : 1
    }

    private var cardBackground: Color {
        if reply.isUserReply { return Theme.hotPink.opacity(0.10) }
        if reply.isHater { return Color(red: 0.2, green: 0, blue: 0).opacity(0.4) }
        if reply.isDefender { return Color(red: 0, green: 0.2, blue: 0).opacity(0.2) }
        return Theme.aiCardBackground.opacity(0.9)
    }

    private var cardStrokeColor: Color {
        if reply.isUserReply { return Theme.hotPink.opacity(0.45) }
        if reply.isHater { return Color.red.opacity(0.5) }
        if reply.isDefender { return Color.green.opacity(0.5) }
        return Theme.subtleBorder
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
                } else if reply.isUserReply {
                    Image(Theme.defaultAvatarAsset)
                        .resizable()
                        .scaledToFill()
                } else {
                    AIAvatarImage(url: reply.img, isHater: reply.isHater)
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

                    if !reply.isUserReply && !reply.isHater && !reply.isDefender {
                        Text("AI")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.purpleAccent.opacity(0.45))
                            .foregroundColor(.white.opacity(0.9))
                            .cornerRadius(4)
                    }

                    if reply.isUserReply {
                        Text("あなた")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.hotPink.opacity(0.18))
                            .foregroundColor(Theme.hotPink)
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
                            .background(Theme.purpleAccent.opacity(0.22))
                            .foregroundColor(Theme.lavender)
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
                        .homeGuideTarget(guideReplyAction ? .reply : nil)
                    }
                    if showsThreadToggle {
                        Button(action: onThreadTap) {
                            HStack(spacing: 3) {
                                Image(systemName: isThreadExpanded ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                Text(appState.text(isThreadExpanded ? "閉じる" : "会話", isThreadExpanded ? "Close" : "Thread"))
                            }
                            .foregroundColor(Theme.cyan)
                            .font(.system(size: 10, weight: .black))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(appState.text(isThreadExpanded ? "会話を閉じる" : "会話を表示", isThreadExpanded ? "Close thread" : "Show thread"))
                    }
                    if canManageRegulars {
                        Button(action: onRegularTap) {
                            Image(systemName: isRegular ? "star.circle.fill" : "star.circle")
                                .foregroundColor(isRegular ? Theme.hotPink : .gray.opacity(0.8))
                                .font(.system(size: 18, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRegular)
                        .accessibilityLabel(appState.text(isRegular ? "常連設定済み" : "常連に設定", isRegular ? "Already a regular" : "Make a regular"))
                        .homeGuideTarget(guideRegularAction && !isRegular ? .regular : nil)
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
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(cardStrokeColor, lineWidth: 1))
            .homeGuideTarget(guideReplyCard ? .aiReply : nil)
            
            Spacer(minLength: 16)
        }
        .padding(.trailing, 16)
        .background {
            GeometryReader { proxy in
                if !reply.isUserReply,
                   reply.replyToId == nil,
                   let postFlowID = analyticsPostFlowID {
                    Color.clear.preference(
                        key: AIReplyVisibilityPreferenceKey.self,
                        value: [reply.id.uuidString: AIReplyVisibility(
                            replyID: reply.id.uuidString,
                            postFlowID: postFlowID.uuidString.lowercased(),
                            isOnboardingPost: analyticsIsOnboardingPost,
                            isRegular: isRegular,
                            replyCount: analyticsTopLevelReplyCount,
                            frame: proxy.frame(in: .named("feedViewport"))
                        )]
                    )
                } else {
                    Color.clear
                }
            }
        }
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
                    Text(appState.text("@\(target.authorName)に返信", "Reply to @\(target.authorName)"))
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

                Text(appState.text("返信は1回限りです。送信後、@\(target.authorName)を起点に他のAIも会話へ参加します。", "You can reply once. After sending, other AIs will join the thread starting from @\(target.authorName)."))
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
