# Build, configure & test

Everything below is what's needed to take the current `main` and run it. There
are **no third-party dependencies** — pure SwiftUI + Apple frameworks.

## 1. Open & build

1. Open `AudioPlayer_test.xcodeproj` in **Xcode 15 or newer**.
2. Select the `AudioPlayer_test` scheme and an **iOS 16+** simulator or device.
3. `Cmd + B` to build. (This is the first real compile — see "If the build
   fails" below.)

Deployment target is **iOS 16.0**. Signing uses automatic; set your team under
Signing & Capabilities if building to a device.

## 2. Capabilities to enable in Xcode (not code)

Target → **Signing & Capabilities → + Capability**:

- **ShazamKit** — required for "what's playing" recognition to match against the
  Shazam catalogue. Without it the app builds and runs, but recognition returns
  "no match".
- (Already in `Info.plist`, no action needed) Background audio mode,
  microphone usage string, and an ATS media exception for HTTP radio streams.

## 3. StoreKit / Aurora Pro

Purchases need products defined in **App Store Connect** with these IDs (see
`ProStore.swift`):

- `com.aurora.pro.monthly`
- `com.aurora.pro.yearly`
- `com.aurora.pro.lifetime`

To test purchases **locally without App Store Connect**:

1. File → New → File → **StoreKit Configuration File** (e.g. `Aurora.storekit`).
2. Add the three products above (2 auto-renewable subs + 1 non-consumable).
3. Scheme → Edit Scheme → Run → **Options → StoreKit Configuration** → select it.

Or skip purchasing entirely while testing: in a **DEBUG** build open
**Settings → Developer: unlock Pro** to toggle the entitlement on. This unlocks
AI Mix and other Pro-gated features immediately.

## 4. QA checklist (by feature)

Bundled audio works offline; the rest needs a network connection.

- **Playback** — play a bundled track; scrub, next/prev, shuffle, repeat,
  volume; lock-screen / Control Center controls; background playback.
- **Home** — greeting, AI Mix banner, Trending on Audius shelf, quick picks.
- **Search** — local results + live Audius results (type ≥ 2 chars).
- **Radio** — genre chips load stations; a station plays; Now Playing shows LIVE.
- **Podcasts** — search or pick a genre; open a show; play an episode; change
  speed (0.8×–2×) in Now Playing.
- **AI Mix** — (Pro) enter "rainy focus" etc.; a mix is built and plays.
- **Lyrics** — open a mainstream track's lyrics; synced highlight + tap-to-seek.
- **Shazam** — tap the waveform button in Home; identify ambient music (device
  only; needs the ShazamKit capability).
- **Self-hosted** — Settings → Self-hosted; connect a Subsonic/Navidrome server;
  "From your server" shelf + server results in Search.
- **Playlists** — create a playlist; add tracks from the player's + button or a
  row's long-press menu; verify it persists after relaunch.
- **Favorites / Recents** — favorite a streaming track; confirm it survives a
  relaunch (stored as full snapshots).
- **Queue** — Play Next / Add to Queue from a row's long-press; open the queue;
  drag to reorder; swipe to remove.
- **Share** — Now Playing → share; a gradient "now playing" card is generated.
- **Sleep timer** — Now Playing (moon) or Settings; playback pauses when it ends.

## 5. If the build fails

The code was written and reviewed without a local Swift toolchain, so the first
Xcode build is the source of truth. If anything doesn't compile, send me the
exact error text (file + line) and I'll fix it immediately. Most likely spots to
watch are SDK availability on your Xcode version and StoreKit/ShazamKit APIs.

## 6. Not yet included (next up)

- Equalizer + crossfade/gapless (needs an `AVAudioEngine` graph — a core audio
  refactor best done on a green build).
- Widgets / Live Activities / CarPlay / Apple Watch (each needs a new Xcode
  **target**, which should be added in Xcode rather than by editing the project
  file by hand).
- Apple Music (MusicKit) and Spotify account connect (Tier 3 — playback via
  their SDKs, subscription-gated).
- Scrobbling (Last.fm / ListenBrainz).
