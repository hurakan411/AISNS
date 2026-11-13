# AI avatar loading without disk storage

The backend returns each stable Picsum seed URL without fetching/expanding it during
reply generation. This removes the sequential image-network waits from both post
and reply-thread responses. No image files, cache service or DB migration are added.

The app's `AIAvatarImage` is used for AI replies, nested replies and regular-follower
profiles. Its independent view task requests the image while the reply text remains
visible. There are at most three attempts per loading cycle, with 1s and 3s backoffs.
HTTP failures, non-image Content-Type responses and undecodable bytes are rejected.
An old saved Fastly CDN URL can retry via Picsum with the same image ID, dimensions
and image options; it does not substitute a different photo. Task cancellation ends
retries when the view disappears or its URL changes. Returning to the foreground
restarts loading if the view still has no image.

The dedicated session is ephemeral, URLCache is nil, local cache reads are disabled,
and no disk image store is created. Visible views retain their decoded image only
in memory. Connections per host are limited to four. A new loading cycle may require
another download; this deliberately trades network traffic for no persistent cache.

This reduces transient failures but cannot guarantee image availability during an
external provider outage. It does not replace the service or introduce new artwork.

## Verification

`scripts/check_avatar_images.swift`: 16 mocked checks cover recovery from 503/timeout,
maximum attempts, immediate success, HTTP 200 HTML rejection, invalid image data,
cancellation, HTTPS-only URLs, old CDN URL recovery and cache configuration.
Backend tests verify all normal/critic seed URLs are returned unchanged without a
requests.get call. No paid AI request or user database write is needed for these tests.

App installation alone enables retries; removing the server-side image wait also
requires deploying the backend change. Production is not updated by an install.
