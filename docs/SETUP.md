# Build, configure & test

What's needed to take the current branch and run it. There are **no third-party
dependencies** — pure SwiftUI + Apple frameworks.

## 1. Open & build

1. Open `Sonava.xcodeproj` in **Xcode 26 or newer**.
2. Select the `Sonava` scheme and an **iOS 18+** simulator or device.
   UI tests and layout are tuned against **iPhone 17 Pro** — use it.
3. `Cmd + B` to build. Signing is automatic; set your team under
   Signing & Capabilities when building to a device.

Full build/test command lines (including the two-language suite) live in the
[README](../README.md). The rule that matters: **a commit needs the whole suite
green in both languages** — plain run + `-testLanguage ru` run.

## 2. Capabilities & App Store Connect switches

Target → **Signing & Capabilities → + Capability**:

- **ShazamKit** — "what's playing" recognition against the Shazam catalogue.
  Without it the app builds; recognition honestly reports no match.

In **App Store Connect** (not Xcode):

- **MusicKit App Service** (App Information → App Services) — without this
  toggle Apple refuses developer tokens and the Apple Music connector shows
  its "not configured" state. No key generation needed for MusicKit on-device.

Already in `Config/Sonava-Info.plist`, no action needed: background audio,
microphone string, Apple Music usage string, ATS media exception +
local-networking (LAN Subsonic/WebDAV over http), local-network usage string.
`Sonava/Resources/PrivacyInfo.xcprivacy` declares the required-reason APIs
(UserDefaults, system boot time) — keep it in the target when adding targets.

## 3. StoreKit / Sonava Pro

Products expected in **App Store Connect** (see `ProStore.swift`):

- `com.sonava.pro.lifetime` (non-consumable — the anchor offer)
- `com.sonava.pro.monthly`, `com.sonava.pro.yearly` (auto-renewable + trial)

To test purchases locally without ASC: File → New → **StoreKit Configuration
File**, add the three products, select it under Scheme → Run → Options.
In **DEBUG** builds Settings has **Developer: unlock Pro**; the override is
compiled out of Release and the flag is scrubbed on Release launch.

## 4. QA checklist (current features)

- **Playback engine** — gapless album playback; EBU R128 normalization;
  10-band EQ **including on radio/podcast streams**; headphone correction
  profile (import an autoeq.app export); Crate Mix ordering with beat-matched
  overlaps (device audio check) — the only crossfade in the app; there is no
  generic "crossfade N seconds" setting for ordinary playback.
- **Sources hub** — Library → hub: files, folder bookmarks, Subsonic/Navidrome,
  WebDAV (Яндекс.Диск / Mail.ru presets), Apple Music connect, playlist import
  (M3U/CSV/pasted text), listening-history import (Spotify export, ListenBrainz).
- **Apple Music** — connect, search, play full catalogue with an active
  subscription (device only — simulator can't play DRM; EQ honestly disabled).
- **Подсобка** — track passports (BPM/key/sections) scan; ownership ledger;
  year recap + flyer share; Monday Mix.
- **Radio / Podcasts / Audius / previews** — search, play, favourites persist.
- **Lyrics** — synced highlight, tap-to-seek, offline cache, search fallback.
- **Pro** — paywall shows lifetime first; Privacy Policy + Terms links present
  (App Review 3.1.2); restore purchases works.
- **Both languages** — run the suite twice (`-testLanguage ru`); frames for any
  UI change (`docs/` design rules; no wall-clock in tests).

## 5. Release collateral

- Website statics live in `docs/site/` (index / privacy / support, EN+RU) —
  publish via GitHub Pages or any static host; the in-app links point to
  `Links.swift` → update the domain there once it exists.
- Privacy nutrition mapping for the ASC form: `docs/privacy-nutrition.md`.
- Reviewer notes draft: `docs/review-notes.md`.
- Partner/permission letters (send before release): `docs/letters/`.

## 6. Known gaps (by design, waiting on owner)

- Widgets / Live Activities / CarPlay / Watch — each needs a new Xcode target,
  added **in Xcode**, never by hand-editing the project file.
- Spotify connector ships DEBUG-only (5-user dev cap makes it unshippable);
  TIDAL/YouTube import wait on self-serve keys. See `docs/INTEGRATIONS.md`.
