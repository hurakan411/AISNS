# Tactile social UI refresh

## Current scope after partial rollback (2026-11-11)

At the user's request, Home, Post, Profile, the tab bar and rank-up popup have returned to their previous designs. The original animated particle-network background is restored across the main screens. Stats retains its approved rank illustrations, circular progress, current-rank benefits, summary layout and rank-guide sheet. Its surface colors are isolated in `StatsTheme` so restoring the shared palette does not change the summary panel. Image-loading guards and whitespace-only submission prevention are retained.

The approved follow-up for Statistics replaces the lower summary with “あなたの記録” / “Your activity”.
One borderless, softly shaded purple panel displays AI followers and the next-rank requirement above
Posts, Likes received and AI replies, with small outline icons and Japanese 人/件 units. A note below
the panel always states that likes and replies come from saved posts. The summary guide uses the same
heading. The main screen has no header and fits without scrolling, using compact spacing and smaller
rank artwork when necessary; the rank-list sheet still scrolls.

Follow-up verification (2026-11-11): Debug simulator and signed device builds passed. Screenshots
confirmed Japanese layout with both banner spaces reserved, the updated summary spotlight, and
English rank 10 on a 375×667-point iPhone SE with both banner spaces reserved. Labels, the full
20,000,000 follower count, the saved-posts note and the rank-list button are visible without scrolling.
The build was installed over the existing app and launched on iPhone 13 with the development API.

The four-screen refresh and its screenshots described below are the previous review baseline, not the current appearance of Home, Post or Profile.

Rollback verification: Debug simulator build and `git diff --check` passed. All four Japanese fixture screens were captured and visually inspected (`home-restored-ja.png`, `post-restored-ja.png`, `profile-restored-ja.png`, `stats-restored-background-ja.png` in `output/design-review/`). The preview app was terminated afterward. No physical-device installation or Git push was performed.

## Scope

- Home: matte post cards and distinct, indented AI conversation bubbles. Existing one-reply and regular-follower actions retained.
- Post: spacious writing surface, native photo picker and thumbnail removal, disabled submission for whitespace-only text or while an image loads.
- Stats: ten rank illustrations, native circular progress, current-rank benefits, a unified follower/reaction summary. No lower horizontal progress gauge. The rank guide is opened separately.
- Profile: organic cover, editable avatar/name/bio, current rank artwork, regular-follower removal, language picker, hater toggle, purchases/restoration, contact link and legal sheets retained.
- Shared: restrained charcoal/pink/violet palette, tactile surfaces, four-tab navigation. Smaller displays can scroll instead of squeezing content.

## Data semantics

The app stores only its most recent five posts locally. Likes and replies therefore must not be labeled lifetime cumulative totals. The summary labels these as received likes / AI replies and always explains their scope below the panel. Total posts remains the server's cumulative count. Reply totals include AI replies in expanded conversation threads, but not the user's own reply.

Rank progress uses the current rank's lower threshold rather than dividing lifetime followers by the next threshold. At rank 3 with 1,482 followers it is `(1482 - 500) / (2000 - 500)`, approximately 65.5%. Rank 10 is complete.

## Verification

- Debug iOS Simulator build: successful.
- Release iOS device build, without signing/upload: successful.
- 62 automated rank-progress and image-atlas checks: successful.
- Simulator screenshots visually inspected for all four screens in Japanese and English, the English rank-guide sheet, and rank 10.
- No live AI posting, database writes, App Store upload, Git push or physical-device installation performed.
- Touch-driven end-to-end flows are not claimed by the screenshot checks. The Mac was locked for native UI automation.

Run the focused checks from the repository root:

```sh
xcrun swiftc AppCode/RankProgress.swift scripts/check_rank_design.swift -o /private/tmp/upme-rank-design-checks
/private/tmp/upme-rank-design-checks
```

## Offline design review

Install a Debug simulator build and launch, for example:

```sh
xcrun simctl launch --terminate-running-process booted com.example.UPME --ui-preview --ui-tab=stats --ui-language=ja --ui-rank=3
```

Tabs: `home`, `post`, `stats`, `profile`. Languages: `ja`, `en`. `--ui-guide=true` opens the selected screen's walkthrough; `--ui-empty=true` shows the empty timeline. `--ui-ad-space=true` reserves both banner spaces without loading ads. This mode is unavailable in Release and on physical devices. It uses in-memory fixtures, bypasses registration, local persistence, analytics, ads and StoreKit startup; accidental reply requests are confined to loopback. Preview screenshots are not real user data.

Screenshots are in `output/design-review/`. Artwork provenance and the exact built-in generation prompt are in `rank-artwork.md`.
