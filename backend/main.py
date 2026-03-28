import os
import random
import requests
from typing import List, Optional, Any, Tuple
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from openai import AsyncOpenAI
from supabase import create_client, Client

# -------- 1. 設定・初期化 --------
load_dotenv()

app = FastAPI(title="ZEN-KOTEI Logic Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    is_onboarding: bool = False
    image_base64: Optional[str] = None

class ReplySchema(BaseModel):
    author_name: str
    content: str
    is_hater: bool
    is_defender: bool

class GenerateRepliesResponse(BaseModel):
    replies: List[ReplySchema]


# -------- 3. リソース (モックアバター) --------
# picsum.photosのseed URLを使用して多様なジャンルの画像を100種類用意
AVATARS = [f"https://picsum.photos/seed/user{i}/150/150" for i in range(1, 101)]

# アンチ用は別のシード名で20種類
HATER_AVATARS = [f"https://picsum.photos/seed/hater{i}/150/150" for i in range(1, 21)]

def resolve_avatar_url(seed_url: str) -> str:
    """picsum.photosのseed URLからリダイレクトを解決し、最終的な直接画像URLを返す"""
    try:
        resp = requests.get(seed_url, allow_redirects=True, timeout=5, stream=True)
        final_url = resp.url  # リダイレクト後の最終URL (fastly.picsum.photos/id/xxx/...)
        resp.close()  # 画像データは不要なので即座に閉じる
        return final_url
    except Exception:
        return seed_url  # 失敗時はそのまま返す（フォールバック）


def build_length_plan_shuffled(n: int) -> List[str]:
    """
    短文:約30字 / 中文:約60字 / 長文:約100字 を目安に、件数比率 3:4:3 になるようラベルを割り当て、順序だけシャッフルする。
    """
    if n <= 0:
        return []
    n_short = max(0, round(n * 0.3))
    n_long = max(0, round(n * 0.3))
    n_mid = n - n_short - n_long
    while n_mid < 0:
        if n_short > 0:
            n_short -= 1
            n_mid += 1
        elif n_long > 0:
            n_long -= 1
            n_mid += 1
        else:
            break
    while n_short + n_mid + n_long < n:
        n_mid += 1
    while n_short + n_mid + n_long > n:
        if n_mid > 0:
            n_mid -= 1
        elif n_short > 0:
            n_short -= 1
        else:
            n_long -= 1
    labels = ["短文"] * n_short + ["中文"] * n_mid + ["長文"] * n_long
    random.shuffle(labels)
    return labels


LENGTH_BAND = {
    "短文": "20〜45字（句読点・絵文字を含む日本語の文字数。目安30字前後）",
    "中文": "50〜85字（目安60字前後）",
    "長文": "90〜130字（目安100字前後）",
}


def extract_normal_and_hater_defender_pairs(
    all_replies: List[ReplySchema],
) -> Tuple[List[ReplySchema], List[List[ReplySchema]]]:
    """
    アンチ→擁護が**連続**で返ってきたペアを優先して抽出する。
    残りのアンチ・擁護は出現順のリストをインデックスで対応付ける（従来の zip と同等だが、連続ペアを先に取る）。
    フロントでは通常リプライだけシャッフルし、アンチ+擁護の塊は順序を保ったまま挿入する。
    """
    n = len(all_replies)
    consumed = [False] * n
    normal: List[ReplySchema] = []
    pairs: List[List[ReplySchema]] = []

    i = 0
    while i < n:
        if consumed[i]:
            i += 1
            continue
        r = all_replies[i]
        if r.is_hater and i + 1 < n and all_replies[i + 1].is_defender:
            pairs.append([r, all_replies[i + 1]])
            consumed[i] = True
            consumed[i + 1] = True
            i += 2
            continue
        if not r.is_hater and not r.is_defender:
            normal.append(r)
            consumed[i] = True
        i += 1

    orphan_haters: List[ReplySchema] = []
    orphan_defenders: List[ReplySchema] = []
    for idx in range(n):
        if consumed[idx]:
            continue
        r = all_replies[idx]
        if r.is_hater:
            orphan_haters.append(r)
        elif r.is_defender:
            orphan_defenders.append(r)

    for hi, h in enumerate(orphan_haters):
        pair = [h]
        if hi < len(orphan_defenders):
            pair.append(orphan_defenders[hi])
        pairs.append(pair)
    if len(orphan_defenders) > len(orphan_haters):
        normal.extend(orphan_defenders[len(orphan_haters) :])

    return normal, pairs


# -------- 4. AI ドラマエンジン --------
async def generate_ai_replies(content: str, followers: int, is_hater_enabled: bool, is_onboarding: bool = False, image_base64: Optional[str] = None) -> List[dict]:
    """
    OpenAIを利用してリプライを一括生成し、レスポンス用の辞書リストを返す
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
        1: {"min": 3, "max": 5, "haters": 0},   # 2*1.3=2.6, 4*1.3=5.2
        2: {"min": 4, "max": 7, "haters": 0},   # 3*1.3=3.9, 5*1.3=6.5
        3: {"min": 4, "max": 7, "haters": 0},   
        4: {"min": 5, "max": 8, "haters": 1},   # 4*1.3=5.2, 6*1.3=7.8 / hatersは据え置き
        5: {"min": 5, "max": 9, "haters": 1},   # 4*1.3=5.2, 7*1.3=9.1 / 2*1.3=2.6 -> 3
        6: {"min": 7, "max": 10, "haters": 1},  # 5*1.3=6.5, 8*1.3=10.4
        7: {"min": 7, "max": 12, "haters": 2},  # 5*1.3=6.5, 9*1.3=11.7
        8: {"min": 8, "max": 13, "haters": 2},  # 6*1.3=7.8, 10*1.3=13.0 / 3*1.3=3.9 -> 4
        9: {"min": 9, "max": 14, "haters": 2},  # 7*1.3=9.1, 11*1.3=14.3
        10: {"min": 10, "max": 16, "haters": 3} # 8*1.3=10.4, 12*1.3=15.6 / 4*1.3=5.2 -> 5
        }
    
    params = rank_params.get(rank, rank_params[10])
    total_replies = random.randint(params["min"], params["max"])
    
    # アンチ数を確率で決定（上限はrank_paramsの定義通り）
    if is_onboarding:
        hater_count = 1
    else:
        max_haters = params["haters"] if is_hater_enabled else 0
        if max_haters > 0 and random.random() < 0.4:
            hater_count = random.randint(1, max_haters)
        else:
            hater_count = 0
    
    length_labels = build_length_plan_shuffled(total_replies)
    length_plan_lines = "\n".join(
        f"    - replies配列の **{i}件目**（JSONではインデックス {i-1}）の content は **{LENGTH_BAND[lab]}** に必ず収める（{lab}）"
        for i, lab in enumerate(length_labels, start=1)
    )
    length_and_tone = f"""【文字数（厳守）】
全{total_replies}件の返信について、**短文:中文:長文 = 3:4:3 の件数**になるようラベルを割り当て、順序はランダムにシャッフル済みです。
**下の「各返信の文字数帯」に従い、replies[i].content の文字数が帯から外れないようにしてください。**（各 content 生成後に文字数を数え、帯外なら短くするか長くして調整すること）

{length_plan_lines}

※ 「短文」「中文」「長文」は上の**件数比率**に対応するラベルです。ユーザーの投稿の語句・文脈を拾い、各ペルソナの口調で書くこと。"""
    
    # オンボーディング時の擁護者数
    defender_count = 2 if is_onboarding else hater_count

    # アンチに関する動的指示（GUARDIANタグの厳格制御含む）
    if hater_count == 0:
        hater_instruction = "【配役とフラグ】\n今回はアンチが発生しないため、全員を通常のフォロワーとしてください。（全員必ず is_hater=false, is_defender=false に設定すること。擁護者フラグは絶対に立てないでください）"
    else:
        hater_base = f"""【批判者（アンチ）の設定】
総返信のうち、{hater_count}件を批判者（is_hater=true, is_defender=false）にしてください。
批判者は以下を**必ず満たす**こと。読者が「キツい」「批判だな」と感じるレベルまで、**ネガティブに寄せる**（ただし暴言・差別・脅迫・特定の人格への罵倒は禁止）：

・ **投稿の内容・論点・言い回し・見せ方・承認欲求の出し方**のいずれかに、**はっきりした否定や難癖**をつける（例：「それ自慢？」だけで終わらせず、**なぜ刺さらないか**を一文以上で言う）
・ **冷笑・皮肉・上から目線のダメ出し**（「この投稿いる？」「誰得？」「ちょっと考え直した方がいい」「自意識過剰で見える」「根拠が弱い」など）
・ **共感やフォローに見せかけた否定**は禁止。批判者は「肯定」や「わかる」で始めない。
・ **弱い表現**（「〜かも」「ちょっとだけ気になる」だけで終わる）は避け、**自分の立場としての否定的な結論**を書く。
・ 投稿に書かれた**単語・事実**を1つ以上引用し、それに対してツッコむ（抽象的な悪口だけにしない）。

※ 禁止：暴言・差別・脅迫・スラング連発。許容：嫌味・皮肉・冷笑的・突き放した・ネット民っぽい辛口。"""

        if is_onboarding:
            hater_instruction = f"""{hater_base}
【オンボーディング専用：アンチ→擁護→改心の3段展開（必須）】
以下の3件を**この順番で連続して** replies 配列に含めてください：

1. **アンチの返信**（is_hater=true, is_defender=false）: 投稿内容を具体的に批判する。author_name を覚えておくこと。
2. **擁護者の返信**（is_hater=false, is_defender=true）: アンチの主張を引用し、**直接反論**してユーザーを擁護する。アンチとは別の author_name にすること。
3. **アンチの改心した返信**（is_hater=false, is_defender=true）: **1と同じ author_name** で、擁護者の反論を受けて態度を改め、「確かにそうかも」「言い過ぎたわ」のようにユーザーを認める内容にする。

- 上記3件は replies 配列内で**必ず連続**させること（間に通常コメントを挟まない）。
- それ以外のフォロワーは is_hater=false, is_defender=false とすること。"""
        elif rank == 10:
            hater_instruction = f"{hater_base}\nただし、アンチの1人は他のフォロワーの反応を見て、最後に「改心して擁護（is_defender=true）へ変わる」展開を入れてください。\n普通のフォロワーは is_hater=false, is_defender=false です。"
        else:
            hater_instruction = f"""{hater_base}
【アンチと擁護の対応（内容・必須）】
- アンチ {hater_count} 件に対し、擁護者は **{defender_count} 名**必須（is_hater=false, is_defender=true）。
- 各擁護者はアンチの論点に**直接反論**すること。擁護者の content には必ず含める：(1) アンチの主張の言い換え、または「〇〇って言ってるけど」「さっきのコメント」など**アンチの発言を指す表現**、(2) その論点への**反論**、(3) ユーザーを擁護する文。
- 擁護者は「投稿への一般的なファン」ではなく、**アンチのコメントへの反論**として書く。称賛だけ・同意だけで終わらせない。
アンチの直後には、必ずアンチに反論してユーザーを擁護する人（is_hater=false, is_defender=true）を **{defender_count} 名**連続で登場させてください。
それ以外のフォロワーは is_hater=false, is_defender=false とすること。"""

    # キャラクターリストを毎回シャッフルしてからプロンプトに埋め込む（AIが番号順に選ぶのを防止）
    character_pool = [
        "17歳・女子高校生（友達とのLINEノリで話す。「まじで」「やば」など短い感嘆詞が多く、絵文字をよく使う）",
        "21歳・男子大学生（サークルやバイトの話題に敏感。軽い口調で共感してくれる。「わかる」「それな」が口癖）",
        "24歳・新卒OL（社会人1年目。仕事の疲れから深夜にSNSを見て癒されている。丁寧だけど親しみやすい口調）",
        "28歳・男性フリーランスデザイナー（クリエイティブな視点で褒める。「構図がいい」「センスある」など具体的に褒める）",
        "32歳・女性・2児のママ（育児の合間にSNSを見る。温かく応援してくれる。「わかるー！」「うちもそう！」と共感型）",
        "19歳・男性・専門学生（ゲームやアニメが好きだが普通の子。「すげー」「マジか」などシンプルな反応）",
        "35歳・男性会社員（営業職。仕事帰りの電車でSNSを見る。落ち着いた口調で的確に褒める）",
        "26歳・女性看護師（夜勤明けにSNSを流し見。優しい言葉をかけてくれる。「無理しないでね」と気遣いも）",
        "45歳・男性・中小企業の部長（少しおじさんっぽい文体。句読点が多め。でも言ってることは温かい）",
        "22歳・女性・美容系インフルエンサー志望（写真や見た目を具体的に褒める。「かわいい！」「映えてる！」が多い）",
        "30歳・男性エンジニア（論理的に「これがすごい理由」を分析して褒めてくれる。少し理屈っぽいが悪意はない）",
        "40歳・女性・パート主婦（近所のおばさん的な温かさ。「えらいねぇ」「すごいわぁ」と素朴に褒める）",
        "16歳・男子高校生（部活帰りにスマホを見る。「かっけぇ」「やべぇ」などストレートな感想）",
        "27歳・女性・カフェ店員（おしゃれなものが好き。「雰囲気いいね」「素敵」など柔らかい表現）",
        "50歳・男性・自営業（人生経験からの深い共感。「若い頃の自分を思い出す」など味のあるコメント）",
        "23歳・女性・大学院生（知的だが堅すぎない。「興味深い」「面白い視点」など少しアカデミックな褒め方）",
        "38歳・男性・トラック運転手（休憩中にSNSを見る。飾らない言葉で素直に感想を言う。「いいじゃん」がシンプル）",
        "20歳・女性・アパレル店員（トレンドに敏感。「おしゃれ！」「真似したい！」とポジティブ）",
        "33歳・男性・公務員（真面目な性格が文章に出る。丁寧語ベースだが心からの称賛が伝わる）",
        "29歳・女性・ヨガインストラクター（ポジティブなエネルギーに溢れる。「素敵なエネルギー感じる！」など前向き）",
    ]
    random.shuffle(character_pool)
    characters_text = "\n".join([f"    {i+1}. {c}" for i, c in enumerate(character_pool)])

    pairing_json_rules = ""
    if hater_count > 0:
        if is_onboarding:
            pairing_json_rules = """
    【replies JSON の並び順（オンボーディング専用・必須）】
    - replies 配列内に**アンチ(is_hater=true) → 擁護者(is_defender=true) → 改心したアンチ(is_defender=true, 同じauthor_name)** の3件を**連続して**配置する。
    - この3件の間に通常コメントを挟まない。
    - 通常コメント（is_hater=false かつ is_defender=false）は、この3件ブロックの前後に配置してよい。
    """
        elif defender_count > hater_count:
            pairing_json_rules = f"""
    【replies JSON の並び順（必須・表示とペア整合のため）】
    - **is_hater=true の行の直後に、そのアンチに対応する is_defender=true を {defender_count} 件連続**で配置する。**アンチ行と擁護行の間に他の返信を挟まない。**
    - 通常コメント（is_hater=false かつ is_defender=false）は、アンチ→擁護ブロックの前後に混ぜてよい。
    """
        else:
            pairing_json_rules = """
    【replies JSON の並び順（必須・表示とペア整合のため）】
    - **is_hater=true の行の直後の1件は、必ずそのアンチに対応する is_defender=true** とする。**アンチ行と擁護行の間に他の返信を挟まない。**
    - 通常コメント（is_hater=false かつ is_defender=false）は、アンチ→擁護のペアの前後に混ぜてよい。
    - 複数アンチがある場合は、(アンチ1→擁護1)、(アンチ2→擁護2) のように、**各擁護が直前のアンチに対応する**ように並べる。
    """

    system_prompt = f"""
    あなたはSNS「ZEN-KOTEI」の仮想フォロワーエンジンです。
    ユーザーの承認ランクは「Lv.{rank}」（フォロワー: {followers}）です。
    ユーザーの投稿に対して、以下の条件に沿った架空のフォロワーからの返信を **きっちり {total_replies} 件**（多くても少なくてもダメ）JSONで作成してください。

    【文字数の定義（上の「各返信の文字数帯」と一致）】
    ・ 短文: {LENGTH_BAND["短文"]}
    ・ 中文: {LENGTH_BAND["中文"]}
    ・ 長文: {LENGTH_BAND["長文"]}

    {length_and_tone}
{pairing_json_rules}
    【返信トーンの自然さ】
    **is_hater=false かつ is_defender=false の通常返信**について：全件が「すごい！」「最高！」のような褒め一辺倒にならないようにし、実際のSNSのようにバラつかせる。

    ・ **共感・肯定型**（3〜4割）: 「わかる」「いいね」「自分もそう思う」など自然な同意
    ・ **中立・感想型**（3〜4割）: 「へー、そうなんだ」「面白いね」「なるほど」など、素直な感想や軽い反応
    ・ **質問・興味型**（1〜2割）: 「どこで？」「それってどうやるの？」など
    ・ **雑談・脱線型**（1割程度）: 投稿をきっかけに自分の話をする

    **is_hater=true の返信には上記の配分は適用しない。** 必ず【批判者（アンチ）の設定】に従い、肯定・共感で始めず批判トーンにすること。
    **is_defender=true** は擁護のみ（**直前のアンチ発言への反論**＋ユーザーへの肩入れ。投稿への無関係な称賛だけにしない）。

    投稿が「頑張った報告」「成果報告」の場合は、通常返信では褒め・称賛を多めに。日常系は中立・質問を多めに。
    **全体として、友達のタイムラインを見ているような自然なリアクション**を目指す（ただし批判者・擁護者は展開ルール優先）。

    【絵文字・顔文字（日本のSNSらしさ・多彩に）】
    実際のX・LINE・Instagramのリプでは、絵文字や顔文字が**それなりに**混ざります。**全件に必須ではない**が、今回の全{total_replies}件のうち**おおよそ半数前後（目安4〜6割）**の返信には、絵文字・顔文字・語尾表現の**いずれかを1つ以上**入れてください。残りはプレーンテキストのみでもよい。
    ・ **種類を返信ごとに変える**：同じ絵文字（例: 😂だけ）を何件も繰り返さない。**Unicode絵文字**はカテゴリを混ぜる（例: 顔系 😭🤣🥹😮‍💨、手・反応 👏🙌👍✌️💪、ハート・記号 💖✨🫶🌟、炎上・皮肉 🔥💀🙄😮‍💨、涙・笑 💦🤭🫠、動物・食 🐶🍣☕、旗・記号 🇯🇵🎉）。
    ・ **顔文字は多様に**：(笑)、(^_^)、(´･ω･`)、(´；ω；`)、( ꒪⌓꒪)、(๑•̀ㅂ•́)و、(*´▽`*)、(・ω・)、(￣▽￣)、(´-ω-`)、(｀・ω・´)、(๑˃̵ᴗ˂̵)、( ꒪Д꒪)ノ、＿|￣|○、orz、ｗｗｗ／ww／笑／草／〜！／っていうか など、**2ch・ニコニコ・LINE・Xの混じり**を意識する。
    ・ ペルソナに合わせる：若年層は絵文字・顔文字のバリエーション多め／年配は「笑」「^^」「(笑)」や句読点・「〜ですね」＋軽い絵文字（🙂👍）でもよい。
    ・ **is_hater=true** は皮肉・呆れ・煽り系（🙄😅💢🤡👎🍵、（笑））も。**is_defender=true** は励まし・共感（🥺💪🫂👏、(*´ω`*)）も。
    ・ 同じ記号の連打や、文全体が絵文字だらけになるのは避け、自然な分量（だいたい1〜4個程度）に留める。

    【ペルソナダイバーシティ（多様性）の強制】
    生成される複数の返信は、すべて**異なるペルソナ（年齢・性別・職業）**を持つ、現実のSNSにいそうな普通の人間として作成してください。以下のペルソナリストの**上から順番に**1件ずつ使用してください（リストは毎回ランダムにシャッフルされています）。それぞれのペルソナの年齢や職業にふさわしい自然な口調・語彙で書くこと。
    **is_hater=true の行**は、割り当てペルソナの口調（若者言葉・丁寧語など）を保ちつつ、内容だけ**批判・皮肉・否定**に振ること（説明文の「褒める」「共感」は無視してよい）。
{characters_text}

    【最重要ルール1: 投稿内容への具体的言及（必須）】
    **全返信は、ユーザーの投稿に書かれた具体的なキーワード・主張・感情・状況のいずれかに直接反応すること。**
    - 投稿の中の**単語やフレーズを引用・言い換え**て、それに対するリアクションを書く。
    - 「いいね」「すごい」「最高」など、**どの投稿にも使い回せる汎用的な反応だけで終わらせることは厳禁**。
    - 投稿が「今日カレー食べた」なら「カレー」「何カレー？」に言及する。「仕事疲れた」なら「仕事」の何が疲れたかに触れる。**投稿の内容を読んでいなければ書けない返信**にすること。

    【最重要ルール2: AI定型文の絶対禁止】
    「最高すぎます」「素晴らしいですね」「お疲れ様です」「頑張って」などのAIが書きがちな無難な定型文は**絶対に使用しないでください**。
    X(旧Twitter)やInstagramで実際の人間が書き込むような、その人の年齢や立場がにじみ出る自然なコメントを徹底してください。

    【最重要ルール3: 返信内容の重複禁止】
    **各返信の content は、他のすべての返信と意味的に重複しないこと。**
    - 同じ感想・同じ褒め方・同じ批判・同じ質問の繰り返しは厳禁。
    - 似たニュアンスの返信が2つ以上存在してはならない。
    - 各返信はそれぞれ**異なる視点・異なる論点・異なる感情**で書くこと。

    【展開ルール】
    1. {hater_instruction}
    2. ユーザー名（author_name）は、SNSでよくある適当なニックネームやハンドルネームにすること（例：「ゆき」「たけし」「miku_23」「ren」など）。ペルソナの職業や属性を名前に含めなくてよい。
    """

    try:
        user_message_content: List[dict[str, Any]] = [{"type": "text", "text": f"ユーザーの投稿: {content}"}]
        # もし画像Base64が渡されていれば、OpenAIのVision形式ペイロードに追加
        if image_base64:
            # プレフィックスがない場合は補足する
            prefix = "" if image_base64.startswith("data:image") else "data:image/jpeg;base64,"
            user_message_content.append({
                "type": "image_url",
                "image_url": {"url": f"{prefix}{image_base64}"}
            })

        # OpenAI API Structured Outputs を使って確実にJSONスキーマで返却させる
        completion = await openai_client.beta.chat.completions.parse(
            model="gpt-5.4-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message_content}
            ],
            response_format=GenerateRepliesResponse,
        )
        
        parsed_data = completion.choices[0].message.parsed
        
        if not supabase:
            print("--- [WARNING] DB NOT CONNECTED. DUMPING MOCK RESULTS ---")
            for rep in parsed_data.replies: print(rep)
            return
            
        all_replies = list(parsed_data.replies)
        if is_onboarding:
            ordered_replies = all_replies
        else:
            normal, pairs = extract_normal_and_hater_defender_pairs(all_replies)
            random.shuffle(normal)
            for pair in pairs:
                insert_pos = random.randint(0, len(normal))
                for j, item in enumerate(pair):
                    normal.insert(insert_pos + j, item)
            ordered_replies = normal
        
        result = []
        author_avatar_map: dict[str, str] = {}
        for index, rep in enumerate(ordered_replies):
            if rep.author_name in author_avatar_map:
                avatar = author_avatar_map[rep.author_name]
            else:
                seed_url = random.choice(HATER_AVATARS) if rep.is_hater else random.choice(AVATARS)
                avatar = resolve_avatar_url(seed_url)
                author_avatar_map[rep.author_name] = avatar
            result.append({
                "author_name": rep.author_name,
                "author_img": avatar,
                "content": rep.content,
                "is_hater": rep.is_hater,
                "is_defender": rep.is_defender,
            })
            
        print(f"✅ AI Replies generated: {len(result)} replies")
        return result
        
    except Exception as e:
        print(f"❌ AI Generation Error: {e}")
        raise


# -------- 5. ルーティング (API Endpoints) --------
@app.post("/api/posts")
async def create_post(request: PostRequest):
    """
    AI返信を生成し、結果を直接レスポンスで返す。DB保存は行わない。
    """
    try:
        replies = await generate_ai_replies(
            content=request.content,
            followers=request.followers,
            is_hater_enabled=request.is_hater_enabled,
            is_onboarding=request.is_onboarding,
            image_base64=request.image_base64,
        )
        return {"status": "success", "replies": replies}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class UserUpdateRequest(BaseModel):
    total_followers: int
    total_posts: int
    has_completed_onboarding: Optional[bool] = None

@app.post("/api/users")
def register_user(request: dict):
    """
    初回起動時にアプリ側で生成したUUIDを受け取り、usersテーブルに登録する。
    既に存在する場合は何もしない（upsert）。
    """
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    
    user_id = request.get("user_id", "")
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    
    existing = supabase.table("users").select("id, has_completed_onboarding").eq("id", user_id).execute()
    if existing.data:
        return {
            "status": "existing",
            "user_id": user_id,
            "has_completed_onboarding": existing.data[0].get("has_completed_onboarding", False)
        }
    
    supabase.table("users").insert({
        "id": user_id,
        "total_followers": 0,
        "total_posts": 0,
        "has_completed_onboarding": False
    }).execute()
    return {"status": "created", "user_id": user_id, "has_completed_onboarding": False}

@app.get("/api/users/{user_id}")
def get_user_status(user_id: str):
    """
    Fetch current followers and posts count for a user.
    """
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    res = supabase.table("users").select("total_followers, total_posts, has_completed_onboarding").eq("id", user_id).execute()
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
    update_data: dict = {
        "total_followers": request.total_followers,
        "total_posts": request.total_posts
    }
    if request.has_completed_onboarding is not None:
        update_data["has_completed_onboarding"] = request.has_completed_onboarding
    supabase.table("users").update(update_data).eq("id", user_id).execute()
    return {"status": "success"}

@app.get("/")
def health_check():
    return {"status": "ok", "message": "ZEN-KOTEI Backend logic is running."}

# [実行コマンド]
# uvicorn main:app --reload
