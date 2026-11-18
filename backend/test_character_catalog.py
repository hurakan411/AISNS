import json
import random
import unittest

from character_catalog import (CHARACTERS, BY_ID, build_character_prompt, select_characters,
    resolve_character_id, make_character_plan, build_persistent_character_prompt, reply_character_id)


class CharacterCatalogTests(unittest.TestCase):
    def test_legacy_regular_identity_is_stable_without_saved_id(self):
        first = resolve_character_id(None, "regular:legacy-user")
        self.assertIn(first, BY_ID)
        self.assertEqual(first, resolve_character_id("unknown-id", "regular:legacy-user"))
        for seed in range(10):
            random.seed(seed)
            plan = make_character_plan(5, regulars=[("legacy-user", None)])
            self.assertEqual(plan.regular_ids["legacy-user"], first)
            self.assertEqual(resolve_character_id(first, "different identity"), first)

    def test_production_prompt_contains_only_needed_definitions(self):
        plan = make_character_plan(5, regulars=[("yuki", "v1-03")])
        self.assertEqual(len(plan.definitions), 5)
        self.assertEqual(len(set(plan.general_ids)), 4)
        self.assertNotIn("v1-03", plan.general_ids)
        for language in ("ja", "en"):
            prompt = build_persistent_character_prompt(plan, language)
            rows = json.loads(prompt.strip().splitlines()[-1])
            self.assertEqual(len(rows["characters"]), 5)
            for c in CHARACTERS:
                if c not in plan.definitions:
                    self.assertNotIn(c.voice_en if language == "en" else c.voice_ja, prompt)

    def test_saved_identity_wins_over_bad_model_id_and_repeated_authors(self):
        plan = make_character_plan(5, regulars=[("yuki", "v1-03")],
            people=[("みく", "v1-13", "unused")])
        assigned = {}
        self.assertEqual(reply_character_id(plan, "v1-22", "yuki", "ゆき", assigned), "v1-03")
        self.assertEqual(reply_character_id(plan, None, None, "みく", assigned), "v1-13")
        first = reply_character_id(plan, "invalid", None, "れん", assigned)
        self.assertIn(first, plan.general_ids)
        self.assertEqual(reply_character_id(plan, "v1-22", None, "れん", assigned), first)

    def test_viral_32_people_can_reuse_only_after_catalog_exhaustion(self):
        plan = make_character_plan(32)
        self.assertEqual(len(plan.definitions), 30)
        assigned = {}
        ids = [reply_character_id(plan, None, None, str(i), assigned) for i in range(32)]
        self.assertEqual(len(set(ids[:30])), 30)
        self.assertTrue(all(id in BY_ID for id in ids))
        plan = make_character_plan(32, regulars=[("yuki", "v1-03"), ("miku", "v1-13"), ("ren", "v1-09")])
        assigned = {}
        general = [reply_character_id(plan, "v1-03", None, str(i), assigned) for i in range(27)]
        self.assertEqual(len(set(general)), 27)
        self.assertFalse(set(general) & set(plan.regular_ids.values()))

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
