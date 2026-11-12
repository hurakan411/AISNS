# Profile-name mentions in AI replies

The iOS app already sends `user_display_name` from the current profile for posts and
reply threads. This change is backend-only; request/response schemas and the model
remain unchanged. Deployment of the backend is required to activate it.

The previous policy allowed one mention in only 35% of batches. The new policy asks
the model to address the user by name in approximately one fifth of replies:

- Ordinary/image/viral post batches: nearest integer to reply count / 5, minimum one.
  Examples: 5 replies → 1, 10 → 2, 16 → 3, 32 → 6.
- A 3–5 reply conversation thread: one participant.
- Onboarding: retain the existing no-name policy.
- Missing, blank and generic placeholder names: no invented name.

Both Japanese and English instructions explicitly request the quota, retain the
profile name as data rather than instructions, prohibit invented nicknames and
critic name-calling, and vary placement. Custom profile names are not logged by
this feature. No extra generation call or paid retry is introduced. This is a
prompt-level target, not a guarantee that every generated batch satisfies the ratio;
the server does not mechanically prepend names or reject otherwise usable replies.

Tests mock the model and image URL resolver. They verify prompt wiring, quota
rounding, legacy clients without a name, and both generation paths without live
database writes or paid generation. They do not establish live-model compliance.

OpenAI Docs informed the explicit, separated instruction/data wording:
https://developers.openai.com/api/docs/guides/prompt-engineering
