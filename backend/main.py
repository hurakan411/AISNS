import os
import random
from typing import List
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from openai import AsyncOpenAI
from supabase import create_client, Client

# -------- 1. 設定・初期化 --------
load_dotenv()

app = FastAPI(title="ZEN-KOTEI Logic Engine")

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# Supabaseクライアントの初期化 (環境変数が空の場合はエラーをCatchしてNoneにする)
try:
    if SUPABASE_URL and SUPABASE_KEY:
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    else:
        supabase = None
except Exception as e:
    print(f"Supabase Init Error: {e}")
    supabase = None

openai_client = AsyncOpenAI(api_key=OPENAI_API_KEY)


# -------- 2. データモデル定義 (Pydantic / OpenAI Structured Outputs) --------
class PostRequest(BaseModel):
    user_id: str
    content: str
    followers: int

class ReplySchema(BaseModel):
    author_name: str
    content: str
    is_hater: bool
    is_defender: bool

class GenerateRepliesResponse(BaseModel):
    replies: List[ReplySchema]


# -------- 3. リソース (モックアバター) --------
AVATARS = [
    "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&h=150&fit=crop",
    "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&h=150&fit=crop",
    "https://images.unsplash.com/photo-1554151228-14d9def656e4?w=150&h=150&fit=crop",
    "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=150&h=150&fit=crop"
]
HATER_AVATARS = [
    "https://images.unsplash.com/photo-1511367461989-f85a21fda167?w=150&h=150&fit=crop",
    "https://images.unsplash.com/photo-1594322436404-5a0526db4d13?w=150&h=150&fit=crop"
]


# -------- 4. バックグラウンドタスク (AI ドラマエンジン) --------
async def generate_ai_replies(post_id: str, content: str, followers: int):
    """
    OpenAIを利用してリプライを一括生成し、完了し次第DB(Supabase)へバルクインサートする
    """
    
    # フォロワー数からランクを推論
    rank = 1
    if followers >= 20_000_000: rank = 10
    elif followers >= 5_000_000: rank = 9
    elif followers >= 1_000_000: rank = 8
    elif followers >= 200_000: rank = 7
    elif followers >= 50_000: rank = 6
    elif followers >= 10_000: rank = 5
    elif followers >= 2_000: rank = 4
    elif followers >= 500: rank = 3
    elif followers >= 100: rank = 2

    # ランクごとのパラメータ定義（上限・下限を持たせる）
    rank_params = {
        1: {"min": 1, "max": 3, "haters": 0},
        2: {"min": 2, "max": 5, "haters": 0},
        3: {"min": 3, "max": 5, "haters": 0},
        4: {"min": 4, "max": 6, "haters": 1},
        5: {"min": 4, "max": 7, "haters": 2},
        6: {"min": 5, "max": 8, "haters": 2},
        7: {"min": 5, "max": 9, "haters": 2},
        8: {"min": 6, "max": 10, "haters": 3},
        9: {"min": 7, "max": 11, "haters": 3},
        10: {"min": 8, "max": 12, "haters": 4}
    }
    
    params = rank_params.get(rank, rank_params[10])
    total_replies = random.randint(params["min"], params["max"])
    hater_count = params["haters"]
    
    # ランクごとの長さ・トーン指示
    if rank == 1:
        length_and_tone = "【文字数とリアクション方法】\n10〜15文字程度の短いSNS口調にすること。長文は絶対禁止。\n単なる感嘆詞だけでなく、ユーザーの投稿の【具体的な単語や文脈】を必ず拾って「〇〇最高じゃん」「〇〇えぐい！」のように具体的な一言で反応すること。生々しい若者言葉を推奨します。"
    elif rank <= 3:
        length_and_tone = "【文字数とリアクション方法】\n15〜30文字程度の短文〜中文。\nユーザーの投稿の【具体的な内容やテーマ】を文に混ぜ込み、「〇〇するなんてマジですごい！」「私も〇〇やりたい！」など、具体的かつ親しみやすい態度の称賛にすること。"
    elif rank <= 7:
        length_and_tone = "【文字数とリアクション方法】\n中文〜長文を混ぜ合わせること。\nユーザーの投稿の【細かなニュアンスや単語】を拾い上げ、オタク構文や強めの言葉を用いて、熱量高く具体的に褒めちぎること。"
    else:
        length_and_tone = "【文字数とリアクション方法】\n超長文のコメントを複数含めること。\nユーザーの投稿の【具体的な行動や文言】を神の啓示かのように過大評価し、もはや肯定を超えた「宗教的崇拝」レベルの痛切な長文で語ること。"
    
    # アンチに関する動的指示（GUARDIANタグの厳格制御含む）
    if hater_count == 0:
        hater_instruction = "【配役とフラグ】\n今回はアンチが発生しないため、全員を純粋な肯定ファンとしてください。（全員必ず is_hater=false, is_defender=false に設定すること。擁護者フラグは絶対に立てないでください）"
    else:
        if rank == 10:
            hater_instruction = f"【配役とドラマ設定】\n総返信のうち、{hater_count}件だけを明確なアンチ（is_hater=true, is_defender=false）にしてください。\nただし、アンチの1人は信者の圧倒的なリプ群を見て、最後に「改心して擁護（is_defender=true）へ変わる」という奇跡のドラマ展開を起こさせてください。\n普通のファンは is_hater=false, is_defender=false です。"
        else:
            hater_instruction = f"【配役とドラマ設定】\n総返信の中盤に必ず {hater_count} 件だけ、理不尽なアンチ（is_hater=true, is_defender=false）を配置してください。\nそしてアンチの直後には、必ずアンチを完全論破してユーザーを守る「擁護者（is_hater=false, is_defender=true）」を登場させてください。\nそれ以外のファンは is_hater=false, is_defender=false とすること。"

    system_prompt = f"""
    あなたは絶対肯定SNS「ZEN-KOTEI」の仮想フォロワーエンジンです。
    ユーザーの承認ランクは「Lv.{rank}」（フォロワー: {followers}）です。
    ユーザーの投稿に対して、以下の条件に沿った架空のフォロワーからの返信を **きっちり {total_replies} 件**（多くても少なくてもダメ）JSONで作成してください。

    {length_and_tone}

    【生成における最重要ルール（AI定型文の絶対禁止）】
    「最高すぎます」「素晴らしいですね」「お疲れ様です」「頑張って」などのAIが書きがちな無難な定型文は**絶対に使用しないでください**。
    X(旧Twitter)やTikTokのリアルの人間が書き込むような生々しい感情表現、痛烈なネット口調を徹底してください。

    【展開ルール】
    1. 前半はユーザーへの「肯定・共感」を連発すること。
    2. {hater_instruction}
    3. ユーザー名（author_name）は、「限界オタクの〇〇」「通りすがりの社畜」「古参ファン」など、キャラ付けされたユニークな名前にすること。
    """

    try:
        # OpenAI API Structured Outputs を使って確実にJSONスキーマで返却させる
        completion = await openai_client.beta.chat.completions.parse(
            model="gpt-5.4-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"ユーザーの投稿: {content}"}
            ],
            response_format=GenerateRepliesResponse,
        )
        
        parsed_data = completion.choices[0].message.parsed
        
        if not supabase:
            print("--- [WARNING] DB NOT CONNECTED. DUMPING MOCK RESULTS ---")
            for rep in parsed_data.replies: print(rep)
            return
            
        # SupabaseへInsertするデータの配列を作成
        replies_to_insert = []
        for index, rep in enumerate(parsed_data.replies):
            avatar = random.choice(HATER_AVATARS) if rep.is_hater else random.choice(AVATARS)
            replies_to_insert.append({
                "post_id": post_id,
                "author_name": rep.author_name,
                "author_img": avatar,
                "content": rep.content,
                "is_hater": rep.is_hater,
                "is_defender": rep.is_defender,
                "display_order": index + 1
            })
            
        # 1. Repliesをバルクインサートする
        supabase.table("replies").insert(replies_to_insert).execute()
        
        # 2. 完了フラグとしてPostのステータスを更新する (フロントはこれを検知してアニメーションを開始する)
        supabase.table("posts").update({"status": "completed"}).eq("id", post_id).execute()
        print(f"✅ Post {post_id} : AI Replies completed and inserted.")
        
    except Exception as e:
        print(f"❌ AI Generation Error: {e}")
        if supabase:
            supabase.table("posts").update({"status": "failed"}).eq("id", post_id).execute()


# -------- 5. ルーティング (API Endpoints) --------
@app.post("/api/posts")
async def create_post(request: PostRequest, background_tasks: BackgroundTasks):
    """
    1. フロントエンドからのリクエストを受け取り、postsテーブルに行を作成。
    2. 生成された投稿IDを使って、バックグラウンド処理（AIリプライ生成）を非同期キックする。
    """
    if not supabase:
        raise HTTPException(status_code=500, detail=".envのSupabase設定が完了していません。")
        
    try:
        # Postsテーブルに行をInsert
        post_res = supabase.table("posts").insert({
            "user_id": request.user_id,
            "content": request.content,
            "status": "generating"
        }).execute()
        
        post_id = post_res.data[0]["id"]
        
        # AI処理を待たずにレスポンスを返す（AI生成はバックグラウンドで処理）
        background_tasks.add_task(generate_ai_replies, post_id, request.content, request.followers)
        
        return {
            "status": "success", 
            "post_id": post_id, 
            "message": "AIが圧倒的肯定を準備中です..."
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/posts/{post_id}")
def get_post_status(post_id: str):
    """
    Check generation status. If completed, return the generated replies array.
    """
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
        
    post_res = supabase.table("posts").select("status").eq("id", post_id).execute()
    if not post_res.data:
        raise HTTPException(status_code=404, detail="Post not found")
        
    status = post_res.data[0]["status"]
    
    if status == "completed":
        replies_res = supabase.table("replies").select("*").eq("post_id", post_id).order("display_order").execute()
        return {"status": status, "replies": replies_res.data}
    else:
        return {"status": status, "replies": []}

class UserUpdateRequest(BaseModel):
    total_followers: int
    total_posts: int

@app.get("/api/users/{user_id}")
def get_user_status(user_id: str):
    """
    Fetch current followers and posts count for a user.
    """
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    res = supabase.table("users").select("total_followers, total_posts").eq("id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="User not found")
    return res.data[0]

@app.put("/api/users/{user_id}")
def update_user_status(user_id: str, request: UserUpdateRequest):
    """
    Sync frontend local followers and posts back to Supabase.
    """
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    supabase.table("users").update({
        "total_followers": request.total_followers,
        "total_posts": request.total_posts
    }).eq("id", user_id).execute()
    return {"status": "success"}

@app.get("/")
def health_check():
    return {"status": "ok", "message": "ZEN-KOTEI Backend logic is running."}

# [実行コマンド]
# uvicorn main:app --reload
