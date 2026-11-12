# 継続率分析用イベントの定義

`post_flow_id` は端末で生成した投稿UUID。オンボ投稿と通常投稿を区別し、AI要求・受信・表示・閲覧・ユーザー返信を同じIDで結ぶ。投稿本文・画像・プロフィール名は計測に含めない。

## 投稿回数

`post_created` の投稿回数は、AI生成完了時のDB同期とは独立して投稿時に端末へ保存する。

- `post_number_after_onboarding`: オンボ投稿を除く累計投稿番号。初回通常投稿は1。
- `is_first_post_after_onboarding`: 上記番号が1のときだけtrue。
- `tracked_post_number`: この計測の導入後、端末で観測した通常投稿の番号。
- `post_number_is_known`: 過去の投稿数を確定できているか。

新規ユーザーはオンボ完了時に通常投稿0件から開始する。既存ユーザーは有効なユーザーAPIの応答から初期値を引き継ぐ。履歴を確認する前に投稿した既存ユーザーは、過去の正確な番号を後から推測せず、`post_number_after_onboarding` と `is_first_post_after_onboarding` を省略する。`tracked_post_number` はこの場合も利用できる。

## AI返信の閲覧

`ai_replies_displayed` は返信の追加演出が完了したこと、`ai_replies_viewed` は少なくとも1件のAI返信が画面内に現れたことを表す。イベントの発生順はこの順とは限らない。

閲覧はアプリがアクティブで、返信と表示領域がともに正のサイズを持ち、縦横それぞれ返信の25%以上（最大60pt）が画面内に入ったときに記録する。0サイズ・不正な矩形・画面外は対象外。文章を読んだこと自体を保証するイベントではない。

閲覧済みIDはユーザー別に端末へ保存し、アプリ再起動後やオンボからホームへの移動でも重複を抑える。保存対象は直近512投稿（アプリの投稿保存は直近5件）。SDK初期化前には閲覧済みとして保存しない。

## オンボの取得失敗

成功と失敗は `Result` で分け、返信0件も失敗として扱う。成功結果だけをキャッシュし、取得中のプリフェッチを二重リクエストしない。失敗時には再試行かオンボ完了を選べる。`onboarding_completed.ai_reply_status` は `received` / `failed` / `pending`。

## ローカル回帰確認

```sh
xcrun swiftc -parse-as-library AppCode/Analytics.swift AppCode/UserProgressSync.swift AppCode/AppState.swift scripts/check_engagement_metrics.swift -o /private/tmp/upme-engagement-checks
/private/tmp/upme-engagement-checks
```

40件の確認。別プロセス間の保存、古いDB値を受け取った後の投稿番号、矩形の境界、プリフェッチ失敗と再試行、返信0件、ネットワークの再試行上限、オンボを終了した後の遅延応答、重複抑制用のAI返信履歴の抽出・件数/文字数制限・ユーザー返信の除外を対象とする。通信はすべて模擬し、アプリの保存ファイルやPostHogプロジェクトには接続しない。保存テストにはテスト専用のUserDefaults領域への書き込みが必要。
