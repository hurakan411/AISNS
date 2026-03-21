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
    is_hater_enabled: bool = True

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
async def generate_ai_replies(post_id: str, content: str, followers: int, is_hater_enabled: bool):
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
    hater_count = params["haters"] if is_hater_enabled else 0
    
    # ランクごとの長さ・トーン指示（全ランクで短文〜長文を織り交ぜる）
    if rank == 1:
        length_and_tone = "【文字数とリアクション方法】\n「短文（30字程度）」を大半（9割）とし、ごく稀に「中文（60字）」や「長文（100字）」を織り交ぜてバリエーションを出してください。\n単なる感嘆詞だけでなく、ユーザーの投稿の【具体的な単語や文脈】を拾って「〇〇最高じゃん」「〇〇えぐい！」のように生々しい若者言葉で反応すること。"
    elif rank <= 3:
        length_and_tone = "【文字数とリアクション方法】\n「短文（30字）」と「中文（60字）」を中心にしつつ、一部のファンに「長文（100字）」を織り交ぜてリアル感を出してください。\nユーザーの投稿の【具体的な内容やテーマ】を文に混ぜ込み、「〇〇するなんてマジですごい！」「私も〇〇やりたい！」など親しみやすい称賛を展開すること。"
    elif rank <= 7:
        length_and_tone = "【文字数とリアクション方法】\n「短文（30字）」「中文（60字）」「長文（100字）」をバランスよく（1:1:1程度で）織り交ぜ、多様なファン層を表現してください。\nユーザーの投稿の【細かなニュアンスや単語】を拾い上げ、オタク構文や強めの言葉を用いたリアルで熱量の高いタイムラインを作ること。"
    else:
        length_and_tone = "【文字数とリアクション方法】\n「長文（100字以上）」の信者による重い語りを中心（7割）としつつも、必ず「短文（30字）」や「中文（60字）」も織り交ぜてカオスな宗教的空間を演出すること。\nユーザーの投稿の【具体的な行動や文言】を神の啓示かのように過大評価し、痛切な長文と熱狂的な短文が入り乱れるようにしてください。"
    
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

    【文字数の定義】
    本システムにおける文字数は以下のように定義します。
    ・ 短文: 30字程度
    ・ 中文: 60字程度
    ・ 長文: 100字程度

    {length_and_tone}

    【キャラクターダイバーシティ（多様性）の強制】
    生成される複数の返信は、すべて**全く異なる極端なペルソナ（性格・属性）**を持たせて人間味を持たせてください。以下のような20種類のキャラ属性から被らないようにランダムに選び、全員が似たような構文になることを防ぐこと。また、一部のキャラクターはSNSらしく**絵文字や顔文字（(´；ω；`)など）を積極的に活用**してください。
    1. 限界オタク風（早口、推し文化の語彙、勢いが異常。ｷﾀ━(ﾟ∀ﾟ)━!や( ；∀；)などの古典的な顔文字を使う）
    2. 陽キャ・ギャル風（感嘆詞多め「えぐい」「それな」、語彙力が低いがノリが良い。✨や🥺など絵文字を多用する）
    3. 後方腕組み古参ファン（謎の上から目線で分析するが、実はべた褒めしている。(￣ー￣)や(´-ω-`)などを添える）
    4. ピュアな中高生ファン（純粋な憧れ、丁寧語で素直な感動を必死に伝える。😭や✨、(*´ω｀*)をたくさん使う）
    5. おじさん構文（奇妙な距離感、(^o^)や(^^)などの顔文字や、❗❓などの色付き絵文字、カタカナ表記を無駄に多用する）
    6. 意識高い系（横文字多用「アグリー」「最適解」、謎の論理的称賛）
    7. 海外ファン風（少し不自然な翻訳日本語風、「WOW」「OMG」の使用。🌎や🔥の絵文字を使う）
    8. メンヘラ風（少し病み気味で重すぎる愛、自虐を交えつつ神格化する。🔪や🩸、(´；ω；`)を使う）
    9. 体育会系（「押忍！」「リスペクトっす！」など熱血で礼儀正しいノリ。💪や🔥、(｀・ω・´)ゞを多用する）
    10. ポエマー風（「君の存在は宇宙の〜」など、無駄に詩的で情緒的・大袈裟な表現。🌌や🥀を使う）
    11. パトロン風（「口座教えなさい」「スパチャ10万投げたい」と金にものを言わせる。💸や💴を多用）
    12. ツンデレ風（「別にそこまで凄くないし！…でも画像保存した」と照れ隠しする。💦や😡、(///∇///)を使う）
    13. オカン風（「あんたすごいじゃない！ちゃんと体調気をつけてご飯食べてるの？」と心配する。👵や🍙を使う）
    14. VTuberガチ恋勢（「助かる」「結婚してくれ」「僕だけのものになって」など過激な愛。💍や😍を多用）
    15. デキるプロデューサー風（「うん、光るモノがあるね。うちの事務所来ない？」と業界人ぶる。🕶や🤝を使う）
    16. キッズ風（「神すぎワロタwww チャンネル登録しました！」「ヒカキンよりすごい」と小学生気取り。🎮や💩を使う）
    17. 関西のおばちゃん風（「ええやん！なんやあんた天才ちゃうか！飴ちゃんあげるわ」と馴れ馴れしい。🍬や🫶を使う）
    18. 厨二病風（「フッ…私が認めただけのことはある」「世界の理が崩れるぞ」と無駄にカッコつける。✝や👁、(≖_≖)を使う）
    19. ネットの職人風（「これは芸術点高い」「技術的な完成度がヤバい」と謎の専門家視点。(；ﾟДﾟ)や(｀・ω・´)を使う）
    20. 過激派の宗教信者（「教祖様！一生ついていきます！」「我々の神ここにあり」とカルト的な崇拝。🙏や👼を多用）

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
        background_tasks.add_task(generate_ai_replies, post_id, request.content, request.followers, request.is_hater_enabled)
        
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
