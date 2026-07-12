# Aurora — a modern SwiftUI music player

A complete redesign of the original UIKit/Storyboard `AudioPlayer_test` into a
polished, animated, SwiftUI music player.

> Requires **Xcode 15+** and **iOS 16.0+**. No third-party dependencies —
> everything is built on SwiftUI, AVFoundation, MediaPlayer and Combine.

## Highlights

- **100% SwiftUI** with a declarative, testable MVVM-ish architecture.
- **Live, audio-reactive visualizer** driven by real `AVAudioPlayer` metering.
- **Animated "aurora" backgrounds** that recolor to each track's palette.
- **Expanding Now Playing** scene with a shared-element (`matchedGeometryEffect`)
  transition from a docked mini-player.
- **Custom animated components**: morphing play/pause, heart-burst favorite
  button, draggable scrubber, marquee titles, spring-animated tab bar and
  segmented control.
- **System integration**: lock-screen / Control Center Now Playing info and
  remote commands, plus background audio playback.
- **Persistence**: favorites and recently-played survive relaunches
  (`UserDefaults`).

## Screens

| Screen | What's there |
| --- | --- |
| **Home** | Time-aware greeting, recently played carousel, featured playlist heroes, quick picks. |
| **Search** | Custom search field, browse-by-mood grid, live results. |
| **Library** | Animated segmented control across Playlists / Songs / Favorites. |
| **Now Playing** | Aurora background, breathing artwork, visualizer, scrubber, full transport, volume, queue. |
| **Queue** | Upcoming tracks with tap-to-jump. |
| **Playlist detail** | Gradient hero header with Play / Shuffle. |

## Architecture

```
App/            AudioPlayerApp            — @main entry point
Models/         Song, Playlist, PlaybackModels
Services/       AudioManager (engine)     — playback, queue, metering, remote controls
                MusicLibrary              — catalogue, playlists, favorites, recents
DesignSystem/   Theme, DesignComponents, Visualizer, MarqueeText
Views/          RootView, HomeView, SearchView, LibraryView,
                NowPlayingView, MiniPlayerView, QueueView,
                PlaylistDetailView, SongRow
```

`AudioManager` is a single `@MainActor` `ObservableObject` that owns the
`AVAudioPlayer`, publishes playback state, and advances the queue while
respecting shuffle and repeat modes. Views observe it (and `MusicLibrary`)
through the SwiftUI environment.
