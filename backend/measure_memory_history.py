"""Local paid comparison of 8 memories/3 summaries versus 10/10.

Run: python3 backend/measure_memory_history.py
Synthetic data only; no database writes or deployment.
"""
import asyncio
import contextlib
import io
import json
import os
from pathlib import Path
import random
import sys
from types import ModuleType, SimpleNamespace
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent


class PromptCaptured(BaseException):
    pass


async def run():
    load_dotenv(ROOT / "backend/.env")
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is missing")
    os.environ["SUPABASE_URL"] = ""
    os.environ["SUPABASE_KEY"] = ""
    source = (ROOT / "backend/main.py").read_text()
    modules = {}
    for size, memories in ((3, 8), (10, 10)):
        module = ModuleType(f"memory_benchmark_{size}")
        module.__file__ = str(ROOT / "backend/main.py")
        sys.modules[module.__name__] = module
        exec(compile(source, module.__file__, "exec"), module.__dict__)
        module.REGULAR_MEMORY_LIMIT = memories
        module.REGULAR_INTERACTION_LIMIT = size
        assert module.supabase is None
        modules[size] = module
    client = modules[3].openai_client.with_options(max_retries=0, timeout=90)
    summaries = [
        "仕事帰りに散歩し、公園の赤い花を見つけたと話した。常連は、小さな変化に気づいて楽しめるところが素敵だと返信した。",
        "休日にカフェで読書したと話した。常連は、好きな場所で自分のペースを取り戻せる時間を大切にしていると受け止めた。",
        "初めてパンを焼き、形は不揃いでも香りがよかったと話した。常連は、初挑戦を楽しみながら工夫したことを肯定した。",
        "会議の発表前に緊張していると話した。常連は、声に出して練習した準備を認め、落ち着いて臨めるよう応援した。",
        "発表を無事に終え、安心したと報告した。常連は準備を続けたことと、自分の言葉で伝えられた達成感を喜んだ。",
        "雨の日は外出せず家で映画を観たと話した。常連は、その日の気分に合わせて心地よい過ごし方を選ぶことに共感した。",
        "忙しくても夕食を簡単に作れたと話した。常連は、無理をしすぎず自分に合う工夫を見つけた点を温かく肯定した。",
        "週末の旅行先を調べて楽しみにしていると話した。常連は、景色や食べ物を想像しながら計画する時間も楽しそうだと応じた。",
        "仕事で疲れたので早く寝たいと話した。常連は、一日の頑張りを認め、自分の疲れに気づいて休もうとする判断を尊重した。",
        "帰り道に夕焼けを撮影したと話した。常連は、慌ただしい日でも好きな景色を見つけて写真に残す楽しさを受け止めた。",
    ]
    padding = "投稿者はその日の気持ちを飾らずに伝え、常連は具体的な出来事と気持ちを温かく受け止めた。"
    facts = ["散歩と写真が好き。", "赤い花に関心がある。", "カフェで読書する。", "パン作りを始めた。", "発表に向けて練習した。", "映画を楽しむ。", "夕焼けを撮る。", "景色のよい旅行先が好き。", "忙しい日は簡単な料理を作り、自分のペースで過ごす時間を大切にしている。", "旅行の予定を立てることが好きで、行き先の風景や食べ物を調べる時間も楽しんでいる。"]
    results = []
    for chars in (80, 180):
        for count in (1, 3):
            for size in (3, 10):
                module = modules[size]
                captured = {}
                async def capture(**kwargs):
                    captured.update(kwargs)
                    raise PromptCaptured()
                module.openai_client = SimpleNamespace(beta=SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(parse=capture))))
                histories = [(s + padding * 5)[:chars] for s in summaries]
                regulars = [module.RegularFollowerContext(follower_id=f"synthetic-{i}", author_name=name,
                    avatar_url="https://example.invalid/avatar", memories=[(f + padding * 5)[:160] for f in facts] if chars == 180 else facts,
                    recent_interactions=histories[-size:]) for i, name in enumerate(("ゆき", "みく", "れん")[:count])]
                random.seed(42)
                try:
                    with contextlib.redirect_stdout(io.StringIO()):
                        await module.generate_ai_replies("今日も仕事を頑張った。帰り道の夕焼けがきれいで、少し気持ちが軽くなった。", 200000, False, regular_followers=regulars)
                except PromptCaptured:
                    pass
                assert captured
                # Ensure the actual full summaries reached the model prompt.
                prompt = captured["messages"][0]["content"]
                assert prompt.count(histories[-size]) == count
                if size == 10:
                    assert facts[-1] in prompt and facts[-2] in prompt
                else:
                    assert facts[0] not in prompt and facts[1] not in prompt
                completion = await client.beta.chat.completions.parse(**captured, max_completion_tokens=4096)
                usage = completion.usage.model_dump()
                result = {"summary_chars": chars, "memory_profile": "160-char-cap" if chars == 180 else "natural", "regulars": count, "history": size, "memories": module.REGULAR_MEMORY_LIMIT,
                          "model": completion.model, "usage": usage,
                          "finish_reason": completion.choices[0].finish_reason,
                          "parsed": completion.choices[0].message.parsed is not None}
                results.append(result)
                print(json.dumps(result), flush=True)
    output = ROOT / "docs/analysis/memory-10x10-cost-2026-11-17.json"
    output.write_text(json.dumps({"synthetic": True, "db_writes": False, "samples": results}, ensure_ascii=False, indent=2))
    print(f"Saved {output}", flush=True)


if __name__ == "__main__":
    asyncio.run(run())
