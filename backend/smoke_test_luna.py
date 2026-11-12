"""Opt-in paid Luna smoke tests against local FastAPI routes; no Render/DB writes.

python3 backend/smoke_test_luna.py --live --output /private/tmp/upme-luna-smoke.json
All posts and images are synthetic. The report contains generated replies, not keys.
"""

import argparse
import asyncio
import base64
import contextlib
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import random
from types import SimpleNamespace
from unittest.mock import patch

from dotenv import load_dotenv
import httpx
from PIL import Image, ImageDraw


def flower_image():
    image = Image.new("RGB", (1024, 768), (225, 232, 226))
    draw = ImageDraw.Draw(image)
    for x in (220, 500, 780):
        draw.line((x, 350, x, 760), fill=(40, 100, 50), width=12)
        for dx, dy in ((-35, 0), (35, 0), (0, -35), (0, 35)):
            draw.ellipse((x+dx-35, 350+dy-35, x+dx+35, 350+dy+35), fill=(210, 35, 55))
        draw.ellipse((x-16, 334, x+16, 366), fill=(240, 190, 45))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=50)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


async def run(output):
    load_dotenv(Path(__file__).with_name(".env"))
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is missing")
    # Never initialize a real database connection for these tests.
    os.environ["SUPABASE_URL"] = ""
    os.environ["SUPABASE_KEY"] = ""
    import main

    assert main.OPENAI_MODEL == "gpt-6-luna"
    client = main.openai_client.with_options(max_retries=0, timeout=60)
    api_calls = []

    async def parse(**kwargs):
        assert kwargs["model"] == "gpt-6-luna"
        assert kwargs["reasoning_effort"] == "none"
        completion = await client.beta.chat.completions.parse(**kwargs)
        assert completion.choices[0].finish_reason == "stop"
        assert completion.choices[0].message.parsed is not None
        api_calls.append({"model": completion.model, "usage": completion.usage.model_dump()})
        return completion

    proxy = SimpleNamespace(beta=SimpleNamespace(chat=SimpleNamespace(
        completions=SimpleNamespace(parse=parse),
    )))
    regulars = [{
        "follower_id": f"smoke-{i}", "author_name": name,
        "avatar_url": f"https://example.invalid/avatar/{i}",
        "memories": ["投稿者は仕事のプレゼンに向けて声に出して練習していた。"],
        "recent_interactions": ["昨日はプレゼン前で緊張していると話していた。"],
    } for i, name in enumerate(("ゆき", "みく", "れん"))]
    base = {"user_id": "synthetic-luna-smoke", "followers": 0, "is_hater_enabled": False}
    image = flower_image()
    cases = []
    for case_id, text in (
        ("ja_work", "今日も１日仕事頑張ったー！！！"),
        ("ja_short", "トイレ行けた"),
        ("ja_sad", "会議でうまく話せなくて、帰ってからも思い出して落ち込んでる。今日はもう何もしたくない。"),
        ("ja_food", "昼ごはんにカレー食べた。辛さを欲張りすぎて水ばっか飲んでたw"),
    ):
        cases.append((case_id, "/api/posts", {**base, "content": text}))
    cases += [
        ("en_work", "/api/posts", {**base, "language": "en", "content": "I finally finished the presentation I was nervous about!"}),
        ("ja_style_history", "/api/posts", {**base, "content": "今日も１日仕事頑張ったー！！！", "recent_ai_replies": [
            "一日やり切ったね。今夜はゆっくり休んでね。",
            "仕事頑張ったんだね。今日は自分を甘やかしてあげて。",
            "一日おつかれさま。温かいものでも飲んでゆっくりしよう。",
        ]}),
        ("en_style_history", "/api/posts", {**base, "language": "en", "content": "Another full workday done!", "recent_ai_replies": [
            "A whole day done. Hope you get a quiet evening.",
            "You worked hard today. Time for some well-earned rest.",
        ]}),
        ("ja_image", "/api/posts", {**base, "content": "散歩で赤い花を見つけた。写真を撮って、いい気分転換になった！", "image_base64": image}),
        ("en_image", "/api/posts", {**base, "language": "en", "content": "Found these red flowers on my walk. Taking a photo was a nice break!", "image_base64": "data:image/jpeg;base64," + image}),
        ("ja_regulars_rank10", "/api/posts", {**base, "followers": 20_000_000, "content": "昨日ここで話したプレゼン、今日終わった。練習のときほど声は震えなかったかも。", "regular_followers": regulars}),
    ]
    for language, text in (("ja", "今日も仕事を頑張った"), ("en", "I worked hard today")):
        cases.append((f"{language}_onboarding", "/api/posts", {
            **base, "language": language, "content": text, "followers": 20_000_000,
            "is_onboarding": True,
        }))
    for language, name, post, comment, reply in (
        ("ja", "ゆき", "プレゼン終わった！", "練習してた分が出たんだね。", "ありがとう！最初は緊張したけど、後半は落ち着いて話せたよ。"),
        ("en", "Mia", "Finished my presentation!", "Glad you made it through.", "Thanks! I was nervous at first, but I settled down halfway through."),
    ):
        cases.append((f"{language}_thread", "/api/replies", {
            "user_id": base["user_id"], "language": language, "post_content": post,
            "ai_author_name": name, "ai_reply_content": comment, "user_reply": reply,
        }))

    report = {"created_at_utc": datetime.now(timezone.utc).isoformat(), "model": main.OPENAI_MODEL,
              "synthetic_fixtures_only": True, "database_access": False, "samples": []}
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with (
            patch.object(main, "openai_client", proxy),
            patch.object(main, "supabase", None),
            patch.object(main, "resolve_avatar_url", side_effect=lambda url: url),
        ):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://local-test") as http:
                for index, (case_id, route, payload) in enumerate(cases):
                    random.seed(100 + index)
                    before = len(api_calls)
                    with contextlib.redirect_stdout(io.StringIO()):
                        response = await http.post(route, json=payload)
                    assert response.status_code == 200, f"{case_id}: HTTP {response.status_code}"
                    data = response.json()
                    assert data["status"] == "success"
                    assert len(api_calls) == before + 1
                    assert 3 <= len(data["replies"]) <= (5 if route == "/api/replies" else 16)
                    for item in data["replies"]:
                        main.ReplySchema.model_validate(item)
                        assert item["content"].strip() and item["author_img"]
                    if route == "/api/replies":
                        assert data["reply"] == data["replies"][0]
                        assert data["reply"]["author_name"] == payload["ai_author_name"]
                    elif payload.get("is_onboarding"):
                        replies = data["replies"]
                        critics = [i for i, item in enumerate(replies) if item["is_hater"]]
                        assert len(critics) == 1
                        i = critics[0]
                        assert len(replies) > i+2 and replies[i+1]["is_defender"] and replies[i+2]["is_defender"]
                        assert replies[i]["author_name"] == replies[i+2]["author_name"]
                    else:
                        assert not any(item["is_hater"] or item["is_defender"] for item in data["replies"])
                    if payload.get("regular_followers"):
                        ids = [item["regular_follower_id"] for item in data["replies"] if item["regular_follower_id"]]
                        assert sorted(ids) == sorted(item["follower_id"] for item in regulars)
                        assert {item["follower_id"] for item in data["memory_updates"]} == set(ids)
                    report["samples"].append({"case": case_id, "route": route, "http_status": response.status_code,
                                              **api_calls[-1], "response": data})
                    print(f"PASS {case_id}: HTTP 200, {len(data['replies'])} replies, model={api_calls[-1]['model']}", flush=True)
    finally:
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        await client.close()
        await main.openai_client.close()
    assert len(report["samples"]) == len(cases)
    print(f"Passed {len(cases)} live API cases. Report: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Explicitly opt into paid OpenAI requests")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.live:
        parser.error("--live is required; this test makes paid API requests")
    asyncio.run(run(args.output))
