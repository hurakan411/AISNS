import asyncio
import json
import os
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
            patch.object(backend_main.random, "random", return_value=0.0),
        ):
            replies, _ = asyncio.run(backend_main.generate_ai_reply_to_user(request))

        self.assertEqual(capture_client.calls[0]["model"], "gpt-6-luna")
        self.assertEqual(capture_client.calls[0]["reasoning_effort"], "none")
        self.assertIs(capture_client.calls[0]["response_format"], GenerateReplyThreadResponse)
        messages = capture_client.calls[0]["messages"]
        system_prompt = messages[0]["content"]
        self.assertIn(build_reply_style_instruction("en"), system_prompt)
        user_message = messages[1]["content"]
        self.assertIn("OUTPUT LANGUAGE — HIGHEST PRIORITY", system_prompt)
        self.assertIn('profile name is "Mina"', system_prompt)
        self.assertIn("Original post:", user_message)
        self.assertIsNone(re.search(r"[ぁ-んァ-ヶ一-龠]", system_prompt))
        self.assertEqual(replies[0]["author_name"], "Alex")


if __name__ == "__main__":
    unittest.main()
