import asyncio
import json
import os
import random
import re
import unittest
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("OPENAI_API_KEY", "test-key")

import main as backend_main
from main import (
    GenerateRepliesResponse,
    GenerateReplyThreadResponse,
    PostRequest,
    ReplyToAiRequest,
    ReplySchema,
    build_reply_style_instruction,
    build_reply_diversity_instruction,
    build_recent_reply_context,
    build_user_name_instruction,
    localize_generated_author_names,
    rank_from_followers,
    regular_follower_limit_for_rank,
    sanitize_user_display_name,
)


class PromptCaptureClient:
    def __init__(self, parsed_response):
        self.calls = []

        async def parse(**kwargs):
            self.calls.append(kwargs)
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(parsed=parsed_response))]
            )

        self.beta = SimpleNamespace(
            chat=SimpleNamespace(completions=SimpleNamespace(parse=parse))
        )


class RegularFollowerApiTests(unittest.TestCase):
    def test_avatar_selection_never_waits_for_image_network(self):
        with patch("requests.get", side_effect=AssertionError("Unexpected image download")):
            for url in backend_main.AVATARS + backend_main.HATER_AVATARS:
                self.assertEqual(backend_main.resolve_avatar_url(url), url)

    def test_legacy_post_response_still_contains_avatar_urls_without_image_fetches(self):
        parsed = GenerateRepliesResponse(replies=[ReplySchema(
            author_name="ゆき", content="おつかれさま！", is_hater=False,
            is_defender=False, regular_follower_id=None,
        )], memory_updates=[])
        capture = PromptCaptureClient(parsed)
        with (
            patch.object(backend_main, "openai_client", capture),
            patch("requests.get", side_effect=AssertionError("Reply must not wait for an image")),
        ):
            result = asyncio.run(backend_main.create_post(PostRequest(
                user_id="legacy-test", content="仕事終わった", followers=0,
                is_hater_enabled=False,
            )))
        self.assertEqual(result["status"], "success")
        self.assertNotIn("reaction", result)
        self.assertEqual(len(capture.calls), 1)
        self.assertIn(result["replies"][0]["author_img"], backend_main.AVATARS)
        self.assertEqual(set(result["replies"][0]), {
            "author_name", "author_img", "content", "is_hater", "is_defender", "regular_follower_id",
        })

    def test_viral_followers_are_three_times_and_likes_five_times_rank_maximum(self):
        thresholds = [0, 100, 500, 2000, 10000, 50000, 200000, 1000000, 5000000, 20000000]
        for rank, followers in enumerate(thresholds, 1):
            with patch.object(backend_main.random, "random", return_value=0.0):
                reaction = backend_main.build_post_reaction(followers)
            maximum = backend_main.POST_FOLLOWER_RANGES[rank - 1][1]
            self.assertEqual(reaction, {"is_viral": True, "rank": rank,
                                       "likes": maximum * 7 * 5, "follower_gain": maximum * 3})
            with patch.object(backend_main.random, "random", return_value=0.99):
                normal = backend_main.build_post_reaction(followers)
            minimum = backend_main.POST_FOLLOWER_RANGES[rank - 1][0]
            self.assertFalse(normal["is_viral"])
            self.assertLessEqual(minimum, normal["follower_gain"])
            self.assertLessEqual(normal["follower_gain"], maximum)
            self.assertLessEqual(normal["likes"], maximum * 7)

    def test_viral_endpoint_doubles_replies_in_one_generation_including_image(self):
        for followers, count in ((0, 10), (20_000_000, 32)):
            for language in ("ja", "en"):
                parsed = GenerateRepliesResponse(replies=[ReplySchema(
                    author_name=f"AI{i}", content=f"reply {i}", is_hater=False,
                    is_defender=False, regular_follower_id=None,
                ) for i in range(count)], memory_updates=[])
                capture = PromptCaptureClient(parsed)
                with (patch.object(backend_main, "openai_client", capture),
                      patch.object(backend_main, "supabase", None),
                      patch.object(backend_main, "resolve_avatar_url", return_value="https://example.test/avatar"),
                      patch.object(backend_main.random, "random", return_value=0.0)):
                    result = asyncio.run(backend_main.create_post(PostRequest(
                        user_id="test", content="Test post", followers=followers,
                        supports_viral_posts=True, is_hater_enabled=False,
                        language=language, image_base64="test-image",
                    )))
                self.assertEqual(len(capture.calls), 1)
                self.assertEqual(len(result["replies"]), count)
                self.assertTrue(result["reaction"]["is_viral"])
                schema = capture.calls[0]["response_format"].model_json_schema()["properties"]["replies"]
                self.assertEqual((schema["minItems"], schema["maxItems"]), (count, count))
                self.assertEqual(capture.calls[0]["messages"][1]["content"][1]["type"], "image_url")

    def test_old_clients_do_not_draw_viral_rewards(self):
        from unittest.mock import AsyncMock
        for options in ({}, {"is_onboarding": True}):
            generate = AsyncMock(return_value=([], []))
            with (patch.object(backend_main, "generate_ai_replies", generate),
                  patch.object(backend_main, "build_post_reaction") as draw):
                result = asyncio.run(backend_main.create_post(PostRequest(
                    user_id="test", content="post", followers=0, **options)))
            draw.assert_not_called()
            self.assertNotIn("reaction", result)
            self.assertFalse(generate.call_args.kwargs["is_viral"])

    def test_onboarding_is_guaranteed_viral_in_a_single_batch(self):
        parsed = GenerateRepliesResponse(replies=[ReplySchema(
            author_name=f"AI{i}", content=f"reply {i}", is_hater=False,
            is_defender=False, regular_follower_id=None,
        ) for i in range(32)], memory_updates=[])
        capture = PromptCaptureClient(parsed)
        with (patch.object(backend_main, "openai_client", capture),
              patch.object(backend_main, "supabase", None),
              patch.object(backend_main, "resolve_avatar_url", return_value="https://example.test/avatar"),
              patch.object(backend_main.random, "random", return_value=0.99)):
            result = asyncio.run(backend_main.create_post(PostRequest(
                user_id="test", content="first post", followers=20_000_000,
                is_onboarding=True, supports_viral_posts=True,
            )))
        self.assertEqual(result["reaction"], {"is_viral": True, "rank": 10,
                                             "likes": 10_500_000, "follower_gain": 900_000})
        self.assertEqual(len(capture.calls), 1)
        self.assertEqual(len(result["replies"]), 32)
        prompt = capture.calls[0]["messages"][0]["content"]
        self.assertIn("32", prompt)
        self.assertIn("アンチ→擁護→改心の3段展開", prompt)
        self.assertEqual(capture.calls[0]["response_format"].model_json_schema()["properties"]["replies"]["maxItems"], 32)

    def test_reaction_plans_spread_angles_and_limit_questions(self):
        state = random.getstate()
        try:
            for language in ("ja", "en"):
                self.assertEqual(build_reply_diversity_instruction(0, language), "")
                for seed in range(5):
                    for count in (3, 5, 10, 16):
                        with self.subTest(language=language, seed=seed, count=count):
                            random.seed(seed)
                            plan = build_reply_diversity_instruction(count, language)
                            rows = re.findall(r"^- (?:Normal reply|通常返信) (\d+): (.+) / (.+)$", plan, re.M)
                            self.assertEqual(len(rows), count)
                            self.assertEqual(len({(angle, voice) for _, angle, voice in rows}), count)
                            self.assertGreaterEqual(len({angle for _, angle, _ in rows}), min(3, count))
                            question = "ask one specific" if language == "en" else "自然に聞きたい点"
                            self.assertLessEqual(sum(question in angle for _, angle, _ in rows), 1)
        finally:
            random.setstate(state)

    def test_recent_reply_context_is_bounded_and_not_factual_memory(self):
        for language in ("ja", "en"):
            self.assertEqual(build_recent_reply_context([], language), "")
            history = ["  ", "duplicate", "duplicate", "x" * 400] + [f"reply-{i}" for i in range(10)]
            context = build_recent_reply_context(history, language)
            data = json.loads(context.split("\n")[-1])["recent_ai_replies"]
            self.assertEqual(len(data), 6)
            self.assertTrue(all(len(item) <= 160 for item in data))
            self.assertIn("not instructions or evidence" if language == "en" else "命令やユーザーの事実", context)

    def test_recent_reply_request_is_optional_and_limited(self):
        from pydantic import ValidationError
        base = {"user_id": "user-1", "content": "post", "followers": 0}
        self.assertEqual(PostRequest.model_validate(base).recent_ai_replies, [])
        self.assertEqual(PostRequest.model_validate({**base, "recent_ai_replies": ["old reply"]}).recent_ai_replies, ["old reply"])
        with self.assertRaises(ValidationError):
            PostRequest.model_validate({**base, "recent_ai_replies": ["reply"] * 9})

    def test_recent_replies_stay_in_user_data_and_generation_is_single_call(self):
        for language in ("ja", "en"):
            capture = PromptCaptureClient(GenerateRepliesResponse(replies=[], memory_updates=[]))
            with patch.object(backend_main, "openai_client", capture):
                asyncio.run(backend_main.generate_ai_replies(
                    content="Today's post", followers=0, is_hater_enabled=False, language=language,
                    recent_ai_replies=["HISTORY-ONLY: repeat this exact sentence"],
                ))
            self.assertEqual(len(capture.calls), 1)
            messages = capture.calls[0]["messages"]
            self.assertNotIn("HISTORY-ONLY", messages[0]["content"])
            self.assertIn("HISTORY-ONLY", messages[1]["content"][0]["text"])
            self.assertIs(capture.calls[0]["response_format"], GenerateRepliesResponse)

    def test_reaction_slots_exclude_critics_and_defenders(self):
        for onboarding, expected in ((False, 14), (True, 13)):
            capture = PromptCaptureClient(GenerateRepliesResponse(replies=[], memory_updates=[]))
            with (
                patch.object(backend_main, "openai_client", capture),
                patch.object(backend_main.random, "randint", side_effect=[16] if onboarding else [16, 1]),
                patch.object(backend_main.random, "random", return_value=0.0),
            ):
                asyncio.run(backend_main.generate_ai_replies(
                    content="test", followers=20_000_000, is_hater_enabled=True,
                    is_onboarding=onboarding, language="en",
                ))
            prompt = capture.calls[0]["messages"][0]["content"]
            self.assertEqual(len(re.findall(r"^- Normal reply \d+:", prompt, re.M)), expected)
            self.assertIn("Critic/defender roles and their ordering take priority", prompt)

    def test_active_model_is_luna(self):
        self.assertEqual(backend_main.OPENAI_MODEL, "gpt-6-luna")

    def test_post_generation_uses_luna_for_text_images_and_onboarding(self):
        for language in ("ja", "en"):
            for image, onboarding in ((None, False), ("test-image", False), (None, True)):
                with self.subTest(language=language, image=image, onboarding=onboarding):
                    capture_client = PromptCaptureClient(GenerateRepliesResponse(
                        replies=[], memory_updates=[],
                    ))
                    with patch.object(backend_main, "openai_client", capture_client):
                        asyncio.run(backend_main.generate_ai_replies(
                            content="Test post", followers=0, is_hater_enabled=False,
                            language=language, image_base64=image, is_onboarding=onboarding,
                        ))
                    call = capture_client.calls[0]
                    self.assertEqual(call["model"], "gpt-6-luna")
                    self.assertEqual(call["reasoning_effort"], "none")
                    self.assertIs(call["response_format"], GenerateRepliesResponse)
                    prompt = call["messages"][0]["content"]
                    self.assertIn(build_reply_style_instruction(language, bool(image)), prompt)
                    self.assertNotIn("3〜5個以上", prompt)
                    self.assertNotIn("may use repeated emoji", prompt)
                    if image:
                        self.assertEqual(call["messages"][1]["content"][1], {
                            "type": "image_url",
                            "image_url": {"url": "data:image/jpeg;base64,test-image"},
                        })

    def test_reply_style_distinguishes_images_and_thread_context_in_both_languages(self):
        for language in ("ja", "en"):
            with self.subTest(language=language):
                attached = build_reply_style_instruction(language, True)
                absent = build_reply_style_instruction(language, False)
                thread = build_reply_style_instruction(language)
                self.assertNotEqual(attached, absent)
                self.assertNotEqual(attached, thread)
                self.assertIn("1返信につき" if language == "ja" else "at most one", attached)
                self.assertIn("すでに添付" if language == "ja" else "already attached", attached)
                self.assertIn("画像は渡されていない" if language == "ja" else "No image", absent)
                self.assertIn("テキストだけ" if language == "ja" else "text only", thread)

    def test_usage_log_uses_luna_rates_and_cache_write_estimates(self):
        for writes, expected, upper in ((None, 0.000132, 0.000152), (400, 0.000142, 0.000142)):
            with self.subTest(cache_write_tokens=writes):
                completion = SimpleNamespace(model="gpt-6-luna", usage=SimpleNamespace(
                    prompt_tokens=1000, completion_tokens=100,
                    prompt_tokens_details=SimpleNamespace(cached_tokens=200, cache_write_tokens=writes),
                    completion_tokens_details=SimpleNamespace(reasoning_tokens=0),
                ))
                with (
                    patch.object(backend_main, "LOG_OPENAI_USAGE", True),
                    patch.object(backend_main.logger, "info") as logged,
                ):
                    backend_main.log_openai_usage(completion, "post_replies", 0)
                payload = json.loads(logged.call_args.args[1])
                self.assertAlmostEqual(payload["estimated_cost_usd"], expected)
                self.assertAlmostEqual(payload["estimated_cost_upper_usd"], upper)

    def test_old_post_payload_remains_compatible(self):
        request = PostRequest(user_id="user-1", content="hello", followers=0)
        self.assertEqual(request.regular_followers, [])
        self.assertEqual(request.language, "ja")
        self.assertIsNone(request.user_display_name)

    def test_single_user_reply_payload_is_parsed(self):
        request = ReplyToAiRequest.model_validate({
            "user_id": "user-1",
            "post_content": "今日はカフェに行った",
            "ai_author_name": "ミカ",
            "ai_reply_content": "窓際の席が良さそう！",
            "user_reply": "窓際が一番落ち着いたよ",
        })
        self.assertEqual(request.ai_author_name, "ミカ")
        self.assertFalse(request.ai_is_hater)
        self.assertIsNone(request.target_regular_follower)
        self.assertIsNone(request.user_display_name)

    def test_profile_name_is_sanitized_for_prompt_context(self):
        self.assertEqual(sanitize_user_display_name("  Mina\nSmith  "), "Mina Smith")
        self.assertIsNone(sanitize_user_display_name("You"))
        self.assertIsNone(sanitize_user_display_name("あなた"))
        self.assertEqual(len(sanitize_user_display_name("a" * 50)), 30)

    def test_profile_name_instruction_limits_mentions(self):
        japanese = build_user_name_instruction("ja", "みな", True)
        english = build_user_name_instruction("en", "Mina", True)
        skipped = build_user_name_instruction("en", "Mina", False)
        self.assertIn("1人だけ", japanese)
        self.assertIn("アンチ", japanese)
        self.assertIn("Exactly one", english)
        self.assertIn("never let a critic use it", english)
        self.assertIn("do not address the user by name", skipped)

    def test_profile_name_quota_scales_with_reply_count(self):
        for reply_count, expected in ((3, 1), (5, 1), (10, 2), (16, 3), (32, 6)):
            with self.subTest(reply_count=reply_count):
                japanese = build_user_name_instruction("ja", "みな", True, reply_count)
                english = build_user_name_instruction("en", "Mina", True, reply_count)
                self.assertIn(f"{expected}人だけ", japanese)
                self.assertIn("5件に1件", japanese)
                self.assertIn("must naturally address", english)
                self.assertIn("one in five", english)
                self.assertIn("Exactly one" if expected == 1 else f"Exactly {expected}", english)

    def test_missing_profile_name_never_requests_a_name(self):
        for name in (None, "", "あなた", "You"):
            for language in ("ja", "en"):
                prompt = build_user_name_instruction(language, name, True, 32)
                self.assertIn("推測・創作しない" if language == "ja" else "Do not invent", prompt)

    def test_post_name_instruction_no_longer_depends_on_random_gate(self):
        parsed = GenerateRepliesResponse(replies=[ReplySchema(
            author_name="Mia", content="Mina, glad you got that break!",
            is_hater=False, is_defender=False, regular_follower_id=None,
        )], memory_updates=[])
        capture = PromptCaptureClient(parsed)
        with (
            patch.object(backend_main, "openai_client", capture),
            patch.object(backend_main, "resolve_avatar_url", return_value="https://example.com/avatar.png"),
            patch.object(backend_main.random, "random", return_value=0.99),
        ):
            asyncio.run(backend_main.generate_ai_replies(
                content="I finally took a break", followers=0, is_hater_enabled=False,
                language="en", user_display_name="Mina",
            ))
        self.assertEqual(len(capture.calls), 1)
        self.assertIn("must naturally address", capture.calls[0]["messages"][0]["content"])

    def test_reply_thread_payload_includes_other_ai_context(self):
        request = ReplyToAiRequest.model_validate({
            "user_id": "user-1",
            "post_content": "今日はカフェに行った",
            "ai_author_name": "ミカ",
            "ai_reply_content": "窓際の席が良さそう！",
            "user_reply": "窓際が一番落ち着いたよ",
            "other_ai_replies": [{
                "author_name": "ゆき",
                "content": "ラテも気になる",
                "is_hater": False,
                "is_defender": False,
            }],
        })
        self.assertEqual(len(request.other_ai_replies), 1)
        self.assertEqual(request.other_ai_replies[0].author_name, "ゆき")

    def test_reply_thread_response_supports_multiple_ai_replies(self):
        response = GenerateReplyThreadResponse.model_validate({
            "replies": [
                {
                    "author_name": "ミカ",
                    "content": "窓際って落ち着くよね",
                    "is_hater": False,
                    "is_defender": False,
                    "regular_follower_id": "mika-1",
                },
                {
                    "author_name": "ゆき",
                    "content": "その話、私も気になってた",
                    "is_hater": False,
                    "is_defender": False,
                    "regular_follower_id": None,
                },
            ],
            "memory_updates": [],
        })
        self.assertEqual(len(response.replies), 2)

    def test_regular_follower_payload_is_parsed(self):
        request = PostRequest.model_validate({
            "user_id": "user-1",
            "content": "今日はカフェに行った",
            "followers": 2_000,
            "regular_followers": [{
                "follower_id": "mika-1",
                "author_name": "ミカ",
                "avatar_url": "https://example.com/mika.png",
                "memories": ["ユーザーはカフェが好き"],
                "recent_interactions": ["前回は仕事の話をした"],
            }],
        })
        self.assertEqual(request.regular_followers[0].follower_id, "mika-1")

    def test_rank_based_limits(self):
        cases = [
            (0, 1),
            (500, 1),
            (2_000, 2),
            (50_000, 2),
            (200_000, 3),
            (20_000_000, 3),
        ]
        for followers, expected_limit in cases:
            rank = rank_from_followers(followers)
            self.assertEqual(regular_follower_limit_for_rank(rank), expected_limit)

    def test_structured_response_supports_memory_updates(self):
        response = GenerateRepliesResponse.model_validate({
            "replies": [{
                "author_name": "ミカ",
                "content": "前に話していたカフェ、今回も良さそう！",
                "is_hater": False,
                "is_defender": False,
                "regular_follower_id": "mika-1",
            }],
            "memory_updates": [{
                "follower_id": "mika-1",
                "new_memories": ["ユーザーは新しいカフェを見つけた"],
                "interaction_summary": "新しく見つけたカフェについて話した",
            }],
        })
        self.assertEqual(response.replies[0].regular_follower_id, "mika-1")
        self.assertEqual(response.memory_updates[0].follower_id, "mika-1")

    def test_non_regular_ai_names_are_localized_to_japanese(self):
        replies = [
            ReplySchema(
                author_name="miku_23",
                content="内容1",
                is_hater=True,
                is_defender=False,
                regular_follower_id=None,
            ),
            ReplySchema(
                author_name="miku_23",
                content="内容2",
                is_hater=False,
                is_defender=True,
                regular_follower_id=None,
            ),
            ReplySchema(
                author_name="ren",
                content="内容3",
                is_hater=False,
                is_defender=False,
                regular_follower_id="regular-1",
            ),
        ]

        localize_generated_author_names(replies)

        self.assertEqual(replies[0].author_name, replies[1].author_name)
        self.assertRegex(replies[0].author_name, r"^[ぁ-んァ-ヶ一-龠々ー・\s]+$")
        self.assertEqual(replies[2].author_name, "ren")

    def test_non_regular_ai_names_are_localized_to_english(self):
        replies = [
            ReplySchema(
                author_name="みく_23",
                content="Love that night breeze.",
                is_hater=False,
                is_defender=False,
                regular_follower_id=None,
            ),
            ReplySchema(
                author_name="みく_23",
                content="It sounds peaceful.",
                is_hater=False,
                is_defender=False,
                regular_follower_id=None,
            ),
            ReplySchema(
                author_name="ゆき",
                content="Same regular follower.",
                is_hater=False,
                is_defender=False,
                regular_follower_id="regular-1",
            ),
        ]

        localize_generated_author_names(replies, "en")

        self.assertEqual(replies[0].author_name, replies[1].author_name)
        self.assertRegex(replies[0].author_name, r"^[A-Za-z][A-Za-z '\-]+$")
        self.assertEqual(replies[2].author_name, "ゆき")

    def test_english_post_generation_uses_an_english_only_prompt(self):
        parsed_response = GenerateRepliesResponse.model_validate({
            "replies": [{
                "author_name": "Mia",
                "content": "That quiet morning sounds genuinely restorative.",
                "is_hater": False,
                "is_defender": False,
                "regular_follower_id": None,
            }],
            "memory_updates": [],
        })
        capture_client = PromptCaptureClient(parsed_response)

        with (
            patch.object(backend_main, "openai_client", capture_client),
            patch.object(backend_main, "resolve_avatar_url", return_value="https://example.com/avatar.png"),
            patch.object(backend_main.random, "random", return_value=0.0),
        ):
            asyncio.run(backend_main.generate_ai_replies(
                content="A quiet morning walk helped me reset.",
                followers=0,
                is_hater_enabled=False,
                language="en",
                user_display_name="Mina",
            ))

        self.assertEqual(capture_client.calls[0]["model"], "gpt-6-luna")
        self.assertEqual(capture_client.calls[0]["reasoning_effort"], "none")
        messages = capture_client.calls[0]["messages"]
        system_prompt = messages[0]["content"]
        user_text = messages[1]["content"][0]["text"]
        self.assertIn("OUTPUT LANGUAGE — HIGHEST PRIORITY", system_prompt)
        self.assertIn("English-language social timeline", system_prompt)
        self.assertIn('profile name is "Mina"', system_prompt)
        self.assertIn("Exactly one suitable", system_prompt)
        self.assertIn("User's post:", user_text)
        self.assertIsNone(re.search(r"[ぁ-んァ-ヶ一-龠]", system_prompt))

    def test_english_reply_thread_uses_an_english_only_prompt(self):
        parsed_response = GenerateReplyThreadResponse.model_validate({
            "replies": [
                {
                    "author_name": "Alex",
                    "content": "Yeah, the slower pace was exactly what I meant.",
                    "is_hater": False,
                    "is_defender": False,
                    "regular_follower_id": None,
                },
                {
                    "author_name": "Mia",
                    "content": "Morning walks really do change the whole day.",
                    "is_hater": False,
                    "is_defender": False,
                    "regular_follower_id": None,
                },
                {
                    "author_name": "Noah",
                    "content": "Was it quiet because you went out early?",
                    "is_hater": False,
                    "is_defender": False,
                    "regular_follower_id": None,
                },
            ],
            "memory_updates": [],
        })
        capture_client = PromptCaptureClient(parsed_response)
        request = ReplyToAiRequest.model_validate({
            "user_id": "user-1",
            "post_content": "A quiet morning walk helped me reset.",
            "ai_author_name": "Alex",
            "ai_reply_content": "That sounds like a good way to slow down.",
            "user_reply": "It was. I left my phone in my pocket the whole time.",
            "language": "en",
            "user_display_name": "Mina",
        })

        with (
            patch.object(backend_main, "openai_client", capture_client),
            patch.object(backend_main, "resolve_avatar_url", return_value="https://example.com/avatar.png"),
            patch.object(backend_main.random, "random", return_value=0.99),
        ):
            replies, _ = asyncio.run(backend_main.generate_ai_reply_to_user(request))

        self.assertEqual(capture_client.calls[0]["model"], "gpt-6-luna")
        self.assertEqual(capture_client.calls[0]["reasoning_effort"], "none")
        self.assertIs(capture_client.calls[0]["response_format"], GenerateReplyThreadResponse)
        messages = capture_client.calls[0]["messages"]
        system_prompt = messages[0]["content"]
        self.assertIn(build_reply_style_instruction("en"), system_prompt)
        self.assertIn("Additional participant 1:", system_prompt)
        self.assertIn("rather than echo the target", system_prompt)
        user_message = messages[1]["content"]
        self.assertIn("OUTPUT LANGUAGE — HIGHEST PRIORITY", system_prompt)
        self.assertIn('profile name is "Mina"', system_prompt)
        self.assertIn("Exactly one suitable normal or regular follower must naturally address", system_prompt)
        self.assertIn("Original post:", user_message)
        self.assertIsNone(re.search(r"[ぁ-んァ-ヶ一-龠]", system_prompt))
        self.assertEqual(replies[0]["author_name"], "Alex")


if __name__ == "__main__":
    unittest.main()
