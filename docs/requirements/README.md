# AI SNS「UPME! | AI SNS」要件定義書

本ディレクトリには「UPME! | AI SNS」の要件定義ドキュメントを格納しています。

## ドキュメント構成

| ファイル名 | 説明 |
| :--- | :--- |
| [01_Overview_and_UX.md](./01_Overview_and_UX.md) | プロジェクトの概要と目指すユーザー体験(UX)。オンボーディングの設計思想を含む |
| [02_Functional_Requirements.md](./02_Functional_Requirements.md) | オンボーディング・投稿・ホーム・Stats・Profileなど画面別の機能要件。AIリプライ一括生成・アンチ防衛ドラマシナリオ・承認ランクシステム |
| [04_UI_UX_Design.md](./04_UI_UX_Design.md) | カラーパレット、スタイリング、Lottieアニメーション、ランクガイドUIなどのデザイン要件 |
| [05_Architecture_and_TechStack.md](./05_Architecture_and_TechStack.md) | 技術スタック（Swift/FastAPI/Supabase/OpenAI/Lottie）、APIエンドポイント一覧、非機能要件 |
| [06_Database_Schema.md](./06_Database_Schema.md) | DBスキーマ（usersテーブルのみ）、ローカルストレージ設計、データフロー図 |

## 技術構成サマリ

- **フロントエンド**: Swift (SwiftUI) + Lottie
- **バックエンド**: Python (FastAPI) + OpenAI API (Structured Outputs)
- **データベース**: Supabase (PostgreSQL) — usersテーブルのみ
- **ローカルストレージ**: JSONファイル（投稿5件上限）+ UserDefaults
