import os
import time
import httpx
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
except Exception:
    supabase = None

def run_test():
    print("------- バックエンド（AI & DB）動作テスト -------")
    
    if not supabase:
        print("❌ Supabaseクライアントの初期化に失敗しました。.envの値を確認してください。")
        return

    # 1. テスト用ユーザーの作成 (UUIDが必要)
    test_user_id = "11111111-1111-1111-1111-111111111111"
    try:
        # すでに存在するか確認し、なければ作成
        res = supabase.table("users").select("id").eq("id", test_user_id).execute()
        if not res.data:
            print("👤 テスト用ユーザーを作成中...")
            supabase.table("users").insert({
                "id": test_user_id,
                "display_name": "みずき（テスト）",
                "total_posts": 0,
                "total_followers": 2500 # ランク4相当に設定（アンチコメントが出るかテストするため）
            }).execute()
        else:
            print("👤 テスト用ユーザー確認OK")
    except Exception as e:
        print(f"❌ ユーザー作成エラー: {e}")
        print("💡 Supabaseが未設定か、またはテーブルが存在しません。")
        return

    # 2. FastAPIへPOSTリクエスト送信
    print("\n🚀 FastAPIへ投稿リクエストを送信しています...")
    try:
        response = httpx.post(
            "http://127.0.0.1:8000/api/posts",
            json={
                "user_id": test_user_id,
                "content": "テスト投稿：今日は一日中カフェでプログラミングして最高の気分！",
                "followers": 2500
            },
            timeout=10.0
        )
        print(f"レスポンス: {response.json()}")
        post_id = response.json().get("post_id")
    except Exception as e:
        print(f"❌ FastAPIリクエストエラー: {e}")
        print("💡 uvicornサーバーが起動していない可能性があります。")
        return

    # 3. AI生成を待つ (数秒)
    print("\n⏳ AIが肯定・アンチ・擁護ドラマを構築するのを待っています...")
    time.sleep(12)  # gpt-4o なので通常は数秒で返る
    
    # 4. 結果をSupabaseから確認
    print("\n🔍 Supabaseから生成されたリプライを確認します...")
    try:
        post_check = supabase.table("posts").select("status").eq("id", post_id).execute()
        status = post_check.data[0]["status"] if post_check.data else "不明"
        print(f"投稿ステータス: {status}")
        
        replies_check = supabase.table("replies").select("*").eq("post_id", post_id).order("display_order").execute()
        if replies_check.data:
            print(f"\n✨ 生成された架空フォロワーからのコメント ({len(replies_check.data)}件):")
            for rep in replies_check.data:
                icon = "🤬[アンチ]" if rep['is_hater'] else ("🛡️[擁護者]" if rep['is_defender'] else "💬[ファン]")
                print(f" {icon} {rep['author_name']} : {rep['content']}")
        else:
            print("⚠️ リプライがまだ生成されていないか、エラーが発生しました。")
    except Exception as e:
        print(f"❌ データ取得エラー: {e}")

if __name__ == "__main__":
    run_test()
