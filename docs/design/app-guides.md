# In-app screen guides

First entry to each main tab presents a short spotlight tour. The title, explanation, step count and
pointer share one compact popover. Tapping the screen advances; the final step shows the reminder
that all guides can be replayed from Profile. Stage changes fade out in 100ms and fade in in 120ms;
scrolling targets are brought into view before the next popover appears. A light-gray scrim keeps
the rest of the interface visible while preventing underlying controls from activating.

| Screen | Guided elements, in order |
| --- | --- |
| Home | Compose prompt, reaction counts, AI reply, reply action, regular-AI star |
| Post | Text editor, photo attachment, submit button |
| Statistics | Current rank, rank benefits, activity totals, all-ranks link |
| Profile | Profile photo, name and bio, current rank, regular AIs, language, hater toggle, ad removal, contact, terms/privacy, guide chooser |

Each screen has its own saved progress. A step is marked seen when tapped to advance. If targets
are temporarily unavailable, those steps stay pending. Skipping via VoiceOver Escape affects only
that screen. Profile → How to use UPME opens a native menu to replay any screen from its first step.
Progress is stored locally in UserDefaults; no server/schema changes are needed.

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
`postImage`, `statsRankList`, or `profileSettings`. Preview stores are isolated and do not record
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
