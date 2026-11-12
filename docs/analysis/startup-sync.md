# Nonblocking startup (2026-11-12)

After the privacy screen, `ContentView` immediately selects Home or onboarding using local
completion state. There is no server-confirmation/blank-screen branch. Registration and reading
user progress run in the background in both Debug and Release.

`UserProgressSync` restores followers, post count and completion from an environment/user-scoped
cache. Existing `hasCompletedOnboarding` preferences remain compatible. Completion is monotonic:
a delayed `false` or a fresh development DB does not restart completed onboarding. If the server
confirms completion for a locally unfinished user, provisional onboarding effects/requests are
invalidated and saved posts are restored before Home opens.

The AI post/reply endpoints do not require a users-table row. Onboarding submission therefore
continues while registration is pending. Progress PUTs are coalesced and serialized after successful
registration and an initial GET, so completion cannot be lost to a missing row or overwrite unknown
existing counts with zero. Posts and followers added during a read are merged with its baseline.
Onboarding's demonstration followers are excluded from the progress cache.

Failed requests preserve cached state and pending writes. Foreground transitions and subsequent
sync requests retry; there is no continuous retry loop. Pending updates survive process restarts.
PostHog post numbering is seeded only after server history is known, or by the existing explicit
onboarding-completion path, rather than treating an empty startup cache as known history.

No backend endpoint or database migration is required. Shipping this behavior requires an iOS app
update. The first launch after upgrading may lack a follower/count cache; subsequent launches use
the cached values. Slow AI generation and time before iOS starts the app are separate from this
removed startup network wait.

## Verification

```sh
xcrun swiftc -parse-as-library AppCode/UserProgressSync.swift scripts/check_startup_sync.swift -o /private/tmp/upme-startup-checks
/private/tmp/upme-startup-checks
xcrun swiftc -parse-as-library AppCode/Analytics.swift AppCode/UserProgressSync.swift AppCode/AppState.swift scripts/check_engagement_metrics.swift -o /private/tmp/upme-engagement-checks
/private/tmp/upme-engagement-checks
```

- 47 startup/progress checks passed using an ephemeral mocked URLSession and an isolated preferences
  suite: held registration, completion while registering, stale responses, cached startup, environment
  isolation, local changes during reads/writes, registration/GET/PUT failure and restart recovery.
- 36 existing engagement/onboarding checks passed, with all networking mocked.
- Debug simulator and unsigned Release device builds passed. Existing StoreManager concurrency and
  profile `onChange` deprecation warnings remain.
- A dedicated iOS 18.4 simulator and a loopback API that holds registration responses were used for
  visual startup checks. Its app copy had the analytics token removed; no real user DB or AI requests
  were used. This confirms the server-response dependency is removed, not a measured physical-device
  launch-time benchmark.
