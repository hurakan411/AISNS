"""Local, opt-in paid API benchmark. Stores token metadata, never prompts/replies.

Run: python3 backend/measure_ai_usage.py --repeats 3 --max-cost-usd 0.50
Uses backend/.env. Calls the existing generators directly; no Render/DB writes.
"""

import argparse
import asyncio
import base64
import contextlib
import io
import json
import logging
import os
from pathlib import Path
import random
from datetime import datetime, timezone

from dotenv import load_dotenv
from PIL import Image, ImageDraw


BACKEND = Path(__file__).resolve().parent


class UsageCapture(logging.Handler):
    def __init__(self):
        super().__init__()
        self.records = []

    def emit(self, record):
        message = record.getMessage()
        if message.startswith("openai_usage "):
            self.records.append(json.loads(message.removeprefix("openai_usage ")))


def test_image(width, height):
    """Synthetic flower scene, JPEG quality 50 like the app; no private photos."""
    image = Image.new("RGB", (width, height), (220, 230, 225))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, height * 0.65, width, height), fill=(92, 128, 80))
    for x, y in [(0.2, 0.33), (0.45, 0.49), (0.68, 0.3), (0.83, 0.52)]:
        cx, cy, r = int(width * x), int(height * y), int(width * 0.045)
        draw.line((cx, cy, cx, height), fill=(38, 88, 40), width=max(2, width // 120))
        for dx, dy in [(-r, 0), (r, 0), (0, -r), (0, r)]:
            draw.ellipse((cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r), fill=(205, 42, 65))
        draw.ellipse((cx - r // 2, cy - r // 2, cx + r // 2, cy + r // 2), fill=(238, 188, 55))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=50)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def regular_contexts(main):
    facts = [
        "散歩と写真撮影が好きで、公園に咲く花を見つけると写真を撮っている。",
        "仕事が終わった後に外を歩くと、気持ちの切り替えになると話していた。",
        "休日はカフェで本を読みながら、ゆっくり過ごす時間を楽しんでいる。",
        "最近はパン作りを試していて、焼き上がりの香りが好きだと話していた。",
        "映画を観た感想を投稿して、好きな場面について話すことがある。",
        "赤い花や夕焼けなど、日常の小さなきれいなものを写真に残している。",
        "疲れている日も簡単な料理を作るなど、自分のペースで過ごしている。",
        "旅行の計画を立てることが好きで、景色のよい場所に関心がある。",
    ]
    recent = [
        "投稿では仕事帰りの散歩について話し、常連は具体的な風景に触れて自然に返信した。",
        "投稿では公園の花の写真について話し、常連は色や構図について感想を返した。",
        "投稿では休日の過ごし方を話し、常連はこれまでの話題とのつながりに少し触れた。",
    ]
    # Exercise the current 8 memories / 3 recent interactions at their character caps.
    return [
        main.RegularFollowerContext(
            follower_id=f"local-benchmark-{i}", author_name=name,
            avatar_url=f"https://example.invalid/avatar/{i}",
            memories=[(fact * 6)[:160] for fact in facts],
            recent_interactions=[(item * 6)[:180] for item in recent],
        )
        for i, name in enumerate(["ゆき", "みく", "れん"], start=1)
    ]


def seeds_for_counts(low, high, counts):
    return [next(seed for seed in range(1000) if random.Random(seed).randint(low, high) == count) for count in counts]


async def run(args):
    load_dotenv(BACKEND / ".env")
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is missing from backend/.env or the environment")
    os.environ["LOG_OPENAI_USAGE"] = "true"
    import main

    # Avatar redirects are unrelated to LLM token usage. Avoid those extra requests.
    main.resolve_avatar_url = lambda url: url
    main.openai_client = main.openai_client.with_options(max_retries=0, timeout=90)
    capture = UsageCapture()
    main.logger.handlers = [capture]
    main.logger.setLevel(logging.INFO)
    main.logger.propagate = False

    small_image = test_image(1024, 768)
    large_image = test_image(4032, 3024)
    regulars = regular_contexts(main)
    text = "散歩で赤い花を見つけた。写真を撮って、いい気分転換になった！"
    cases = [
        ("text_rank1", 0, None, [], False, False),
        ("image1024_rank1", 0, small_image, [], False, False),
        ("image4032_rank1", 0, large_image, [], False, False),
        ("text_rank10_full_memory", 20_000_000, None, regulars, True, False),
        ("image4032_rank10_full_memory", 20_000_000, large_image, regulars, True, False),
        ("onboarding", 20_000_000, None, [], True, True),
    ]
    result = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "model_requested": main.OPENAI_MODEL,
        "pricing_usd_per_million_tokens": {"input": 0.75, "cached_input": 0.075, "output": 4.5},
        "image_fixture": "Synthetic red-flower drawing, JPEG quality 50; same scene at two resolutions",
        "memory_fixture": "3 regulars, each with 8x160-character memories and 3x180-character recent interactions",
        "samples": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    async def measure(case, index, call, **metadata):
        spent = sum(item.get("estimated_cost_usd", 0) for item in result["samples"])
        if spent >= args.max_cost_usd:
            raise RuntimeError("Local benchmark cost budget reached")
        before = len(capture.records)
        with contextlib.redirect_stdout(io.StringIO()):
            replies, updates = await call()
        if len(capture.records) != before + 1:
            raise RuntimeError("Expected exactly one usage record for this generation")
        sample = {"case": case, "sample": index + 1, **metadata, **capture.records[-1], "reply_count": len(replies), "memory_update_count": len(updates)}
        sample["uncached_cost_usd"] = round((sample["input_tokens"] * 0.75 + sample["output_tokens"] * 4.5) / 1_000_000, 8)
        result["samples"].append(sample)
        save()
        print(f"{case} #{index + 1}: input={sample['input_tokens']} output={sample['output_tokens']} cached={sample['cached_input_tokens']} replies={len(replies)} cost_usd={sample['estimated_cost_usd']:.8f}", flush=True)
        return replies

    low_seeds = seeds_for_counts(3, 5, [3, 4, 5])
    high_seeds = seeds_for_counts(10, 16, [10, 13, 16])
    try:
        for case, followers, image, memories, hater, onboarding in cases:
            for index in range(args.repeats):
                seed = (low_seeds if followers == 0 else high_seeds)[index % 3]
                random.seed(seed)
                replies = await measure(
                    case, index,
                    lambda: main.generate_ai_replies(content=text, followers=followers, is_hater_enabled=hater, is_onboarding=onboarding, image_base64=image, regular_followers=memories, language="ja"),
                    random_seed=seed, rank=main.rank_from_followers(followers), regular_count=len(memories),
                    image_dimensions=([1024, 768] if image is small_image else [4032, 3024]) if image else None,
                    is_onboarding=onboarding,
                )
                if case == "image4032_rank10_full_memory":
                    target = next(reply for reply in replies if reply.get("regular_follower_id"))
                    target_regular = next(f for f in regulars if f.follower_id == target["regular_follower_id"])
                    request = main.ReplyToAiRequest(
                        user_id="local-cost-benchmark", post_content=text,
                        ai_author_name=target["author_name"], ai_reply_content=target["content"],
                        user_reply="ありがとう！赤い花を見てたら、また明日も散歩してみたくなった。",
                        target_regular_follower=target_regular, regular_followers=regulars,
                        other_ai_replies=[main.ThreadReplyContext(author_name=reply["author_name"], content=reply["content"], regular_follower_id=reply.get("regular_follower_id")) for reply in replies if reply is not target][:8],
                    )
                    random.seed(seed)
                    await measure("reply_thread_full_memory", index, lambda: main.generate_ai_reply_to_user(request), regular_count=3, image_dimensions=None)
    finally:
        save()
        await main.openai_client.close()

    print(f"Saved {len(result['samples'])} samples to {args.output}", flush=True)
    print(f"Total estimated API cost: ${sum(item['estimated_cost_usd'] for item in result['samples']):.6f}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--max-cost-usd", type=float, default=0.50)
    parser.add_argument("--output", type=Path, default=BACKEND.parent / "docs/analysis/token-cost-2026-11-09.json")
    arguments = parser.parse_args()
    if not 1 <= arguments.repeats <= 5:
        parser.error("--repeats must be between 1 and 5")
    asyncio.run(run(arguments))
