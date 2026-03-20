# 全肯定SNSシミュレーター（ZEN-KOTEI）要件定義書

本ディレクトリには「全肯定SNSシミュレーター（ZEN-KOTEI）」の要件定義ドキュメントを格納しています。

## ドキュメント構成

| ファイル名 | 説明 |
| :--- | :--- |
| [01_Overview_and_UX.md](./01_Overview_and_UX.md) | プロジェクトの概要と目指すユーザー体験(UX) |
| [02_Functional_Requirements.md](./02_Functional_Requirements.md) | 投稿・ホームなど「画面別の機能要件」や、コアとなる「AIリプライ一括生成・アンチ防衛（ドラマ）シナリオ」 |
| [04_UI_UX_Design.md](./04_UI_UX_Design.md) | カラーパレット、スタイリング、アニメーションなどのデザイン要件 |
| [05_Architecture_and_TechStack.md](./05_Architecture_and_TechStack.md) | 言語、インフラなどの技術スタックと、パフォーマンス等の非機能要件 |

※ アプリはiPhone用 (iOSネイティブ) としてSwiftUIを用いて開発されます。AI連携・バックエンドとしてはPython / Supabaseなどを活用します。
