# 6. データベース設計 (Supabase / PostgreSQL)

「ZEN-KOTEI」アプリは、**中央集権的なDB（Supabase）** を利用してユーザーのプロフィール、ステータス、投稿データ、およびAIによって生成された擬似リプライを管理します。

## 6.1 ER図（エンティティ関係）概要
本システムは非常にシンプルでスケーラブルな3つの主軸テーブルで構成されます。

1. **`users`** (ユーザー情報とステータス)
2. **`posts`** (ユーザーの投稿)
3. **`replies`** (投稿に紐づくAI生成リプライ)

---

## 6.2 テーブル定義

### 1. `users` テーブル
ユーザーの基本情報や、アプリのコア進行度である「フォロワー数」「総投稿数」を記録します。認証(Auth)テーブルと紐づきます。

| カラム名 | データ型 | 制約 / 初期値 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key | Supabase Authの `auth.users.id` に依存 |
| `display_name` | `TEXT` | `NOT NULL`, Default: `みずき（あなた）` | アプリ上で表示されるユーザー名 |
| `avatar_url` | `TEXT` | `NULL`可 | プロフィール画像のURL |
| `total_posts` | `INT` | `DEFAULT 0` | 累積投稿数 |
| `total_followers` | `INT` | `DEFAULT 0` | 累計フォロワー数（ランクに直結） |
| `created_at` | `TIMESTAMPTZ`| `DEFAULT now()` | アカウント作成日時 |

> **💡 設計ポイント**: 
> 「承認ランク」は `total_followers` からクライアント側やAPI側で動的に計算可能なため、DBで直接マスタデータとして持たず、バグやデータの非同期を防ぎます。

### 2. `posts` テーブル
「シングルポスト／タイムライン」の基盤となるユーザーの投稿データです。

| カラム名 | データ型 | 制約 / 初期値 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key, `DEFAULT uuid_generate_v4()` | 投稿の一意のID |
| `user_id` | `UUID` | Foreign Key (`users.id`), `NOT NULL` | 投稿者のID |
| `content` | `TEXT` | `NOT NULL` | 投稿のテキスト本文 |
| `image_url` | `TEXT` | `NULL`可 | 添付画像（Supabase StorageのURLなど） |
| `likes_count`| `INT` | `DEFAULT 0` | 最終的に獲得した「いいね」の数 |
| `status` | `TEXT` | `DEFAULT 'generating'` | AI生成ステータス。`generating`, `completed`, `failed`。このステータスでフロントの表示制御を行う |
| `created_at` | `TIMESTAMPTZ`| `DEFAULT now()` | 投稿日時 |

### 3. `replies` テーブル
OpenAIのAPIによって一括生成され、各 `post` に連なる仮想フォロワーやアンチからのコメント群を保存します。

| カラム名 | データ型 | 制約 / 初期値 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key, `DEFAULT uuid_generate_v4()` | リプライの一意のID |
| `post_id` | `UUID` | Foreign Key (`posts.id`) `ON DELETE CASCADE` | 紐づく投稿のID |
| `author_name`| `TEXT` | `NOT NULL` | AIが生成したリプライ主の名前（例："ひまり🌻", "匿名"など） |
| `author_img` | `TEXT` | `NOT NULL` | アバター画像URL |
| `content` | `TEXT` | `NOT NULL` | リプライ本文 |
| `is_hater` | `BOOLEAN` | `DEFAULT false` | このリプライがアンチ(Hater)からのものかどうか |
| `is_defender`| `BOOLEAN` | `DEFAULT false` | アンチから守護してくれたGuardianからのものかどうか |
| `display_order`| `INT` | `NOT NULL` | アプリ側で遅延表示（1.2秒おき）させる際の並び順 |
| `created_at` | `TIMESTAMPTZ`| `DEFAULT now()` | レコード保存日時 |

---

## 6.3 データフロー構成（フロントエンド ⇆ API ⇆ DB）
1. フロントエンド（SwiftUI）が投稿ボタンを押下し、**バックエンド（Python / FastAPI等）** へリクエストを送信。
2. バックエンドはひとまず `posts` テーブルに行を作成。
3. バックエンドで **OpenAI API** をコールし、投稿文脈と現在のランクに応じたJSONデータ（リプライ群）を一括生成。
4. 生成された配列データを `replies` テーブルに `display_order` を振って一括Insert (バルクインサート)。
5. `posts` テーブルの `status` を `completed` に変更。
6. SwiftUIは DBの Subscribe（リアルタイムリスナー）などを通じてレコードを検知し、アニメーション付きで描写を開始。
