# 6. 技術スタック (Tech Stack) と非機能要件

## 6.1 非機能要件
- **パフォーマンス**: 大量のリプライが生成されてもスムーズにスクロールできるよう、メモリリークを防ぐクリーンアップ処理（Timerの適切な破棄やTaskのキャンセル等）を徹底する。
- **レスポンシブ**: iPhone 13/14/15/16 等の標準的なモバイル解像度に最適化。
- **データ軽量化**: ローカルストレージは直近5件の投稿のみ保持。古いデータは自動削除し、端末容量を圧迫しない。
- **APIタイムアウト**: AI返信生成リクエストのタイムアウトは120秒に設定。

## 6.2 技術スタック

### フロントエンド (iOSアプリ)
- **言語/フレームワーク**: Swift (SwiftUI)
  - 宣言的UIによる高速なプロトタイピングと、iOS標準の滑らかなアニメーション（Spring Animation等）の実装。
- **非同期処理**: Swift Concurrency (`async/await`) + Combine
  - バックエンドAPIとのHTTP通信、Timer（バズ演出・リプライ遅延表示）の制御。
- **ローカルストレージ**: JSONファイル + UserDefaults
  - 投稿データ（最大5件）はJSONファイルとしてDocumentsディレクトリに保存。
  - ユーザー設定（ユーザー名、Bio、アンチON/OFF、ユーザーID等）はUserDefaultsに保存。
  - アバター画像はDocumentsディレクトリにバイナリファイルとして保存。
- **アニメーションライブラリ**: Lottie (Swift Package Manager, v4.4.0+)
  - JSON形式のアニメーションファイルを `UIViewRepresentable` ラッパー経由でSwiftUIに統合。
  - 使用アニメーション: 「Loading Pink Dots」（ローディング表示）、「Technology isometric AI robot brain」（プロフィールヘッダー装飾）。

### バックエンド (AI・ロジック)
- **言語/フレームワーク**: Python (FastAPI)
  - 役割: OpenAI APIとの連携ハブ。リプライのコンテキスト解析、ドラマシナリオの動的生成ロジックを担当。
- **AIエンジン**: OpenAI API (GPT-4o / GPT-4o-mini)
  - ユーザーの投稿内容に基づき、各AIキャラクターの個性を反映した高精度な肯定・擁護コメントを生成する。
  - **Structured Outputs**: Pydanticモデル（`GenerateRepliesResponse`）を使用し、確実にJSONスキーマで返却。1回のAPIリクエストで全リプライ分を一括生成。
  - **画像認識**: `image_base64` をVision形式ペイロードとして送信し、画像付き投稿にも対応。
- **データフロー**: 同期レスポンス方式
  - `POST /api/posts` でAIリプライを生成し、レスポンスボディで直接返却。DB中間保存やバックグラウンドタスクは使用しない。

### インフラストラクチャ・データベース
- **プラットフォーム**: Supabase
- **Database**: PostgreSQL
  - **usersテーブルのみ**: ユーザーID、フォロワー数、投稿数、オンボーディング完了フラグを管理。投稿データ・リプライデータはDBに保存しない（ローカル管理）。
- **Authentication**: アプリ初回起動時に端末上でUUIDを自動生成し、Supabase usersテーブルにupsert。Apple ID等の外部認証は未実装。

### API エンドポイント一覧
| メソッド | パス | 概要 |
| :--- | :--- | :--- |
| `POST` | `/api/posts` | AI返信を生成し、レスポンスで直接返却 |
| `POST` | `/api/users` | 初回ユーザー登録（upsert） |
| `GET` | `/api/users/{user_id}` | ユーザー情報取得（フォロワー数・投稿数・オンボーディングフラグ） |
| `PUT` | `/api/users/{user_id}` | ユーザー情報更新（フォロワー数・投稿数の同期） |
| `GET` | `/` | ヘルスチェック |
