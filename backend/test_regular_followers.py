import os
import unittest

os.environ.setdefault("OPENAI_API_KEY", "test-key")

from main import (
    GenerateRepliesResponse,
    PostRequest,
    rank_from_followers,
    regular_follower_limit_for_rank,
)


class RegularFollowerApiTests(unittest.TestCase):
    def test_old_post_payload_remains_compatible(self):
        request = PostRequest(user_id="user-1", content="hello", followers=0)
        self.assertEqual(request.regular_followers, [])

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


if __name__ == "__main__":
    unittest.main()
