# Sonava — Engineering Handoff

Single source of truth for continuing this app in a fresh session. Read it
fully before making changes. The [`README`](../README.md) covers build/test
mechanics in depth; this document covers *how the project got here and what to
watch out for*. Companion docs: [`ROADMAP.md`](./ROADMAP.md) (product / growth),
[`INTEGRATIONS.md`](./INTEGRATIONS.md) (source connectors),
[`SETUP.md`](./SETUP.md) (capabilities / QA).

---

## 1. What this project is

**Sonava** is a SwiftUI music **aggregator**: one player over the user's own
files, free legal streaming catalogues, internet radio, podcasts and self-hosted
servers, with on-device intelligence and a subscription (Sonava Pro). Positioning
and monetization are in `ROADMAP.md`.

- **Platform:** iOS 18.0+, Xcode 26+, **Swift 6 language mode, zero warnings**.
  **Zero third-party dependencies** — SwiftUI, AVFoundation, MediaPlayer,
  ShazamKit, StoreKit 2, CryptoKit, Security.
- **Bilingual EN/RU.** The owner communicates in **Russian**; mirror that.
- ~60 Swift files, MVVM-ish, `@MainActor` services in the SwiftUI environment.

> **Renamed from "Aurora".** That name is taken in the App Store by a direct
> competitor. "Sonava" was cleared against the store and trademark registries.
> Don't reintroduce "Aurora" as product copy. The `AuroraBackground` view keeps
> its name on purpose — the aurora visual is the motif, not the brand.

---

## 2. Repo & branch mechanics

- **Repo:** `stiks92/AudioPlayer_test`. **Working branch:**
  `claude/player-redesign-swiftui-1c0c2x`. Finished work merges to `main` via PR.
- **Always sync first** — the local checkout can be behind:
  ```
  git fetch origin main claude/player-redesign-swiftui-1c0c2x
  git checkout -B claude/player-redesign-swiftui-1c0c2x origin/claude/player-redesign-swiftui-1c0c2x
  ```
- **Git auth gotcha:** the SSH key has a non-default filename. If pushes fail
  with `Permission denied (publickey)` or a 403, it is key discovery, not access:
  ```
  git config core.sshCommand "ssh -i ~/.ssh/github -o IdentitiesOnly=yes"
  ```
  Keep `origin` on SSH — switching to HTTPS makes the `gh` token take over as the
  **wrong** GitHub identity, which fetches fine but cannot push or open PRs.
  Opening the PR itself may need the owner (the CLI's `gh` account may lack write).

---

## 3. You CAN build and run

The Mac has the full toolchain (Xcode 26, simulators). This is a change from
earlier sessions, which ran on Linux with no compiler.

- Build, run in the simulator, screenshot, and run the test suites. See the
  README for exact commands and **which simulator** (iPhone 17 Pro) UI tests
  expect, plus how to recover a wedged simulator.
- After a batch of non-trivial changes, do a build + test checkpoint before
  stacking more. Every commit so far has been left green (build + tests).
- Still can't be verified here: ShazamKit matching, StoreKit purchases, and
  Instruments profiling — all need a real device.

---

## 4. Architecture map

Folders on disk **are** the project structure (`PBXFileSystemSynchronizedRootGroup`,
`objectVersion = 77`). Adding a Swift file needs **no `project.pbxproj` edit** —
just create it. This designs out the old manual-registration breakage entirely.

```
Sonava/
  App/            SonavaApp (@main), RootView
  Models/         Song, Podcast, PlaybackModels
  Core/           JSONFileStore, Keychain, SongFeed, FilterChip, AccessibilityID
  Services/
    Playback/     AudioManager, PlaybackEngine, PlaybackClock,
                  EqualizerSettings, EqualizerPreset, AudioEffects
    Catalog/      Audius, Deezer, iTunes, RadioBrowser, Subsonic, Station, TrackProvider
    Library/      MusicLibrary, LocalFileStore, PlaylistStore, ServerStore
    Podcasts/     PodcastFeedService
    Intelligence/ AIMixService, ShazamService, LyricsService
    Commerce/     ProStore
  DesignSystem/   Theme, DesignComponents, Visualizer, Artwork, MarqueeText, ShareCard, Haptics
  Features/       one folder per screen (Home, Search, …, Equalizer)
  Resources/      Assets.xcassets, Localizable.xcstrings
Config/           Sonava-Info.plist, Sonava.xctestplan
```

### Playback core (know this before touching audio)
- `AudioManager` — `@MainActor` singleton. Owns queue/shuffle/repeat, volume,
  rate, sleep timer, Now Playing/remote commands, endless autoplay, session
  resume, and the shared `AudioEffects`.
- `PlaybackEngine` — protocol, `@MainActor`, with two backends:
  - `LocalAudioEngine` — an **AVAudioEngine graph** (player → `AVAudioUnitEQ`
    10 bands → `AVAudioUnitTimePitch` → mixer) for imported files. Real EQ,
    real tap-based metering.
  - `RemoteAudioEngine` — `AVPlayer` for streams & live radio.
- `PlaybackClock` — high-frequency (`currentTime`/`progress`/`audioLevel`) split
  into its own `ObservableObject` so 20–30 fps updates don't re-render the whole
  tree. **Do not merge it back into `AudioManager`.**

---

## 5. Invariants that will bite you

- **`Song.id` is `String`.** Id-collections are `[String]`.
- **Local tracks are identified by SHA-256 of content**, not filename.
- **The app ships no audio.** `.gitignore` refuses it; tests synthesise a tone.
  An earlier revision bundled a commercial film score as its demo library — an
  App Store rejection (Guideline 5.2) and infringement. Local = user's files.
- **Don't merge the `PlaybackClock` split back.**
- **Tabs are kept alive** (opacity switch), not rebuilt. A UI test guards it.
- **EQ gains clamp to ±12 dB and reject non-finite** — the audio units trap on
  bad input, so `equalizer.json` is repaired on decode.
- **Previews are labelled.** Deezer/Apple return 30-sec previews; the UI groups
  them under `PREVIEWS · 30 SEC` and shows full tracks first.
- **Feeds never hang in `.loading`** — ~20s timeout, tap-to-retry.
- **Legal honesty:** no free full-length *mainstream* streaming. The real
  content unlock is **MusicKit** (subscription-gated). Don't imply otherwise.

---

## 6. Localization (String Catalog)

`Sonava/Resources/Localizable.xcstrings`, keys **extracted by the compiler**.

- SwiftUI: pass a literal — `Text("Home")`. Never `Text(someString)` for display
  copy; that skips translation silently (this exact bug shipped English
  onboarding to RU users).
- Elsewhere: `String(localized: "…")`.
- Helper params carrying display copy must be `LocalizedStringKey`, not `String`.
- Russian plurals use real plural rules (`one/few/many/other`) — counts decline.
- After adding strings, build once (keys extract to `.stringsdata`), then add the
  Russian value in the catalog. `LocalizationCatalogTests` fail if key UI strings
  are left untranslated.

The old bespoke `L()` dictionary is **gone**. Don't reintroduce a hand-rolled map.

---

## 7. Editing `project.pbxproj`

New **files** need nothing (synchronized groups). New **targets** (widgets,
Watch, CarPlay, Live Activities) should be added in Xcode by the owner —
hand-editing target graphs is too error-prone.

---

## 8. Tests

65 unit + 19 UI, each run in **English and Russian** via `Config/Sonava.xctestplan`.

- Unit (`SonavaTests`): import round trip, favourites/recents persistence, `Song`
  identity/coding, safe degradation of on-disk state, AI Mix intent parsing
  (EN + RU), catalogue completeness + RU plurals, the full EQ model, and the
  `LocalAudioEngine` graph exercised against a generated tone.
- UI (`SonavaUITests`): onboarding, tabs + state preservation, settings, empty
  states, playlist creation, Files picker, Pro gating + paywall disclosure, EQ
  gate + controls, and a Russian pass.
- UI tests find controls by **accessibility identifier** (`AccessibilityID`),
  never visible text. Add an id with `identified(_:label:)`, which also sets the
  VoiceOver label. A DEBUG launch arg `-openEqualizer` deep-links a screen.

---

## 9. Open backlog

### Highest leverage next
- **Apple Music (MusicKit)** — the honest path to a full-length mainstream
  catalogue, the recurring "content feels thin" answer. Needs a device + the
  MusicKit capability + entitlement (owner adds in Xcode).
- **Streaming EQ** — `RemoteAudioEngine` plays flat. Applying the EQ to AVPlayer
  needs an `MTAudioProcessingTap`. The local EQ, model, presets and UI are done.
- **Crossfade / gapless** — now feasible on the AVAudioEngine base (schedule the
  next buffer / a second player node with volume ramps).

### Larger
- Memory/energy profiling in Instruments (device).
- Platform extensions — Widgets, Live Activities, CarPlay, Watch (new targets).
- Spotify connect, scrobbling (Last.fm/ListenBrainz), offline downloads, iCloud sync.

### Known limitations (state honestly, not bugs)
- Shazam needs a physical device. Preview sources are 30 seconds by design.

---

## 10. How the owner works

- Communicates in **Russian**; wants an ambitious, App-Store-worthy product
  ("валить по максимуму") genuinely worth paying for.
- Values clean, readable code; checking decisions against current practice;
  re-verifying your own work; refactoring when needed.
- Expects you to finish to a checkpoint, self-review, then merge — and hand back
  something testable with clear instructions. Gives blunt product feedback.
- "**пушни**" = "push it".

## 11. Definition of done (per change)

1. Builds clean (Swift 6, **zero warnings**); applicable tests green in EN + RU.
2. Committed on the working branch with a clear message.
3. Pushed; PR opened and merged to `main` (owner may need to open the PR).
4. Docs updated if architecture/sources/setup changed.
5. Owner told, in Russian, what changed and what to test.
