# Sonava

One beautiful player for all your music — your own files, free legal streaming
catalogues, internet radio, podcasts and your self-hosted server, unified, with
on-device intelligence and no tracking.

> **Xcode 26+**, **iOS 18.0+**, **Swift 6** language mode.
> Zero third-party dependencies: SwiftUI, AVFoundation, MediaPlayer, ShazamKit,
> StoreKit 2, CryptoKit, Security.

---

## Quick start

```bash
open Sonava.xcodeproj      # scheme: Sonava
```

Everything below runs from the repository root.

| Task | Command |
| --- | --- |
| Build | `xcodebuild -project Sonava.xcodeproj -scheme Sonava -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` |
| All tests | `xcodebuild test -project Sonava.xcodeproj -scheme Sonava -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Unit only | add `-only-testing:SonavaTests` |
| UI only | add `-only-testing:SonavaUITests` |
| One suite | `-only-testing:SonavaTests/AIMixIntentTests` |

### Which simulator

**Run UI tests on _iPhone 17 Pro_.** That is the reference device the assertions
were written against, and the one the layout is tuned for.

```bash
xcrun simctl list devices available | grep iPhone      # what you have
```

If UI tests fail to launch with `Application failed preflight checks` /
`RequestDenied … Busy`, the simulator is wedged. Reset it and retry — this is a
simulator bug, not a test failure:

```bash
xcrun simctl shutdown all && xcrun simctl boot 'iPhone 17 Pro'
```

Pinning by UDID is more reliable than by name when several runtimes are
installed:

```bash
xcodebuild test -project Sonava.xcodeproj -scheme Sonava \
  -destination "platform=iOS Simulator,id=$(xcrun simctl list devices available -j \
  | python3 -c 'import json,sys;print([d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"]=="iPhone 17 Pro"][0])')"
```

### Test plan and languages

`Config/Sonava.xctestplan` runs **every test twice**: once in **English** and
once in **Russian**. The Russian pass is not ceremony — the app previously
shipped English copy to Russian users, and only a run in that locale catches it.

Run a single configuration:

```bash
xcodebuild test … -only-test-configuration Russian
```

### Device-only features

Some things cannot be verified in a simulator, by design of the frameworks:

| Feature | Why |
| --- | --- |
| **ShazamKit recognition** | Needs a real microphone; never matches on a simulator. `ShazamView` says so in-app. |
| **StoreKit purchases** | Need App Store Connect products. Settings → Developer → *unlock Pro* is a **DEBUG-only** override for testing Pro-gated UI. |
| **Instruments profiling** | Energy and memory figures from a simulator are meaningless. |

---

## Architecture

Folders on disk *are* the project structure — the Xcode project uses
`PBXFileSystemSynchronizedRootGroup` (`objectVersion = 77`), so **adding a Swift
file requires no `project.pbxproj` edit at all**. Create the file; it builds.

```
Sonava/
  App/            SonavaApp (@main), RootView            — composition root
  Models/         Song, Podcast, PlaybackModels
  Core/           JSONFileStore, Keychain, SongFeed,
                  FilterChip, AccessibilityID
  Services/
    Playback/     AudioManager, PlaybackEngine, PlaybackClock
    Catalog/      Audius, Deezer, iTunes, RadioBrowser,
                  Subsonic, Station, TrackProvider
    Library/      MusicLibrary, LocalFileStore, PlaylistStore, ServerStore
    Podcasts/     PodcastFeedService
    Intelligence/ AIMixService, ShazamService, LyricsService
    Commerce/     ProStore
  DesignSystem/   Theme, DesignComponents, Visualizer, Artwork,
                  MarqueeText, ShareCard, Haptics
  Features/       one folder per screen
  Resources/      Assets.xcassets, Localizable.xcstrings
Config/           Sonava-Info.plist, Sonava.xctestplan
```

### Invariants worth knowing before you change things

- **`PlaybackClock` is split off from `AudioManager` on purpose.** Position,
  progress and level update 20–30×/sec; keeping them in a separate
  `ObservableObject` stops every tick from re-rendering the whole tree. Do not
  merge them back.
- **Tabs are kept alive**, not rebuilt — visited tabs stay in the hierarchy and
  switch by opacity, which is what prevents flicker. A UI test asserts it.
- **`Song.id` is a `String`.** Anything keyed by track id is `[String]`.
- **Local tracks are identified by content hash**, not filename — the same file
  imported twice is one track, and two different `track01.mp3` are two.
- **Previews are labelled.** Deezer and Apple return 30-second previews; the UI
  groups them under `PREVIEWS · 30 SEC` and puts full tracks first. Users
  complained when previews looked like full tracks.
- **Feeds never hang in `.loading`.** Requests carry a ~20s resource timeout and
  every feed exposes tap-to-retry.

### Localization

Strings live in `Sonava/Resources/Localizable.xcstrings` (a String Catalog) and
are **extracted by the compiler** — there is no manual registry to forget.

- In SwiftUI, pass a literal: `Text("Home")`. Never `Text(someString)` for
  display copy — that silently skips translation.
- Outside SwiftUI: `String(localized: "…")`.
- Helper parameters that carry display copy must be typed `LocalizedStringKey`,
  not `String`.
- Russian plurals are real plural rules (`one/few/many/other`), so counts
  decline: 1 трек / 3 трека / 5 треков.

After adding strings, build once and open the catalog in Xcode; new keys appear
with an empty Russian value.

### Content and rights

**Sonava ships no audio.** The repository refuses it (`.gitignore` blocks
`*.mp3`/`*.m4a`/…), and there are no fixtures — tests synthesise a tone at
runtime (`SonavaTests/Support/TestAudioFile.swift`).

This is deliberate. An earlier revision bundled a commercial film score as its
demo library, which is an App Store rejection under Guideline 5.2 and a
copyright problem besides. The local library is now **the user's own files**,
imported from Files or iCloud Drive and copied into `Documents/Media` so they
keep playing offline even if the original is moved or evicted.

---

## Sources

| Source | Status | Notes |
| --- | --- | --- |
| Your files | ✅ full | Imported from Files / iCloud Drive. |
| Audius | ✅ full tracks | Primary free catalogue, no auth. |
| Deezer | ✅ 30s previews | Search, charts, Editor's picks. |
| Apple / iTunes | ✅ 30s previews | Music previews and podcast discovery. |
| Radio Browser | ✅ live | Internet radio by genre. |
| Podcasts (RSS) | ✅ episodes | 0.8×–2× playback speed. |
| Subsonic | ✅ full | Navidrome / Airsonic / Gonic; credentials in Keychain. |
| ShazamKit | ⚠️ device only | Needs the capability enabled and a real mic. |
| Apple Music (MusicKit) | ⛔ not built | The remaining content unlock. |
| Spotify | ⛔ not built | Premium + SDK gated. |

Free full-length *mainstream* streaming does not exist legally. The app never
implies otherwise; the honest path to a mainstream catalogue is MusicKit.

---

## Tests

65 unit + 19 UI tests, all green.

| Target | What it covers |
| --- | --- |
| `SonavaTests` | Import round trip (copy, metadata, dedupe, prune, delete), favourites/recents persistence and capping, `Song` identity and coding, safe degradation of on-disk state, AI Mix intent parsing in **English and Russian**, catalogue completeness and Russian plural rules. |
| `SonavaUITests` | Onboarding, all five tabs, tab-state preservation, settings, empty-library and empty-favourites states, playlist creation, the Files picker, Pro gating and paywall disclosure, and a Russian-locale pass over the same screens. |

UI tests find controls by **accessibility identifier** (`AccessibilityID`), never
by visible text — text changes with the display language. Identifiers are added
together with a VoiceOver label via the `identified(_:label:)` modifier.

---

## Conventions

- Swift 6 language mode, **zero warnings**. Keep it that way.
- Colours are named by role from `Theme` (`positive`, `destructive`,
  `brandGradient`). Raw `Color(hex:)` belongs in `Theme` or `Palette` only.
- New Xcode **targets** (widgets, Watch, CarPlay) should be added in Xcode, not
  by hand-editing the project file. New *files* need nothing.
- Companion docs: [`docs/HANDOFF.md`](docs/HANDOFF.md),
  [`docs/ROADMAP.md`](docs/ROADMAP.md),
  [`docs/INTEGRATIONS.md`](docs/INTEGRATIONS.md),
  [`docs/SETUP.md`](docs/SETUP.md).
