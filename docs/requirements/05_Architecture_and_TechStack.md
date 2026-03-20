# 6. 技術スタック (Tech Stack) と非機能要件

## 6.1 非機能要件
- **パフォーマンス**: 大量のリプライが生成されてもスムーズにスクロールできるよう、メモリリークを防ぐクリーンアップ処理（Timerの適切な破棄やTaskのキャンセル等）を徹底する。
- **レスポンシブ**: iPhone 13/14 等の標準的なモバイル解像度（390px〜）に最適化。

## 6.2 技術スタック

### フロントエンド (iOSアプリ)
- **言語/フレームワーク**: Swift (SwiftUI)
  - 宣言的UIによる高速なプロトタイピングと、iOS標準の滑らかなアニメーション（Spring Animation等）の実装。
- **非同期処理**: Swift Concurrency (`async/await`)
  - SupabaseやバックエンドAPIとのセキュアかつ効率的な通信。
- **ローカルストレージ**: SwiftData または UserDefaults
  - アプリ設定や軽量なユーザーキャッシュの保持。

### バックエンド (AI・ロジック)
- **言語**: Python (FastAPI / Flask)
  - 役割: OpenAI APIとの連携ハブ。リプライのコンテキスト解析、感情分析、ドラマシナリオの動的生成ロジックを担当。
- **AIエンジン**: OpenAI API (GPT-4o / GPT-4o-mini)
  - ユーザーの投稿内容に基づき、各AIキャラクターの個性を反映した高精度な肯定・擁護コメントを生成する。
  - **APIコール最適化**: Structured Outputs (JSON Schema) などを活用し、1回のAPIリクエストで「全リプライ分（称賛・アンチ・防衛）」をJSON配列として一括返却させる。
- **ホスティング**: Supabase Edge Functions または AWS Lambda / Google Cloud Functions (Pythonランタイム)

### インフラストラクチャ・データベース
- **プラットフォーム**: Supabase
- **Database**: PostgreSQL
  - **データの一元管理**: データ関連（投稿、生成されたJSONリプライデータ、いいね数、フォロワー数、ユーザープロファイルなど）は基本的に全てデータベースで管理する。
- **Authentication**: Supabase Auth
  - Apple ID連携等による迅速なユーザーサインイン。
- **Realtime**: Supabase Realtime
  - (必要に応じて) リプライのリアルタイムプッシュ等に活用する。
- **Storage**: Supabase Storage
  - ユーザーが投稿した画像（ノートの画像等）のホスティング。
