import SwiftUI

enum OnboardingPhase: Int, Equatable {
    case fakeCompose
    case microReaction
    case blackout
    case ritual
    case realCompose
    case burst
}

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var phase: OnboardingPhase = .fakeCompose
    @State private var fakeText = ""
    @FocusState private var fakeFocused: Bool

    @State private var showMicroLikes = false
    @State private var microLikeCount: Int = 0
    @State private var showMicroReply = false

    @State private var ritualLine = 0
    @State private var ritualLogoVisible = false

    @State private var showStartButton = false
    @State private var burstSecondsElapsed: Int = 0

    private var isLightPhase: Bool {
        phase == .fakeCompose || phase == .microReaction
    }

    var body: some View {
        ZStack {
            (isLightPhase ? Color(red: 0.965, green: 0.965, blue: 0.975) : Theme.bgDeepBlack)
                .ignoresSafeArea()

            switch phase {
            case .fakeCompose:
                fakeComposeView
                    .transition(.opacity)
            case .microReaction:
                microReactionView
                    .transition(.opacity)
            case .blackout:
                Color.black.ignoresSafeArea()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.8)) { phase = .ritual }
                        }
                    }
            case .ritual:
                ritualView
                    .transition(.opacity)
            case .realCompose:
                realComposeView
                    .transition(.opacity)
            case .burst:
                burstView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: phase)
    }

    // MARK: - Phase 1: Fake Compose

    private var fakeComposeView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text("何でもいい。ひとことだけ。")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)

                if #available(iOS 16.0, *) {
                    TextEditor(text: $fakeText)
                        .focused($fakeFocused)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .foregroundColor(Color(white: 0.15))
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 120)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.85), lineWidth: 1))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                } else {
                    TextEditor(text: $fakeText)
                        .focused($fakeFocused)
                        .background(Color.clear)
                        .foregroundColor(Color(white: 0.15))
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 120)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.85), lineWidth: 1))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                }

                Button(action: {
                    guard !fakeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { phase = .microReaction }
                }) {
                    Text("投稿する")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            fakeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(white: 0.82)
                                : Color(red: 0.30, green: 0.30, blue: 0.35)
                        )
                        .cornerRadius(28)
                }
                .disabled(fakeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.6))
                    Text("個人情報（本名・住所・電話番号など）は入力しないでください")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fakeFocused = true }
        }
    }

    // MARK: - Phase 2: Micro Reaction (3 likes, 1 reply "で？")

    private var microReactionView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text(fakeText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(white: 0.2))
                    .lineSpacing(4)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)

                if showMicroLikes {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.35))
                        Text("\(microLikeCount)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.35))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .padding(.leading, 8)
                }

                if showMicroReply {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(white: 0.82))
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@nobody")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.55))
                            Text("で？")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(white: 0.3))
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) { showMicroLikes = true; microLikeCount = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.2)) { microLikeCount = 2 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeOut(duration: 0.2)) { microLikeCount = 3 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeOut(duration: 0.4)) { showMicroReply = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                withAnimation(.easeInOut(duration: 0.8)) { phase = .blackout }
            }
        }
    }

    // MARK: - Phase 4: Ritual Animation

    private var ritualView: some View {
        VStack(spacing: 24) {
            Spacer()

            if ritualLine >= 1 {
                Text("ここでは、")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            if ritualLine >= 2 {
                Text("あなたの声は否定されない。")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            if ritualLine >= 3 {
                Text("小さなひとことが、")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            if ritualLine >= 4 {
                Text("熱狂になる。")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(Theme.hotPink)
                    .neonShadow(color: Theme.hotPink, radius: 12)
                    .transition(.opacity)
            }

            if ritualLogoVisible {
                Text("ZEN-KOTEI")
                    .font(.system(size: 36, weight: .black, design: .rounded)).italic()
                    .foregroundColor(.clear)
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Theme.hotPink, .purple, Theme.cyan]), startPoint: .leading, endPoint: .trailing)
                            .mask(Text("ZEN-KOTEI").font(.system(size: 36, weight: .black, design: .rounded)).italic())
                    )
                    .neonShadow(color: Theme.hotPink, radius: 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    .padding(.top, 16)
            }

            Spacer()
        }
        .onAppear {
            let delays: [Double] = [0.6, 2.0, 3.6, 5.0]
            for (i, d) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                    withAnimation(.easeOut(duration: 0.6)) { ritualLine = i + 1 }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { ritualLogoVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
                withAnimation(.easeInOut(duration: 0.6)) { phase = .realCompose }
            }
        }
    }

    // MARK: - Phase 5: Real Compose

    private var realComposeView: some View {
        PostView(
            onCancel: {},
            onOnboardingSubmit: { text in
                appState.submitOnboardingPost(text: text)
                withAnimation(.easeInOut(duration: 0.6)) { phase = .burst }
            },
            isOnboarding: true
        )
    }

    // MARK: - Phase 6: Burst (Rank 10 explosion)

    private var burstView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if let post = appState.posts.first {
                        PostCard(post: post)
                    }
                }
                .padding(.vertical, 24)
                .padding(.bottom, 100)
            }

            if showStartButton {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        appState.completeOnboarding()
                    }
                }) {
                    Text("ZEN-KOTEIを始める")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(gradient: Gradient(colors: [Theme.hotPink, .purple]), startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(28)
                        .neonShadow(color: Theme.hotPink, radius: 12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { scheduleBurstStartButton() }
    }

    private func scheduleBurstStartButton() {
        func checkOrWait() {
            let shown = appState.posts.first?.replies.count ?? 0
            let total = appState.onboardingExpectedReplies
            let threshold = total > 0 ? Int(ceil(Double(total) * 0.8)) : 8
            if shown >= threshold {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showStartButton = true }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { checkOrWait() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { checkOrWait() }
    }
}
