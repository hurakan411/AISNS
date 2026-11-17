import json
import random
import unittest

from character_catalog import CHARACTERS, BY_ID, build_character_prompt, select_characters


class CharacterCatalogTests(unittest.TestCase):
    def test_thirty_stable_unique_definitions(self):
        self.assertEqual(len(CHARACTERS), 30)
        self.assertEqual(len(BY_ID), 30)
        self.assertEqual(len({c.label for c in CHARACTERS}), 30)
        self.assertEqual(len({(c.voice_ja, c.focus_ja) for c in CHARACTERS}), 30)

    def test_saved_regular_ids_survive_new_general_selection(self):
        fixed = json.loads(json.dumps(["v1-04", "v1-07", "v1-09"]))
        for seed in range(20):
            selected = select_characters(5, fixed_ids=fixed, rng=random.Random(seed))
            self.assertEqual([c.id for c in selected[:3]], fixed)
            self.assertEqual(len({c.id for c in selected}), 5)

    def test_only_selected_definitions_enter_each_language_prompt(self):
        for language in ("ja", "en"):
            selected = CHARACTERS[:5]
            prompt = build_character_prompt(selected, language)
            rows = json.loads(prompt.strip().splitlines()[-1])
            self.assertEqual([r["character_id"] for r in rows], [c.id for c in selected])
            for c in CHARACTERS[5:]:
                self.assertNotIn(c.id, prompt)
                self.assertNotIn(c.voice_en if language == "en" else c.voice_ja, prompt)

    def test_invalid_selections_and_misaligned_regular_ids_fail(self):
        for count, fixed in ((31, []), (-1, []), (1, ["v1-01", "v1-02"])):
            with self.assertRaises(ValueError):
                select_characters(count, fixed_ids=fixed)
        with self.assertRaises(KeyError):
            select_characters(1, fixed_ids=["unknown"])
        with self.assertRaises(ValueError):
            build_character_prompt(CHARACTERS[:2], regular_ids=["one"])

    def test_two_regulars_with_same_character_keep_their_saved_identity(self):
        selected = select_characters(5, fixed_ids=["v1-01", "v1-01"], rng=random.Random(1))
        self.assertEqual([c.id for c in selected[:2]], ["v1-01", "v1-01"])
        self.assertNotIn("v1-01", [c.id for c in selected[2:]])


if __name__ == "__main__":
    unittest.main()
