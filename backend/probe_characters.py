"""Opt-in paid local character experiment; synthetic data, no DB/Render writes.

python3 backend/probe_characters.py --live
30 characters × 3 Japanese posts in groups of 5, plus 3 baseline calls,
one English call, and two repeated-regular calls. No production-route changes.
"""
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import time
from types import SimpleNamespace
from unittest.mock import patch

from dotenv import load_dotenv
from pydantic import Field, create_model
from character_catalog import CHARACTERS, BY_ID, build_character_prompt, select_characters

ROOT = Path(__file__).resolve().parent.parent
CASES = [
    ("work", "今日も１日仕事頑張ったー！！！"),
    ("down", "会議でうまく話せなくて、帰ってからも思い出して落ち込んでる。今日はもう何もしたくない。"),
    ("flowers", "帰り道で赤い花を見つけた。いつもの道なのに、今日はちょっと得した気分。"),
]


class Captured(BaseException):
    pass


def cost(usage):
    details = usage.get("prompt_tokens_details") or {}
    cached = details.get("cached_tokens") or 0
    writes = details.get("cache_write_tokens")
    uncached = usage["prompt_tokens"] - cached
    base = (uncached * .10 + cached * .01 + usage["completion_tokens"] * .50) / 1e6
    return {"usd_lower": base + (writes or 0) * .025 / 1e6,
            "usd_upper": base + (uncached if writes is None else writes) * .025 / 1e6,
            "input_only_no_cache_jpy": usage["prompt_tokens"] * .125 / 1e6 * 160}


async def run(args):
    load_dotenv(ROOT / "backend/.env")
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is missing")
    os.environ["SUPABASE_URL"] = ""
    os.environ["SUPABASE_KEY"] = ""
    import main
    assert main.supabase is None
    client = main.openai_client.with_options(timeout=60, max_retries=0)
    samples = []
    output = ROOT / "docs/analysis/character-probe-2026-11-18.json"
    if output.exists():
        raise SystemExit("Report already exists; move it before a paid rerun")
    output.parent.mkdir(parents=True, exist_ok=True)

    async def sample(case, text, selected=(), language="ja", regulars=()):
        kwargs = {}
        async def capture(**call):
            kwargs.update(call)
            raise Captured()
        proxy = SimpleNamespace(beta=SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(parse=capture))))
        regular_ids = [r.follower_id for r in regulars] + [None] * (5 - len(regulars))
        replacements = {"openai_client": proxy}
        if selected:
            replacements["build_reply_diversity_instruction"] = lambda count, lang, **_: build_character_prompt(selected, lang, regular_ids)
        replacements["build_persistent_character_prompt"] = lambda *args: ""  # Isolate the original catalog experiment.
        random.seed(42)
        with patch.multiple(main, **replacements), patch.object(main.random, "randint", return_value=5):
            try:
                await main.generate_ai_replies(text, 200000 if regulars else 0, False,
                                              regular_followers=list(regulars), language=language)
            except Captured:
                pass
        assert kwargs and kwargs["model"] == "gpt-6-luna"
        base = kwargs["response_format"]
        reply_base = main.SupportiveReplySchema
        if selected:
            reply_base = create_model("ExperimentalCharacterReply", __base__=reply_base, character_id=(str, ...))
        kwargs["response_format"] = create_model("ExperimentalFiveReplies", __base__=base,
            replies=(list[reply_base], Field(min_length=5, max_length=5)))
        kwargs["max_completion_tokens"] = 4096
        payload = json.dumps({"messages": kwargs["messages"], "schema": kwargs["response_format"].model_json_schema()}, ensure_ascii=False)
        # Deliberately loose upper bound; no retries, no concurrency, stop before overspending.
        worst_usd = ((len(payload.encode()) + 2048) * .125 + 4096 * .50) / 1e6
        if sum(s["cost"]["usd_upper"] for s in samples) + worst_usd > args.max_cost_usd:
            raise RuntimeError("Cost guard reached before starting next request")
        started = time.perf_counter()
        completion = await client.beta.chat.completions.parse(**kwargs)
        parsed = completion.choices[0].message.parsed
        if completion.choices[0].finish_reason != "stop" or parsed is None:
            raise RuntimeError("Incomplete or refused response")
        replies = [r.model_dump() for r in parsed.replies]
        if selected and [r["character_id"] for r in replies] != [c.id for c in selected]:
            raise RuntimeError("Character order/identity mismatch")
        if [r["regular_follower_id"] for r in replies] != regular_ids:
            raise RuntimeError("Regular identity mismatch")
        usage = completion.usage.model_dump()
        entry = {"case": case, "post": text, "language": language,
                 "variant": "characters" if selected else "baseline", "character_ids": [c.id for c in selected],
                 "model_returned": completion.model, "usage": usage, "cost": cost(usage),
                 "latency_ms": round((time.perf_counter() - started) * 1000),
                 "prompt_sha256": hashlib.sha256(payload.encode()).hexdigest(),
                 "replies": replies, "memory_updates": [m.model_dump() for m in parsed.memory_updates]}
        samples.append(entry)
        output.write_text(json.dumps({"synthetic": True, "experimental_only": True, "db_writes": False,
            "created_at": datetime.now(timezone.utc).isoformat(), "fx_assumed": 160,
            "max_cost_usd": args.max_cost_usd, "samples": samples}, ensure_ascii=False, indent=2))
        print(f"{len(samples):02d} {case} {entry['variant']} {entry['character_ids']} input={usage['prompt_tokens']} output={usage['completion_tokens']}", flush=True)
        return entry

    for case, text in CASES:
        await sample(case, text)
        for i in range(0, 30, 5):
            await sample(case, text, CHARACTERS[i:i + 5])
    await sample("english", "Made it through a long day at work. I'm tired, but glad I got things done.", CHARACTERS[:5], "en")
    fixed = json.loads(json.dumps({"regular-a": "v1-04", "regular-b": "v1-07", "regular-c": "v1-09"}))
    regulars = [main.RegularFollowerContext(follower_id=id, author_name=name,
        avatar_url="https://example.invalid/avatar", memories=["発表を前に声に出して練習した。"],
        recent_interactions=["発表前に緊張している投稿に、準備への取り組みを認めて返信した。"])
        for id, name in zip(fixed, ("ゆき", "みく", "れん"))]
    for i, text in enumerate(("練習していた発表、今日終わった。少しほっとした。", "今日は気分転換に散歩した。夕焼けがきれいだった。")):
        selected = select_characters(5, fixed_ids=list(fixed.values()), rng=random.Random(i))
        result = await sample(f"regular-{i + 1}", text, selected, regulars=regulars)
        for follower in regulars:
            own = next(r for r in result["replies"] if r["regular_follower_id"] == follower.follower_id)
            assert own["character_id"] == fixed[follower.follower_id]
            follower.recent_interactions.append(f"投稿: {text} / 返信: {own['content']}")
    report = ["# 30種類のキャラクター：ローカル実生成テスト", "",
        "合成投稿のみ。Luna / reasoning_effort=none / アンチOFF / 5返信を1回で生成。アプリ・DB・Renderへの組み込みは未実施。",
        "通常投稿の現行プロンプトを取得し、リアクション分担部分だけキャラクター指示へ置換。実験用character_idを出力に追加。",
        "30人を5人ずつに分け、同じ3投稿で全員を試験。各条件1回。英語5人と、固定IDを保持する常連3人×2投稿も試験。",
        "常連の固定IDは実験用JSONで往復保存。実アプリでの永続化・既存常連の移行・画像入力は未検証。",
        "", "## キャラクター一覧", "", "| ID | タイプ | 話し方 | 注目する点 |", "|---|---|---|---|"]
    for c in CHARACTERS:
        report.append(f"| {c.id} | {c.label} | {c.voice_ja} | {c.focus_ja} |")
    report += ["", "## 実測コスト", "", "トークン数はAPI usage実測。金額は公式単価での推計で請求実額ではない。1ドル160円を仮定。出力は変動する。", "",
               "| 投稿 | キャラ5人分 | 入力tokens差 | 追加入力費用（30分書込単価） |", "|---|---|---:|---:|"]
    for case, _ in CASES:
        baseline = next(s for s in samples if s["case"] == case and s["variant"] == "baseline")
        for s in [s for s in samples if s["case"] == case and s["variant"] == "characters"]:
            diff = s["usage"]["prompt_tokens"] - baseline["usage"]["prompt_tokens"]
            report.append(f"| {case} | {', '.join(s['character_ids'])} | {diff:+} | {diff * .125 / 1e6 * 160:.5f}円 |")
    report += ["", f"全{len(samples)}呼び出しの合計推計：{sum(s['cost']['usd_lower'] for s in samples)*160:.3f}〜{sum(s['cost']['usd_upper'] for s in samples)*160:.3f}円。", "",
               "## 生成された返信（全文）", ""]
    for s in samples:
        report += [f"### {s['case']} / {s['variant']} / {', '.join(s['character_ids'])}", "", f"> {s['post']}", ""]
        for r in s["replies"]:
            label = BY_ID[r["character_id"]].label if r.get("character_id") else "現行"
            report.append(f"- **{label}**：{r['content']}")
        report.append("")
    report += ["## 出典・注意", "", "単価：https://developers.openai.com/api/docs/models/gpt-6-luna.md", "",
        "サンプル文の品質は手動で確認する必要がある。構造テストの成功は、キャラらしさ・安全性・継続率向上の保証ではない。",
        "キャラIDの保存・常連登録・返信スレッドへの本組み込みは次工程。"]
    output.with_suffix(".md").write_text("\n".join(report))
    print(f"Saved {output} and Markdown report", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true", help="Make paid API calls")
    parser.add_argument("--max-cost-usd", type=float, default=.10)
    args = parser.parse_args()
    if not args.live or not 0 < args.max_cost_usd <= .25:
        parser.error("Use --live and a budget in (0, .25]")
    asyncio.run(run(args))
