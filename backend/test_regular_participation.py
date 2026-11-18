import os
import asyncio
import unittest
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("OPENAI_API_KEY", "test-key")
import main


class RegularParticipationTests(unittest.TestCase):
    def setUp(self):
        self.regulars = [SimpleNamespace(follower_id=str(i)) for i in range(4)]

    def test_probability_and_boundary(self):
        self.assertEqual(main.REGULAR_REPLY_PARTICIPATION_PROBABILITY, 0.70)
        with patch.object(main.random, "random", side_effect=[0, 0.699999, 0.70]):
            self.assertEqual(main.select_regular_participants(self.regulars, 3), self.regulars[:2])

    def test_draws_are_independent_and_nobody_is_forced_to_appear(self):
        with patch.object(main.random, "random", return_value=0.99) as draw:
            self.assertEqual(main.select_regular_participants(self.regulars, 3), [])
            self.assertEqual(draw.call_count, 3)
        with patch.object(main.random, "random", return_value=0.1):
            self.assertEqual(main.select_regular_participants(self.regulars, 3), self.regulars[:3])

    def test_deduplicate_and_cap_before_draw_no_replacement(self):
        followers = [self.regulars[0], self.regulars[0], *self.regulars[1:]]
        with patch.object(main.random, "random", side_effect=[0.9, 0.1]) as draw:
            self.assertEqual(main.select_regular_participants(followers, 2), [self.regulars[1]])
            self.assertEqual(draw.call_count, 2)

    def test_onboarding_empty_and_no_slots_do_not_draw(self):
        with patch.object(main.random, "random") as draw:
            self.assertEqual(main.select_regular_participants(self.regulars, 3, is_onboarding=True), [])
            self.assertEqual(main.select_regular_participants(self.regulars, 0), [])
            self.assertEqual(main.select_regular_participants([], 3), [])
            draw.assert_not_called()

    def test_profiles_update_only_when_regular_replies(self):
        for language in ("ja", "en"):
            for attendance in (0.0, 0.99):
                with self.subTest(language=language, attendance=attendance):
                    follower = main.RegularFollowerContext(follower_id="yuki", author_name="ゆき",
                        avatar_url="https://example.test/avatar", memories=["OWN-HISTORY"], character_id="v1-03")
                    parsed = main.GenerateRepliesResponse.model_validate({
                        "replies": [{"author_name": "ゆき", "content": "Nice!", "is_hater": False,
                                     "is_defender": False, "regular_follower_id": "yuki"}],
                        "memory_updates": [{"follower_id": id, "new_memories": ["new fact"],
                            "interaction_summary": "an exchange", "impression": "positive profile",
                            "impression_summary": "positive overview"} for id in ("yuki", "unknown")]})
                    calls = []
                    async def parse(**kwargs):
                        calls.append(kwargs)
                        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(parsed=parsed))])
                    client = SimpleNamespace(beta=SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(parse=parse))))
                    with (patch.object(main, "openai_client", client),
                          patch.object(main.random, "random", return_value=attendance),
                          patch.object(main, "resolve_avatar_url", return_value="https://example.test/avatar")):
                        replies, updates = asyncio.run(main.generate_ai_replies(
                            "new post", 0, False, regular_followers=[follower], language=language))
                    self.assertEqual(len(calls), 1)
                    if attendance == 0.99:
                        self.assertIsNone(replies[0]["regular_follower_id"])
                        self.assertEqual(updates, [])
                        prompt = calls[0]["messages"][0]["content"]
                        self.assertNotIn("OWN-HISTORY", prompt)
                    else:
                        self.assertEqual(len(updates), 1)
                        self.assertEqual(updates[0]["impression"], "positive profile")
                        self.assertEqual(replies[0]["regular_follower_id"], "yuki")
                        self.assertEqual(updates[0]["new_memories"], ["new fact"])
