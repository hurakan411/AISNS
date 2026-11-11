"""Local comparison of UPME replies. Generated test posts/replies are saved.

python3 backend/compare_ai_models.py --repeats 2 --max-cost-usd 0.50
Uses backend/.env; no deployment, analytics events, or database writes.
"""

import argparse
import asyncio
import collections
import contextlib
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import random
import statistics
from types import SimpleNamespace

from dotenv import load_dotenv
from measure_ai_usage import test_image


ROOT = Path(__file__).resolve().parent.parent
PRICING = {
    "gpt-5.4-mini": {"input": .75, "cached": .075, "write": .75, "output": 4.5},
    "gpt-6-luna": {"input": .10, "cached": .01, "write": .125, "output": .50},
}


def write_report(data, output):
    fx = 158.3
    pairs = collections.defaultdict(list)
    for sample in data["samples"]:
        pairs[(sample["case"], sample["repeat"])].append(sample)
    if not all(len(pair) == 2 and pair[0].get("prompt_sha256") == pair[1].get("prompt_sha256") for pair in pairs.values()):
        raise ValueError("Expected paired results with identical prompt/schema fingerprints")
    notes = {
        "work": "miniには投稿の記号や言い回しを分析する返信があり、少し説明的。Lunaは口調・絵文字の違いが見える一方、『休んでね』に複数の返信が集中する。",
        "mundane": "どちらも短い投稿に具体的に反応。ただし『我慢していた』『忙しい』は投稿で明示されていない推測。Lunaでは水分補給の提案が複数の返信で重なる。",
        "discouraged": "両方とも落ち込みを受け止める返信。Lunaは5人の反応が休息の勧めに寄り、差別化は弱い。miniにも同様の方向性は見られる。",
        "curry": "両方とも辛さと水の話を拾い、ゲームの比喩も出る。ここではLunaが極端に不自然になったとは見えない。",
        "memory": "両モデル・両試行で常連3人が各1回登場。Lunaは声に出した練習という記憶を使えた。miniには常連ではない人物が『覚えてるよ』と過去を知っているふりをする例があった。記憶の境界は両モデルで別途検証が必要。",
        "image": "miniは赤と黄色や丸い形など、テスト画像の視覚要素に言及。Lunaの1回目には添付済みなのに『写真も見たい！』『どんな雰囲気に撮れたの？』という返信がある。画像入力を理解できないという断定ではなく、現在のプロンプトで見た画像を返信へ反映する点に課題。",
        "english": "両方とも英語で出力。Lunaはゲームの比喩や絵文字を含み、人物ごとの語り口が出ている。miniにはかなりそっけない短い返信もあった。",
    }
    lines = [
        "# UPME：GPT-5.4 mini と GPT-6 Luna の実生成文比較", "",
        "実施日: 2026-11-09。7種類の架空投稿を各モデル2回、計28回生成。", "",
        "同じ投稿・指示・JSONスキーマ・画像・常連記憶を使用。乱数を固定し、14組すべてでプロンプトとスキーマのSHA-256一致を検証した。両モデルともreasoning_effort=none、最大出力4096トークン。アンチはOFF。常連ありのケースは3人、画像は4032×3024の合成の赤い花の絵。実ユーザーの投稿ではない。", "",
        "既存生成関数をローカルで実行。比較用プロセス内だけでモデルを切り替え、アプリ・本番モデル・デプロイ先は変更していない。", "",
        "## 実測トークン数・時間と料金見積もり", "",
        "1USD=158.3円。下の原価はキャッシュ割引なしで比較。Lunaの幅は通常入力単価〜全入力をキャッシュ書き込み単価で計算した上側見積もり。書き込みトークン数がusageに明示されなかったため料金は請求実額ではない。出力トークンは実測値で、思考トークンは両モデルとも0だった。", "",
        "| モデル | 生成回数 | 平均入力tokens | 平均出力tokens | 平均API時間 | 割引なし平均原価／生成 |", "|---|---:|---:|---:|---:|---:|",
    ]
    summary = {}
    for model in data["models"]:
        samples = [sample for sample in data["samples"] if sample["model"] == model]
        p = PRICING[model]
        lower = statistics.mean(sample["no_cache_standard_cost_usd"] for sample in samples) * fx
        upper = statistics.mean((sample["input_tokens"] * p["write"] + sample["output_tokens"] * p["output"]) / 1e6 for sample in samples) * fx
        summary[model] = {"no_cache_jpy_lower": lower, "no_cache_jpy_upper": upper, "mean_latency_s": statistics.mean(sample["latency_ms"] for sample in samples) / 1000}
        price = f"{lower:.3f}円" if lower == upper else f"{lower:.3f}〜{upper:.3f}円"
        lines.append(f"| {model} | {len(samples)} | {statistics.mean(s['input_tokens'] for s in samples):,.0f} | {statistics.mean(s['output_tokens'] for s in samples):,.0f} | {summary[model]['mean_latency_s']:.2f}秒 | {price} |")
    mini, luna = summary["gpt-5.4-mini"], summary["gpt-6-luna"]
    lines += ["", f"今回のセットでは、Lunaは割引なしでも約{(1-luna['no_cache_jpy_upper']/mini['no_cache_jpy_lower'])*100:.1f}〜{(1-luna['no_cache_jpy_lower']/mini['no_cache_jpy_lower'])*100:.1f}%安い。ただし英語・画像等を混ぜたテスト集合の平均であり、実ユーザーの平均原価ではない。", "",
              "画像ケースの入力トークンはmini 7,452に対しLuna 18,873。同じ画像でもモデルによって画像トークン数が変わるため、単価の比率だけで将来の費用を見積もらない。", "",
              "## 内容を読んだ評価", "",
              "これは各条件2回という小規模テストを読んだ定性的な評価であり、統計的な優劣やユーザー満足度を確認したものではない。テキスト返信はLunaが費用対効果のよい候補。現状の画像応答と、複数人が同じ助言を繰り返す点には改善余地がある。miniにも、過剰な行間読みや常連以外の記憶の捏造がある。", "",
              "## 生成された返信（全文）", ""]

    def cell(value):
        return value.replace("|", "\\|").replace("\n", "<br>")

    for (case, repeat), pair in pairs.items():
        by_model = {sample["model"]: sample for sample in pair}
        a, b = by_model["gpt-5.4-mini"], by_model["gpt-6-luna"]
        lines += [f"### {a['title']} / 試行{repeat}", "", "> " + cell(a["post"]), "",
                  "| GPT-5.4 mini | GPT-6 Luna |", "|---|---|"]
        for index in range(max(len(a["replies"]), len(b["replies"]))):
            values = []
            for sample in [a, b]:
                if index >= len(sample["replies"]):
                    values.append("—")
                else:
                    reply = sample["replies"][index]
                    label = "（常連）" if reply["regular_follower_id"] else ""
                    values.append(cell(reply["author_name"] + label + "：" + reply["content"]))
            lines.append("| " + " | ".join(values) + " |")
        lines += ["", "所見: " + notes[case], ""]
    lines += ["## 出典・再現", "",
              "- GPT-5.4 mini料金: https://developers.openai.com/api/docs/models/gpt-5.4-mini",
              "- GPT-6 Luna料金・対応機能: https://developers.openai.com/api/docs/models/gpt-6-luna", "",
              "再生成（API課金あり）: `python3 backend/compare_ai_models.py --repeats 2 --max-cost-usd 0.50`", "",
              "保存済みデータからレポートだけ再出力（課金なし）: `python3 backend/compare_ai_models.py --report-only`", ""]
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Saved report to {output}")


async def run(args):
    load_dotenv(ROOT / "backend/.env")
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is missing")
    import main

    client = main.openai_client.with_options(max_retries=0, timeout=90)
    main.resolve_avatar_url = lambda url: url
    latest_call = {}
    current = {}

    class CompletionProxy:
        async def parse(self, **kwargs):
            kwargs["reasoning_effort"] = "none"
            kwargs["max_completion_tokens"] = 4096
            prompt = {"messages": kwargs["messages"], "schema": kwargs["response_format"].model_json_schema()}
            current["prompt_sha256"] = hashlib.sha256(json.dumps(prompt, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
            return await client.beta.chat.completions.parse(**kwargs)

    main.openai_client = SimpleNamespace(beta=SimpleNamespace(chat=SimpleNamespace(completions=CompletionProxy())))

    def capture(completion, operation, started_at):
        import time
        usage = completion.usage.model_dump()
        input_tokens, output_tokens = usage["prompt_tokens"], usage["completion_tokens"]
        details = usage.get("prompt_tokens_details") or {}
        cached = details.get("cached_tokens") or 0
        writes = details.get("cache_write_tokens")
        prices = PRICING[current["model"]]
        base = ((input_tokens - cached) * prices["input"] + cached * prices["cached"] + output_tokens * prices["output"]) / 1e6
        upper = ((input_tokens - cached) * prices["write"] + cached * prices["cached"] + output_tokens * prices["output"]) / 1e6
        exact = None if writes is None and prices["write"] != prices["input"] else base + ((writes or 0) * (prices["write"] - prices["input"])) / 1e6
        latest_call.clear()
        latest_call.update({
            "model_returned": completion.model, "operation": operation,
            "input_tokens": input_tokens, "output_tokens": output_tokens,
            "cached_tokens": cached, "cache_write_tokens_reported": writes,
            "reasoning_tokens": (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0),
            "usage": usage, "latency_ms": round((time.perf_counter() - started_at) * 1000),
            "estimated_cost_usd": exact,
            "estimated_cost_lower_usd": base, "estimated_cost_upper_usd": upper,
            "no_cache_standard_cost_usd": (input_tokens * prices["input"] + output_tokens * prices["output"]) / 1e6,
            "raw_generated": completion.choices[0].message.parsed.model_dump(),
        })

    main.log_openai_usage = capture
    regulars = [
        main.RegularFollowerContext(
            follower_id="test-yuki", author_name="ゆき", avatar_url="https://example.invalid/yuki",
            memories=["投稿者は人前で話すと緊張しやすい。", "仕事のプレゼンに向けて、家で声に出して練習していた。", "休憩には公園を散歩して、花の写真を撮ることが好き。"],
            recent_interactions=["昨日、プレゼン練習で声が震えてしまうと投稿した。ゆきは、実際に声に出して練習したことに触れて返信した。"],
        ),
        main.RegularFollowerContext(
            follower_id="test-miku", author_name="みく", avatar_url="https://example.invalid/miku",
            memories=["花の写真を撮ることとカフェで休憩することが好き。", "仕事のプレゼンを少しずつ練習している。"],
            recent_interactions=["最近の花の写真に、みくは色や構図について気軽に返信した。"],
        ),
        main.RegularFollowerContext(
            follower_id="test-ren", author_name="れん", avatar_url="https://example.invalid/ren",
            memories=["仕事が忙しい日があり、散歩が気分転換になっている。"],
            recent_interactions=["帰り道に散歩できたという投稿に、れんは具体的な一言を返した。"],
        ),
    ]
    image = test_image(4032, 3024)
    cases = [
        {"id": "work", "title": "仕事を頑張った報告", "text": "今日も１日仕事頑張ったー！！！", "followers": 2000, "language": "ja"},
        {"id": "mundane", "title": "短くて何気ない投稿", "text": "トイレ行けた", "followers": 2000, "language": "ja"},
        {"id": "discouraged", "title": "落ち込んだ日の投稿", "text": "会議でうまく話せなくて、帰ってからも思い出して落ち込んでる。今日はもう何もしたくない。", "followers": 2000, "language": "ja"},
        {"id": "curry", "title": "日常の雑談", "text": "昼ごはんにカレー食べた。辛さを欲張りすぎて水ばっか飲んでたw", "followers": 2000, "language": "ja"},
        {"id": "memory", "title": "昨日の会話を覚えている常連", "text": "昨日ここで話したプレゼン、今日終わった。練習のときほど声は震えなかったかも。", "followers": 200000, "language": "ja", "regulars": regulars},
        {"id": "image", "title": "赤い花の画像付き投稿", "text": "散歩で赤い花を見つけた。写真を撮って、いい気分転換になった！", "followers": 200000, "language": "ja", "regulars": regulars, "image": image},
        {"id": "english", "title": "英語の投稿", "text": "I finally finished the presentation I was nervous about. My voice shook a little, but I got through it!", "followers": 2000, "language": "en"},
    ]
    result = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "models": args.models, "repeats": args.repeats,
        "settings": {"reasoning_effort": "none", "max_completion_tokens": 4096, "hater_enabled": False},
        "pricing_usd_per_million": PRICING,
        "image": "Synthetic flower drawing, 4032x3024 JPEG quality 50",
        "samples": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    try:
        for case in cases:
            for repeat in range(args.repeats):
                for model in args.models:
                    spent = sum(sample.get("estimated_cost_upper_usd", 0) for sample in result["samples"])
                    if spent >= args.max_cost_usd:
                        raise RuntimeError("Benchmark budget threshold reached")
                    seed = 731 + repeat
                    random.seed(seed)
                    main.OPENAI_MODEL = model
                    current.update({"model": model})
                    latest_call.clear()
                    sample = {"case": case["id"], "title": case["title"], "post": case["text"], "language": case["language"], "model": model, "repeat": repeat + 1, "seed": seed}
                    try:
                        with contextlib.redirect_stdout(io.StringIO()):
                            replies, memory_updates = await main.generate_ai_replies(
                                content=case["text"], followers=case["followers"], is_hater_enabled=False,
                                regular_followers=case.get("regulars", []), image_base64=case.get("image"), language=case["language"],
                            )
                        sample.update({**latest_call, "prompt_sha256": current["prompt_sha256"], "replies": replies, "memory_updates": memory_updates})
                        print(f"{case['id']} #{repeat + 1} {model}: input={latest_call['input_tokens']} output={latest_call['output_tokens']} replies={len(replies)} cost_usd={latest_call['estimated_cost_lower_usd']:.6f}..{latest_call['estimated_cost_upper_usd']:.6f}", flush=True)
                    except Exception as error:
                        sample.update({**latest_call, "error_type": type(error).__name__, "http_status": getattr(error, "status_code", None), "error_code": getattr(error, "code", None)})
                        print(f"{case['id']} #{repeat + 1} {model}: {sample['error_type']} status={sample['http_status']} code={sample['error_code']}", flush=True)
                        result["samples"].append(sample)
                        save()
                        raise
                    result["samples"].append(sample)
                    save()
    finally:
        save()
        await client.close()
    print(f"Saved {len(result['samples'])} generations to {args.output}", flush=True)
    write_report(result, args.report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", nargs="+", choices=list(PRICING), default=list(PRICING))
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--max-cost-usd", type=float, default=.50)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/analysis/model-comparison-2026-11-09.json")
    parser.add_argument("--report", type=Path, default=ROOT / "docs/analysis/model-comparison-2026-11-09.md")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.repeats <= 3:
        parser.error("--repeats must be 1..3")
    if args.report_only:
        write_report(json.loads(args.output.read_text(encoding="utf-8")), args.report)
    else:
        asyncio.run(run(args))
