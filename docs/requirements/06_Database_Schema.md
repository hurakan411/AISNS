# 6. データベース設計 (Supabase / PostgreSQL)

「UPME! | AI SNS」アプリは、**Supabase（PostgreSQL）** をユーザー管理専用のデータストアとして利用します。投稿データ・リプライデータはDBに保存せず、フロントエンドのローカルストレージで管理します。

## 6.1 テーブル構成

本システムは **`users` テーブルのみ** で構成されます。

> **設計方針**: 投稿（posts）と返信（replies）はユーザー間での共有が不要なため、DB保存のメリットが薄い。APIレスポンスとして直接返却し、ローカルで最大5件のみ保持する軽量設計を採用。

---

## 6.2 テーブル定義

### `users` テーブル
ユーザーの基本情報や、アプリのコア進行度である「フォロワー数」「総投稿数」「オンボーディング完了状態」を記録します。

| カラム名 | データ型 | 制約 / 初期値 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key | アプリ初回起動時に端末上で自動生成されるUUID |
| `display_name` | `TEXT` | `NOT NULL`, Default: `みずき（あなた）` | アプリ上で表示されるユーザー名 |
| `avatar_url` | `TEXT` | `NULL`可 | プロフィール画像のURL |
| `total_posts` | `INT` | `DEFAULT 0` | 累積投稿数 |
| `total_followers` | `INT` | `DEFAULT 0` | 累計フォロワー数（ランクに直結） |
| `has_completed_onboarding` | `BOOLEAN` | `DEFAULT false` | オンボーディング完了フラグ |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | アカウント作成日時 |

> **設計ポイント**:
> - 「承認ランク」は `total_followers` からクライアント側やAPI側で動的に計算するため、DBカラムとしては持たない。
> - `has_completed_onboarding` はDBをSource of Truthとし、アプリ起動時にDBから取得して同期。UserDefaultsにもキャッシュするが、DBの値を優先する。
> - `display_name` と `avatar_url` はDB上に存在するが、現在の実装ではローカル（UserDefaults/ファイル）で管理しており、DBとの同期は行っていない。

### 廃止済みテーブル
以下のテーブルは設計変更により廃止されました。既存環境では `DROP TABLE` で削除済み。

- **`posts` テーブル**: 投稿データはローカルJSONファイルで管理するため不要。
- **`replies` テーブル**: リプライはAPIレスポンスとして直接返却し、ローカルの投稿データに含めて保存するため不要。

---

## 6.3 データフロー構成（フロントエンド ⇆ API ⇆ DB）

```
[投稿フロー]
1. SwiftUI → POST /api/posts (投稿テキスト + フォロワー数 + 設定)
2. FastAPI → OpenAI API (リプライ一括生成)
3. FastAPI → SwiftUI (レスポンスボディでリプライ配列を返却)
4. SwiftUI → ローカルJSONファイルに保存 (最大5件)
5. SwiftUI → リプライを5〜15秒間隔で順次表示 + いいね/フォロワー漸増
6. SwiftUI → PUT /api/users/{id} (フォロワー数・投稿数をDBに同期)

[初回起動フロー]
1. SwiftUI → POST /api/users (UUID送信、upsert)
2. API → has_completed_onboarding を返却
3. false の場合 → オンボーディング開始
4. 完了時 → PUT /api/users/{id} (has_completed_onboarding=true)

[アプリ起動フロー]
1. SwiftUI → GET /api/users/{id} (フォロワー数・投稿数・オンボーディングフラグ取得)
2. SwiftUI → ローカルJSONから投稿データ読み込み
```

## 6.4 ローカルストレージ設計

| データ | 保存先 | 保持上限 | 備考 |
| :--- | :--- | :--- | :--- |
| 投稿＋返信 | `Documents/posts_v1.json` | 5件 | 超過分は自動削除 |
| ユーザーアバター | `Documents/user_avatar.dat` | 1件 | バイナリ画像データ |
| ユーザー名 | `UserDefaults` | - | `userName` キー |
| 自己紹介文 | `UserDefaults` | - | `userBio` キー |
| ユーザーID | `UserDefaults` | - | `userId` キー (UUID) |
| アンチ設定 | `UserDefaults` | - | `isHaterEnabled` キー |
| オンボーディング | `UserDefaults` + DB | - | DBがSource of Truth |
