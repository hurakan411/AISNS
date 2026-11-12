# Viral posts

Normal posts have a 10% chance of going viral. The draw is independent of text or image content.
Onboarding is guaranteed viral for supported clients. The rank at request time determines the rewards:

- Likes: five times the rank's maximum (normal follower-gain maximum × 7 × 5).
- Followers gained: five times the rank's normal maximum.
- AI replies: twice the rank's maximum, from 10 at rank 1 to 32 at rank 10.

`POST_FOLLOWER_RANGES` and `POST_REPLY_RANGES` in `backend/main.py` define the ranges.
There is one OpenAI generation call for the entire batch, including images, regular-follower
memories and critic/defender roles. A viral response uses a count-constrained Structured Outputs
schema; there is no follow-up generation to fill the extra replies. More output tokens are still
used for the larger batch. Critic limits do not increase.

## Compatibility and persistence

New apps send `supports_viral_posts: true`. The backend returns an optional `reaction` object with
`is_viral`, `rank`, `likes`, and `follower_gain`. Old clients do not opt in. Supported onboarding requests
force a viral result without drawing a random chance. Onboarding uses virtual rank 10: 10,500,000 likes,
1,500,000 demonstration followers and 32 replies, generated in one call with the existing critic/defender
story. The same 12-second presentation is used, reusing prefetched replies. Exiting early retains all
received replies and final likes; demonstration followers still reset to zero and never enter the real
account's progress ledger. If the new app reaches an old backend, normal posts use normal local
rewards and does not display a viral effect. No database migration is needed.

After receiving a successful response, the app atomically saves the reaction, pending replies and
their reveal offsets in each post. No generation call is made during animation or restoration.
Each post has independent state so simultaneous submissions cannot exchange replies or rewards.
Unfinished posts are retained beyond the normal five-post history limit until delivered.

Follower gain is credited at the end so rank-up appears after the viral animation. An absolute
`followersAfter` ledger is saved before updating the user-progress cache. Restoration repairs an
interrupted cache write using the recorded maximum, without treating previously credited totals
as new gains over the first server read. Pending saved outcomes settle on relaunch; no animation
or reward is replayed. Reward ledgers are scoped to the API environment, so development rewards
cannot be credited to production when an app build is replaced. The pre-existing request lifecycle still cannot recover an API response
if the process is terminated before that response has been received and saved.

## Presentation

The effect starts when generated replies arrive, not while the API is pending:

- 0–3 seconds: first replies arrive, counts start slowly.
- At 3 seconds: localized viral badge appears; one haptic signals the reveal.
- 3–9 seconds: faster count-up and a thin moving pink/violet highlight on the post border.
- 9–12 seconds: count settles; all generated replies have appeared by 11 seconds.
- At 12 seconds: exact likes and follower gain settle, follower gain label appears, rank-up can follow.

The completed post keeps a quiet viral badge/border. Replies retain the existing nested SNS layout.
No automatic scroll or fullscreen interruption is introduced. Reduce Motion disables the moving
highlight, symbol bounce and number/entry animations. UI strings are provided in Japanese/English.

Debug simulator preview: `--ui-preview --ui-tab=home --ui-language=ja --ui-viral=true`.
Preview uses fixture replies and does not contact the backend, AI API or analytics.

## Verification

Mocked backend tests cover all ten rank rewards, normal ranges, viral batches of 10 and 32 in
Japanese/English including an image, exact response-schema counts, one generation call, and
guaranteed onboarding and old-client exclusion. Swift checks cover concurrent posts, timed reveal, exact reward
settlement, repeated foreground updates, saved pending replies, legacy post decoding and interrupted
write recovery. Startup checks include recovery against a server that already has the reward.
