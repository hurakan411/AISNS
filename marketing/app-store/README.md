# App Store screenshots

Latest versions: `ja/01-concept-v2-real.jpg` and `ja/02-features-v2-real.jpg`.
Each is 1179 × 2556 px, RGB JPEG without transparency. PNG review copies are also provided.

The UI layers are actual captures of the current Debug simulator app using its existing offline
sample data (`--ui-preview`). No generative image tool was used to redraw, replace or retouch
the app UI. The original simulator screenshots are retained in `ja/screenshots/`.
Feature cards use cropped captures of Home, the viral-post state, and Profile.
The posting screen capture is also retained as source material.

Rebuild the marketing layouts from the repository root:

```sh
xcrun swift marketing/app-store/render-screenshots.swift
```

The v1 images are earlier generated visual concepts, retained for reference; use v2-real
when reviewing the versions that include actual app screenshots.
