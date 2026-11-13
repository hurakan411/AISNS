# In-app screen guides

First entry to each main tab presents a short spotlight tour. The title, explanation, step count and
pointer share one compact popover. Tapping the screen advances; the final step shows the reminder
that all guides can be replayed from the rightmost Settings tab. Stage changes fade out in 100ms and fade in in 120ms;
scrolling targets are brought into view before the next popover appears. A light-gray scrim keeps
the rest of the interface visible while preventing underlying controls from activating.

| Screen | Guided elements, in order |
| --- | --- |
| Home | Compose prompt, reaction counts, viral-post explanation, AI reply, reply action, regular-AI star |
| Post | Text editor, photo attachment, submit button |
| Statistics | Current rank, rank benefits, activity totals, all-ranks link |
| Profile | Profile photo, name and bio, regular AIs |

Each screen has its own saved progress. A step is marked seen when tapped to advance. If targets
are temporarily unavailable, those steps stay pending. Skipping via VoiceOver Escape affects only
that screen. Settings → How to use UPME opens a native menu to replay any screen from its first step.
Progress is stored locally in UserDefaults; no server/schema changes are needed.

The bottom bar has five equally sized tabs: Home, Post, Statistics, Profile and Settings.
Profile has no navigation header, gear button or rank card. It retains editing and
regular-follower management. Settings holds language, the hater toggle, guide replay, ad removal/restore,
contact, legal sheets and Debug-only onboarding replay. Settings itself has no guide or guide targets;
Settings is the root of its own NavigationStack and never hosts a spotlight. Selecting a guide opens the
chosen tab's guide. Old settings step IDs remain decodable, but are excluded from the profile tour;
including `profileSettingsEntry` from the former gear-entry tour. Previously acknowledged profile
steps remain complete. Existing home users receive only the new `buzz` step.

The viral explanation highlights the existing post card even if it is not currently viral, so the tour
does not require waiting for a random viral event. Its Japanese/English text explains five times rank
maximum likes, three times follower gain, twice maximum AI replies and the 24-hour cooldown.
The completion reminder points to Settings.

Highlights attach to the visible control or card before outer spacing. The Post photo step highlights
only the attachment button. The statistics rank step includes the illustration, rank number and rank
name together. Statistics has no top header and fits the available height without scrolling; smaller
spaces use a smaller illustration and tighter spacing. Its rank-list sheet still scrolls.

The Post and Profile guides scroll their own content to offscreen targets. The keyboard does not open automatically
while the Post guide is active. Rank list, profile legal sheets and removal alerts pause guide
presentation while open. The final reminder also blocks the app until dismissed.

## Preview

Use a Debug simulator build with `--ui-preview --ui-guide=true --ui-tab=home|post|stats|profile`
and optionally `--ui-language=ja|en`. `--ui-guide-step` accepts a step raw value such as
`postImage`, `statsRankList`, `buzz`, or `profileRank`. `--ui-tab=settings`
opens Settings directly for layout checks. Preview stores are isolated and do not record
guide completion. `--ui-ad-space=true` reserves the two 50-point banner spaces without loading
ads, to verify layouts with the same available height as an ad-supported device. The state test script is:

```sh
xcrun swiftc -parse-as-library AppCode/HomeGuide.swift scripts/check_home_guide.swift -o /private/tmp/upme-home-guide-checks
/private/tmp/upme-home-guide-checks
```

Verified corrections on 2026-11-11: simulator and signed iPhone Debug builds succeeded; all 23
guide state checks passed. Screenshots confirmed the attachment button target, the combined
statistics rank target, profile photo, rank card, language, contact and guide-chooser targets. The statistics screen also
fits a 375×667-point iPhone SE display with English rank 10 and both banner spaces reserved.
These screenshot checks do not exercise tap-driven transitions. The corrected build was installed
over the existing app and launched on iPhone 13 with the development API on 2026-11-11.

Settings-tab verification: 29 guide-state checks cover the revised tours and legacy progress,
including progress saved with the former gear-entry step. Settings has no guide screen. No real
purchases or contact submissions are needed for these layout checks.
