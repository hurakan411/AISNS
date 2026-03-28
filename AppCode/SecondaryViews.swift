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

                RankGuideSection(currentRank: appState.currentRank)
            }
            .padding(.bottom, 40)
        }
        .refreshable {
            appState.fetchUser()
        }
    }
}

struct RankInfo {
    let level: Int
    let name: String
    let followers: String
    let replies: String
    let haters: String
    let likes: String
}

private let rankData: [RankInfo] = [
    RankInfo(level: 1,  name: "名もなき市民",             followers: "0〜99",          replies: "3〜5",   haters: "なし",     likes: "100〜280"),
    RankInfo(level: 2,  name: "クラスの人気者",           followers: "100〜499",       replies: "4〜7",   haters: "なし",     likes: "270〜770"),
    RankInfo(level: 3,  name: "プチ・インフルエンサー",    followers: "500〜1,999",     replies: "4〜7",   haters: "なし",     likes: "510〜1,470"),
    RankInfo(level: 4,  name: "マイクロ・インフルエンサー", followers: "2,000〜9,999",   replies: "5〜8",   haters: "最大1",    likes: "1,500〜3,990"),
    RankInfo(level: 5,  name: "ネットのカリスマ",          followers: "10,000〜49,999", replies: "5〜9",   haters: "最大1",    likes: "3,600〜10,150"),
    RankInfo(level: 6,  name: "オピニオンリーダー",        followers: "50,000〜199,999", replies: "7〜10",  haters: "最大1",    likes: "10,500〜28,000"),
    RankInfo(level: 7,  name: "時代の寵児",               followers: "200,000〜999,999", replies: "7〜12", haters: "最大2",    likes: "45,000〜119,000"),
    RankInfo(level: 8,  name: "宗派の祖",                 followers: "1,000,000〜4,999,999", replies: "8〜13", haters: "最大2", likes: "114,000〜294,000"),
    RankInfo(level: 9,  name: "預言者",                   followers: "5,000,000〜19,999,999", replies: "9〜14", haters: "最大2", likes: "270,000〜770,000"),
    RankInfo(level: 10, name: "デジタル・ゴッド",          followers: "20,000,000〜",   replies: "10〜16", haters: "最大3",    likes: "450,000〜2,100,000"),
]

struct RankGuideSection: View {
    let currentRank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ランク一覧")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)

            ForEach(rankData, id: \.level) { info in
                let isCurrent = info.level == currentRank
                let isNext = info.level == currentRank + 1
                let isPast = info.level < currentRank
                let isHidden = info.level > currentRank + 1

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Lv.\(info.level)")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(isCurrent ? Theme.hotPink : (isNext ? Theme.cyan : (isPast ? Theme.cyan : .gray.opacity(0.3))))
                        Text(isHidden ? "？？？" : info.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isCurrent ? .white : (isNext ? .white.opacity(0.8) : (isPast ? .white.opacity(0.8) : .gray.opacity(0.3))))
                        Spacer()
                        if isCurrent {
                            Text("NOW")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.hotPink)
                                .cornerRadius(6)
                        } else if isNext {
                            Text("NEXT")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(Theme.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.cyan.opacity(0.15))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cyan.opacity(0.3), lineWidth: 1))
                        }
                    }

                    HStack(spacing: 16) {
                        RankDetailLabel(icon: "person.2.fill", text: isHidden ? "???" : info.followers, dimmed: isHidden)
                        RankDetailLabel(icon: "bubble.left.fill", text: isHidden ? "???" : info.replies, dimmed: isHidden)
                        RankDetailLabel(icon: "heart.fill", text: isHidden ? "???" : info.likes, dimmed: isHidden)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(isHidden ? .gray.opacity(0.2) : (info.level >= 4 ? .orange.opacity(0.7) : .gray.opacity(0.3)))
                        Text(isHidden ? "アンチ: ???" : "アンチ: \(info.haters)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isHidden ? .gray.opacity(0.2) : .gray.opacity(0.7))
                    }
                }
                .padding(16)
                .background(
                    isCurrent
                        ? Theme.hotPink.opacity(0.08)
                        : (isNext ? Theme.cyan.opacity(0.04) : Color.white.opacity(isHidden ? 0.008 : 0.03))
                )
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCurrent ? Theme.hotPink.opacity(0.3) : (isNext ? Theme.cyan.opacity(0.15) : Color.clear), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

struct RankDetailLabel: View {
    let icon: String
    let text: String
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(dimmed ? .gray.opacity(0.3) : Theme.cyan.opacity(0.7))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(dimmed ? .gray.opacity(0.3) : .white.opacity(0.6))
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
    @State private var showTerms = false
    @State private var showPrivacy = false
    
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
                    
                    Text("ID: \(appState.userId)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                    
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

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 24)

                VStack(alignment: .leading, spacing: 16) {
                    Text("LEGAL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(2)

                    Button(action: { showTerms = true }) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.gray)
                            Text("利用規約")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }

                    Button(action: { showPrivacy = true }) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.gray)
                            Text("プライバシーポリシー")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 40)
        }
        .refreshable {
            appState.fetchUser()
        }
        .sheet(isPresented: $showTerms) { LegalTextView(title: "利用規約", text: termsOfServiceText) }
        .sheet(isPresented: $showPrivacy) { LegalTextView(title: "プライバシーポリシー", text: privacyPolicyText) }
    }
}

struct LegalTextView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(6)
                    .padding(24)
            }
            .background(Theme.bgDeepBlack.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Theme.hotPink)
                }
            }
        }
    }
}

private let termsOfServiceText = """
ZEN-KOTEI 利用規約

最終更新日: 2026年3月28日

第1条（適用）
本規約は、ZEN-KOTEI（以下「本アプリ」）の利用に関する条件を定めるものです。ユーザーは、本アプリを利用することにより、本規約に同意したものとみなされます。

第2条（サービスの内容）
本アプリは、ユーザーが投稿したテキストに対してAI（人工知能）が仮想的なフォロワーの返信を生成するエンターテインメントアプリです。
・表示されるフォロワー、いいね数、返信はすべてAIによる架空のものであり、実在の人物・団体とは一切関係ありません。
・本アプリ内での数値（フォロワー数、いいね数等）は本アプリ内でのみ有効であり、現実のSNSとは無関係です。

第3条（禁止事項）
ユーザーは、以下の行為を行ってはなりません。
1. 個人情報（本名、住所、電話番号、メールアドレス等）を投稿する行為
2. 第三者の権利を侵害する内容を投稿する行為
3. 違法行為、公序良俗に反する内容を投稿する行為
4. 本アプリのサーバーやネットワークに過度な負荷をかける行為
5. 本アプリの運営を妨害する行為

第4条（知的財産権）
本アプリに関するすべての知的財産権は、運営者に帰属します。AIが生成した返信の著作権についても、ユーザーに帰属するものではありません。

第5条（免責事項）
1. 運営者は、本アプリの提供の中断、停止、終了、利用不能について、いかなる責任も負いません。
2. AIが生成する返信の内容について、運営者は一切の責任を負いません。
3. 本アプリの利用により生じた損害について、運営者は一切の責任を負いません。

第6条（サービスの変更・終了）
運営者は、事前の通知なく、本アプリの内容を変更し、または提供を終了することができるものとします。

第7条（規約の変更）
運営者は、必要に応じて本規約を変更できるものとします。変更後の規約は、本アプリ内に掲示した時点で効力を生じます。
"""

private let privacyPolicyText = """
ZEN-KOTEI プライバシーポリシー

最終更新日: 2026年3月28日

1. はじめに
ZEN-KOTEI（以下「本アプリ」）は、ユーザーのプライバシーを尊重し、個人情報の保護に努めます。本ポリシーでは、本アプリが取り扱う情報について説明します。

2. 収集する情報
本アプリでは、以下の情報を取り扱います。

【自動的に生成・保存される情報】
・ユーザーID（アプリ初回起動時に端末上で自動生成されるランダムなUUID）
・アプリ内の進行データ（フォロワー数、投稿数、ランク、オンボーディング完了フラグ）

【ユーザーが入力する情報】
・投稿テキスト（AI返信生成のためサーバーに送信されます）
・プロフィール情報（ユーザー名、自己紹介文、アバター画像 — 端末内にのみ保存）

3. 情報の利用目的
・投稿テキスト: AI返信を生成するために、OpenAI社のAPIへ送信されます。送信されたテキストはAI処理後、本アプリのサーバーには保存されません。
・ユーザーID・進行データ: アプリの状態を管理し、端末間でのデータ同期に利用します。

4. 第三者への提供
・投稿テキストは、AI返信生成の目的でOpenAI社のAPIに送信されます。OpenAI社のデータ取り扱いについては、同社のプライバシーポリシーをご確認ください。
・上記を除き、ユーザーの情報を第三者に提供・販売することはありません。

5. データの保存
・投稿データ（テキスト・返信）は端末内にのみ保存され、直近5件を超えるデータは自動的に削除されます。
・サーバー（Supabase）には、ユーザーID・フォロワー数・投稿数・オンボーディングフラグのみが保存されます。

6. データの削除
・アプリをアンインストールすることで、端末内のすべてのデータが削除されます。
・サーバー上のデータの削除を希望される場合は、運営者までご連絡ください。

7. お子様のプライバシー
本アプリは、13歳未満のお子様を対象としていません。

8. ポリシーの変更
本ポリシーは、必要に応じて改定されることがあります。重要な変更がある場合は、アプリ内で通知します。

9. お問い合わせ
本ポリシーに関するご質問は、アプリの運営者までお問い合わせください。
"""
