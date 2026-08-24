import SwiftUI

/// App Store ガイドライン 5.1.1(i) / 5.1.2(i) 対応
/// 初回起動時にのみ表示する、AIデータ送信に関するプライバシー同意画面。
/// ユーザーが「同意する」を選択すると `hasAcceptedPrivacyPolicy` が true になり、
/// 以降は表示されない。
struct PrivacyConsentView: View {
    @Binding var hasAccepted: Bool
    let userID: String
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            Theme.bgDeepBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── アイコン & タイトル ──
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Theme.hotPink.opacity(0.25), Color.purple.opacity(0.2)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.hotPink)
                    }
                    .neonShadow(color: Theme.hotPink, radius: 20)

                    Text("データ取扱と\nプライバシーポリシーについて")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)

                // ── 説明カード ──
                VStack(alignment: .leading, spacing: 20) {
                    DataRow(
                        icon: "text.bubble.fill",
                        iconColor: Theme.cyan,
                        title: "送信されるデータ",
                        description: "投稿・返信テキスト、添付画像（任意）、常連AIの会話記憶（設定時）"
                    )
                    Divider().background(Color.white.opacity(0.08))
                    DataRow(
                        icon: "server.rack",
                        iconColor: .purple,
                        title: "送信先",
                        description: "OpenAI（ChatGPT API）— AIリプライ生成のみに使用"
                    )
                    Divider().background(Color.white.opacity(0.08))
                    DataRow(
                        icon: "person.badge.shield.checkmark.fill",
                        iconColor: .green,
                        title: "保存・販売はしません",
                        description: "送信データはAI処理後に保持されず、第三者への販売は行いません"
                    )
                    Divider().background(Color.white.opacity(0.08))
                    DataRow(
                        icon: "chart.bar.xaxis",
                        iconColor: .orange,
                        title: "利用状況の計測",
                        description: "匿名のユーザーIDで、起動・投稿・AI返信などの利用状況を計測します"
                    )
                }
                .padding(24)
                .background(Color.white.opacity(0.05))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // ── プライバシーポリシーリンク ──
                Button(action: { showPrivacyPolicy = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13))
                        Text("プライバシーポリシーを読む")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Theme.cyan)
                    .padding(.top, 24)
                }

                Spacer()

                // ── 同意ボタン ──
                VStack(spacing: 12) {
                    Button(action: {
                        UserDefaults.standard.set(true, forKey: "hasAcceptedPrivacyPolicy")
                        UPMEAnalytics.start(userID: userID)
                        UPMEAnalytics.capture("privacy_accepted")
                        UPMEAnalytics.recordActiveSession(userID: userID)
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasAccepted = true
                        }
                    }) {
                        Text("同意してはじめる")
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Theme.hotPink, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(28)
                            .neonShadow(color: Theme.hotPink, radius: 12)
                    }

                    Text("同意することで、プライバシーポリシーおよび\n利用規約に同意したものとみなされます。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalTextView(title: "プライバシーポリシー", text: privacyPolicyText)
        }
    }
}

// MARK: - Sub-components

private struct DataRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(1)
                Text(description)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
