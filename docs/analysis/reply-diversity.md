# Reply diversity (2026-11-12)

## Findings and changes

The prompt already prohibited semantic duplicates, but mostly differentiated followers by age/job.
It also showed the same flower/workday example phrases on every request and encouraged long replies
even for sparse posts. Non-regular replies had no wording history from previous posts. These are
plausible contributors to repetition, not a measured attribution of production output quality.

Normal replies now receive distinct assignments before generation: noticing a detail, receiving an
emotion, personal taste, a relatable everyday situation, appreciation, suitable light humor, or a
personal reaction. Wording/length varies independently. Optional curiosity is assigned to at most
one slot, and the shared instructions cap advice/rest wishes and questions at one normal reply each.
An unsuitable assignment must yield to the post's mood and actual information. No extra API call is
added. These are model instructions, not a semantic uniqueness guarantee enforced by code.

Regular followers keep their established voice. The normal-reply table excludes critic/defender
slots and preserves their ordering; thread follow-ups get a separate table for additional people,
while the target AI answers the user's response first. Fixed example phrases, reaction percentages,
and demographic/job personas have been removed. Comments are now mostly short, with an approximate
6:3:1 short/medium/long mix: Japanese 2–20 / 21–45 / 46–75 characters; English 1–6 / 7–14 / 15–24
words. Lower bounds remain optional. Simple acknowledgments are allowed so sparse posts do not
force everyone to paraphrase the same sentence or invent circumstances to fill space.

The iOS app optionally sends `recent_ai_replies`: up to eight distinct excerpts, at most 160 characters
each and three per saved post, from AI comments/AI thread replies. User-authored replies, critics,
defenders and the current post are excluded. Backend history is bounded again and supplied as user
data with instructions to avoid reusing distinctive openings/endings, not to treat it as commands,
facts, or shared memories. Onboarding sends no history. The request field defaults to an empty list,
so previous apps work with the updated backend; previous backends ignore the additional field.

Model, reasoning mode, response schemas, rank counts and database schema are unchanged. Prompt-only
improvements become available to existing apps when the backend is deployed; cross-post wording
history additionally requires an updated iOS app. No deployment is performed by these edits.

The [official OpenAI prompting guide](https://developers.openai.com/api/docs/guides/prompt-engineering)
describes separating behavioral instructions from contextual data. The particular reaction plan is
an app-specific design choice, not an OpenAI guarantee of diverse replies.

## Checks

```sh
cd backend
OPENAI_API_KEY=test-key SUPABASE_URL= SUPABASE_KEY= python3 -m unittest test_regular_followers -q
```

22 mocked backend tests cover language, image context, role slots, schema compatibility and bounded
history. The Swift engagement/onboarding check executable now includes four style-history checks
(40 total); the Debug simulator build also passes. The paid synthetic smoke harness includes Japanese
and English style-history cases in addition to text, images, onboarding, regulars and reply threads:

```sh
python3 backend/smoke_test_luna.py --live --output /private/tmp/upme-reply-diversity-v2-smoke.json
```

This harness disables database access and uses synthetic posts/images only. Its response/identity
checks detect API/schema/role regressions; wording quality still requires reading the generated
examples. No experiment with real users or retention measurement is implied.

Final verification: all 14 live cases passed with the revised prompt, including both style-history
cases, both image cases, three regulars at rank 10, both onboarding arcs and both thread languages.
The first local iteration still produced long recaps and repeated rest suggestions; shortening
replies and removing demographic personas produced more distinct short reactions in the second
iteration. For the workday/history fixture, actual outputs included “仕事モード終了！” and
“今日の分は完了だね。自分に何かごほうびあげたくなるやつ。” rather than five rest wishes.
High-count replies to thin posts still sometimes share the same theme (notably practice helping a
presentation). This is a qualitative review of synthetic samples, not a semantic-dedup benchmark.
