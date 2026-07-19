# Aurora — Engineering Handoff

This document is the single source of truth for **continuing development of this
app in a fresh session (new account, same model, same repo)**. Read it fully
before making changes. Companion docs: [`ROADMAP.md`](./ROADMAP.md) (product /
growth), [`INTEGRATIONS.md`](./INTEGRATIONS.md) (source connectors),
[`SETUP.md`](./SETUP.md) (build / capabilities / QA).

---

## 1. What this project is

**Aurora** is a complete SwiftUI rewrite of a UIKit/Storyboard demo audio player.
The goal is an "ultimate", beautiful, cross-service music **aggregator**: one
gorgeous player that unifies local files, free legal streaming catalogs, internet
radio, podcasts, and self-hosted servers, with on-device AI touches and a
subscription (Aurora Pro). Full positioning and monetization are in `ROADMAP.md`.

- **Platform:** iOS 16.0+, Xcode 15+. **Zero third-party dependencies** — only
  SwiftUI, AVFoundation, MediaPlayer, ShazamKit, StoreKit 2, CryptoKit, Security.
- **Language:** the product ships **bilingual EN/RU** (see §7). The user (project
  owner) communicates in **Russian**; mirror that in chat.
- **56 Swift files**, MVVM-ish, `@MainActor` services published into the SwiftUI
  environment.

---

## 2. Repo & branch mechanics (read first — this is how you continue seamlessly)

- **Repo:** `stiks92/audioplayer_test`.
- **Working branch:** `claude/player-redesign-swiftui-1c0c2x`. All work happens
  here. The owner has authorized **merging finished work to `main`** via PR.
- **Default flow for every change:**
  1. Make edits on the working branch.
  2. Commit with a clear message.
  3. `git push -u origin claude/player-redesign-swiftui-1c0c2x`.
  4. Open a PR to `main` and merge it (owner has standing authorization).
- **Before starting, always sync to remote** — a local checkout can be behind:
  ```
  git fetch origin main claude/player-redesign-swiftui-1c0c2x
  git checkout -B claude/player-redesign-swiftui-1c0c2x origin/claude/player-redesign-swiftui-1c0c2x
  ```
  (This exact "stale local checkout" issue caused a near-miss once — the crash fix
  had to be re-applied against the real remote HEAD. Always fetch first.)
- **If the working branch's PR was already merged and you're starting fresh work**,
  keep the same branch name but rebase/restart from the latest `origin/main`.

Merged so far: **PRs #1–#14** (full history in `git log origin/main`). Current
`main` HEAD after the handoff: `7a71fd2` (startup-crash fix).

---

## 3. The hard environment constraint: you cannot compile

There is **no Swift/Xcode toolchain in this Linux environment**, so you cannot
build or run the app. This shapes everything:

- **You write and review code by hand.** The owner's Xcode build is the source of
  truth. Expect to iterate on compile errors reported (often as screenshots).
- **Be conservative with SDK/API usage** — prefer APIs you're certain exist on the
  iOS 16 SDK. Availability mistakes are the most common build breaks.
- **Validate what you can statically:** for any dictionary literal, JSON decoding
  shape, or `project.pbxproj` edit, run a quick script to check invariants (e.g.
  duplicate keys, undefined UUID refs). A `static let` dictionary literal with
  **duplicate keys traps at launch** — that exact bug shipped once (see §7).
- After a batch of non-trivial changes, **explicitly recommend the owner do a
  build checkpoint** rather than stacking more unverified code.

---

## 4. Architecture map

Everything lives flat in `AudioPlayer_test/`. Logical grouping:

### App & root
- `AudioPlayerApp.swift` — `@main`; injects the shared services as environment objects.
- `RootView.swift` — custom tab container. **Keep-alive tabs** (a `Set<AppTab>` of
  visited tabs, opacity switching in a ZStack) to avoid tab-switch flicker. Hosts
  the mini-player, the `.fullScreenCover` onboarding (`@AppStorage("hasOnboarded.v1")`),
  and `.task { audio.restoreLastSession() }`.

### Models
- `Song.swift` — the universal track model. `id: String`, `source: TrackSource`
  (local/audius/radio/subsonic/itunes/deezer/jamendo/archive/podcast, each with a
  `badge`), `streamURL`/`artworkURL`, `isLive`, and `gradientHex: [UInt]` (Codable;
  computed `gradient: [Color]`). **`Song.id` is `String`** — anything referencing
  songs by id (e.g. `Playlist.songIDs`) must be `[String]`.
- `Playlist.swift` — user playlist; `songIDs: [String]`.
- `Podcast.swift`, `PlaybackModels.swift` — supporting models.

### Playback core
- `AudioManager.swift` — the heart. `@MainActor` singleton (`.shared`),
  `ObservableObject`. Owns the queue, shuffle/repeat, volume, playback rate, sleep
  timer, Now Playing/remote commands, endless autoplay (`autoExtendEnabled`,
  `maybeExtendQueue()`), and session resume (`persistNowPlaying`, `restoreLastSession`).
- `PlaybackEngine.swift` — protocol with **two backends**: `LocalAudioEngine`
  (`AVAudioPlayer`, real metering) for bundled files, `RemoteAudioEngine`
  (`AVPlayer`) for network streams & live radio. `AudioManager` picks per track.
- `PlaybackClock.swift` — **performance-critical split**: high-frequency values
  (`currentTime`, `progress`, `audioLevel`, `duration`) live here as a separate
  `ObservableObject` so the ~20–30fps updates don't re-render the whole UI tree —
  only views that observe the clock. **Do not move these back onto `AudioManager`.**

### Sources / services (all keyless & free unless noted)
- `AudiusService.swift` — full-length CC tracks (primary free catalog).
- `DeezerService.swift` — search + charts + playlists (30-sec previews).
- `iTunesService.swift` — Apple music previews + podcast discovery (30-sec previews).
- `RadioBrowserService.swift` — internet radio (`all.api.radio-browser.info`).
- `PodcastFeedService.swift` — RSS episode parsing (XMLParser).
- `SubsonicService.swift` + `ServerStore.swift` + `Keychain.swift` — self-hosted
  Subsonic/Navidrome (MD5 token auth via CryptoKit; creds in Keychain).
- `LyricsService.swift` — LRCLIB synced lyrics.
- `ShazamService.swift` — ShazamKit recognition (**device-only**; needs the
  ShazamKit capability enabled in Xcode).
- `AIMixService.swift` — on-device natural-language mix generation (understands
  EN + RU intent keywords).
- `StationService.swift`, `TrackProvider.swift`, `SongFeed.swift` — feed/loading
  state helpers (`SongFeed` models idle/loading/loaded/empty/failed, with retry).

### Monetization
- `ProStore.swift` — StoreKit 2 (`Product`, `Transaction`, `AppStore.sync`).
  Product IDs in `SETUP.md`. Has a **DEBUG-only developer unlock** (Settings →
  Developer: unlock Pro) so Pro features can be tested without App Store Connect.
- `PaywallView.swift` — the paywall.

### Design system
- `Theme.swift`, `DesignComponents.swift`, `Visualizer.swift`, `MarqueeText.swift`,
  `Artwork.swift`, `Haptics.swift`, `ShareCard.swift` (ImageRenderer "now playing"
  card). The **visualizer is mirror-symmetric / static-feeling** (not scrolling
  left→right) and the **aurora background pauses when not playing** for energy.

### Views (screens)
- `HomeView`, `SearchView`, `RadioView`, `PodcastsView`/`PodcastDetailView`,
  `LibraryView`, `NowPlayingView`, `MiniPlayerView`, `QueueView`,
  `PlaylistDetailView`/`UserPlaylistDetailView`, `RemotePlaylistView`,
  `ArtistView`, `AddToPlaylistView`, `SettingsView`, `ConnectServerView`,
  `OnboardingView`, `AIMixView`, `ShazamView`, `LyricsView`, `SongRow`.
- `Localization.swift` — see §7.

---

## 5. Key decisions & invariants (things that will bite you)

- **`Song.id` is `String`.** Keep id-collections as `[String]`.
- **Don't merge the high-frequency clock back into `AudioManager`** — the
  `PlaybackClock` split is a deliberate performance fix.
- **Mini-player minimize animates *down*, not left** — a `matchedGeometryEffect`
  was intentionally removed because it slid the player sideways. Don't reintroduce it.
- **Tabs are kept alive** (opacity switching), not rebuilt on switch — prevents
  flicker. Preserve this.
- **Network calls use a ~20s resource timeout** and feeds must never get stuck in
  `.loading` on cancellation; they expose tap-to-retry. Follow this pattern for new
  feeds.
- **Previews vs full tracks:** Deezer/Apple return 30-sec previews. The UI groups
  and **labels** them ("PREVIEWS · 30 SEC") and shows **full tracks first** — users
  were confused when previews looked like full tracks. Keep that distinction visible.
- **Legal/honesty constraint:** free *full-length mainstream* streaming does not
  exist legally. The real content unlock is **Apple Music via MusicKit** (Tier 3,
  subscription-gated) — see §9. Don't imply the app has full mainstream catalogs
  for free.

---

## 6. Sources status (what actually returns content)

| Source | Status | Notes |
| --- | --- | --- |
| Local bundle | ✅ full | 17 bundled mp3s, offline. |
| Audius | ✅ full tracks | Primary free catalog. |
| Deezer | ✅ 30s previews | Search, charts, playlists (Editor's picks on Home). |
| Apple/iTunes | ✅ 30s previews + podcasts | Music previews; podcast discovery. |
| Radio Browser | ✅ live | Internet radio by genre. |
| Podcasts (RSS) | ✅ episodes | 0.8×–2× speed. |
| Subsonic self-hosted | ✅ full | User provides server; Keychain creds. |
| ShazamKit | ⚠️ device-only | Needs capability + real device (won't match on simulator). |
| Apple Music (MusicKit) | ⛔ not built | The big content unlock — see §9. |
| Spotify | ⛔ not built | Tier 3, Premium + SDK gated. |

---

## 7. Localization system (and the crash rule)

Deliberately **lightweight and dependency-free** to avoid `.strings`/variant-group
`pbxproj` build risk:

- `Localization.swift` exposes a global `func L(_ key: String) -> String`.
- `L("English text")` returns the Russian string from `Localization.ru` **only when
  the device language is Russian** (`Localization.isRussian`), else returns the key
  (English) as-is. Missing keys fall back to English gracefully.
- **To localize a new string:** wrap the English literal in `L(...)` at the call
  site and add one `"English": "Русский",` entry to the `ru` dictionary.

**CRASH RULE (learned the hard way):** `Localization.ru` is a `static let`
dictionary literal. **A duplicate key traps at initialization → instant startup
crash** (only on RU devices, since `ru` is only read when `isRussian`). This
already shipped once (`"Server URL"` and `"Restore purchases"` were each added in
two blocks). **After editing `Localization.ru`, always run a duplicate-key check:**

```bash
python3 -c "
import re
keys={}; dup=False
for i,ln in enumerate(open('AudioPlayer_test/Localization.swift'),1):
    m=re.match(r'\s*\"((?:[^\"\\\\]|\\\\.)*)\"\s*:', ln)
    if m:
        k=m.group(1)
        if k in keys: print('DUP',k,keys[k],i); dup=True
        else: keys[k]=i
print('OK' if not dup else 'CRASH')
"
```

---

## 8. Editing `project.pbxproj` by hand

New Swift files must be registered in `AudioPlayer_test.xcodeproj/project.pbxproj`
(no Xcode here to do it). Pattern used:

- Add a `PBXFileReference`, a `PBXBuildFile`, an entry in the group's `children`,
  and an entry in the `Sources` build phase.
- Fabricated 24-hex UUIDs follow a convention (`AA000000000000000000Fnnn` for file
  refs, `Bnnn`/`Annn` for build files) to stay unique and greppable.
- **After editing, validate** there are no undefined references (every UUID used is
  defined) with a quick Python scan before committing. A broken pbxproj fails the
  owner's build immediately.
- **New Xcode *targets*** (Widgets, Watch, CarPlay, Live Activities) should **not**
  be hand-added — tell the owner to add the target in Xcode; hand-editing target
  graphs is too error-prone.

---

## 9. Open backlog

### Owner feedback still worth pushing on
These themes recur in the owner's reviews — weigh them when prioritizing:
- **"Content still feels thin."** The honest fix is **MusicKit (Apple Music)** —
  the only path to full-length mainstream catalog. Requires a green build + a real
  device + the MusicKit capability + entitlement. This is the highest-leverage next
  feature for perceived value.
- **Make it engaging to stay** (retention): smarter Home, taste-based endless radio,
  better AI Mix results.
- **Scale/polish for the App Store** — more content surfaces, richer discovery.
- **AI must understand Russian** — RU intent keywords were added to AIMix; keep
  verifying quality on RU prompts.

### Big rocks (each best done on a green build / may need a device)
- **Apple Music (MusicKit)** connect — real content unlock (see above).
- **Equalizer + crossfade/gapless** — needs an `AVAudioEngine` graph (core audio
  refactor; do it on a confirmed-building base).
- **Memory-leak & energy profiling** in Instruments (device).
- **Platform extensions** — Widgets, Live Activities, CarPlay, Watch (new targets;
  add in Xcode).
- **Spotify** connect (Tier 3), **scrobbling** (Last.fm/ListenBrainz), **offline
  downloads**, **iCloud sync**. See `ROADMAP.md` phases.

### Known limitations to state honestly (not bugs)
- Shazam needs a physical device (there's already a simulator hint in `ShazamView`).
- Preview sources are 30 seconds by the providers' design.

---

## 10. How the owner works (style guide)

- Communicates in **Russian**; wants an **ambitious, top-tier, App-Store-worthy**
  product ("валить по максимуму") that's genuinely worth paying for.
- Values: **clean, readable code; check every decision against current trends;
  re-verify your own work; refactor when needed.**
- Expects you to **finish to a checkpoint, self-review, then merge** and hand back
  something testable — with clear instructions.
- Gives blunt product feedback (often screenshots). Treat it as the priority signal.
- Frequently says "**пушни**" — that's "push it" (retry the commit/push).

---

## 11. Definition of done (per change)

1. Code compiles *in your head* — conservative APIs, no obvious type/availability
   errors; run any applicable static validation (dup keys, pbxproj refs).
2. Committed with a clear message on `claude/player-redesign-swiftui-1c0c2x`.
3. Pushed; PR opened and merged to `main`.
4. Docs updated if architecture/sources/setup changed.
5. Owner told, in Russian, what changed and what to test — and reminded to build if
   a lot of unverified code accumulated.
