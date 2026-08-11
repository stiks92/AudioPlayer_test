//
//  RootView.swift
//  Sonava
//
//  Hosts the tab scenes, the docked mini player and the expanding
//  Now Playing overlay.
//

import SwiftUI
import StoreKit

struct RootView: View {
    @StateObject private var audio = AudioManager.shared
    @StateObject private var library = MusicLibrary()
    @StateObject private var proStore = ProStore()
    @StateObject private var serverStore = ServerStore()
    @StateObject private var playlistStore = PlaylistStore()
    @StateObject private var reviewPrompt = ReviewPrompt()
    @StateObject private var scrobbleStore = ScrobbleStore()
    @StateObject private var cloudStore = CloudStore()
    @StateObject private var history = ListeningHistory()

    /// Observed so the whole tree re-renders (and re-reads Theme.accent) when
    /// the palette changes.
    @ObservedObject private var theme = ThemeManager.shared

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasOnboarded.v1") private var hasOnboarded = false
    @State private var selection: AppTab = .home
    @State private var showNowPlaying = false
    /// Shared by the mini player's thumbnail and the full player's cover, so
    /// the artwork travels between them instead of one fading into the other.
    @Namespace private var playerTransition
    #if DEBUG
    @State private var debugShowEqualizer = false
    @State private var debugShowPaywall = false
    @State private var debugShowAIMix = false
    @State private var debugShowIcons = false
    @State private var debugShowAnimLab = false
    @State private var debugShowAlbum = false
    @State private var debugShowArtist = false
    @State private var debugShowQueue = false
    @State private var debugShowScrobble = false
    @State private var debugShowStats = false
    @State private var debugShowServers = false
    @State private var debugShowSettings = false
    #endif

    private let playerSpring = Animation.spring(response: 0.45, dampingFraction: 0.86)

    var body: some View {
        ZStack {
            // The system tab bar: it supplies Liquid Glass, 44pt targets and
            // the contract-on-scroll behaviour that a hand-rolled bar cannot.
            TabView(selection: $selection) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Tab(value: tab) {
                        view(for: tab)
                            .opaqueBottomScrollEdge()
                    } label: {
                        // The app's own glyphs, not the system's. A tab bar is
                        // the one row where five icons are read side by side,
                        // so it is where a borrowed set is most obvious — and
                        // where the old one mixed two stroke weights.
                        Label {
                            Text(tab.title)
                        } icon: {
                            if let raster = IconRaster.image(tab.glyph, size: 24) {
                                Image(uiImage: raster)
                            } else {
                                SonavaIcon(glyph: tab.glyph, size: 22)
                            }
                        }
                    }
                }
            }
            // Without this the system bar tints itself blue and the app's
            // whole palette stops at the tab bar. `accentSoft`, not `accent`:
            // on the selection pill the accent measured 3.44:1, so the one tab
            // that must be identifiable was the least legible thing in the bar.
            .tint(Theme.accentSoft)
            .modifier(MiniPlayerSlot(isHidden: showNowPlaying,
                                      namespace: playerTransition) {
                withAnimation(playerSpring) { showNowPlaying = true }
            })


            if showNowPlaying {
                // The genie. The shell grows out of the capsule's spot and
                // shrinks back into it — see PlayerShell for why this morphs
                // one container instead of flying geometry across the
                // accessory boundary.
                PlayerShell { showNowPlaying = false }
                    .zIndex(2)
            }
        }
        .environmentObject(audio)
        .environmentObject(audio.clock)
        .environmentObject(library)
        .environmentObject(proStore)
        .environmentObject(serverStore)
        .environmentObject(playlistStore)
        .environmentObject(scrobbleStore)
        .environmentObject(cloudStore)
        .environmentObject(history)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            WelcomeFlow { hasOnboarded = true }
                .environmentObject(proStore)
        }
        .sheet(isPresented: $proStore.isShowingPaywall) {
            PaywallView().environmentObject(proStore)
        }
        #if DEBUG
        // Lets a launch argument deep-link straight to a screen, so a specific
        // view can be driven or screenshotted without walking the UI.
        .sheet(isPresented: $debugShowEqualizer) {
            EqualizerView(effects: audio.effects).environmentObject(proStore).environmentObject(audio)
        }
        .sheet(isPresented: $debugShowPaywall) {
            PaywallView().environmentObject(proStore)
        }
        .sheet(isPresented: $debugShowAIMix) {
            AIMixView()
                .environmentObject(audio)
                .environmentObject(library)
                .environmentObject(proStore)
        }
        .sheet(isPresented: $debugShowIcons) { IconGallery() }
        .sheet(isPresented: $debugShowAnimLab) {
            #if DEBUG
            AnimatedIconLab()
            #endif
        }
        .sheet(isPresented: $debugShowQueue) {
            QueueView()
                .environmentObject(audio)
                .environmentObject(library)
                .environmentObject(proStore)
        }
        .sheet(isPresented: $debugShowArtist) {
            if let song = library.songs.first {
                ArtistView(artistName: song.artist, gradient: song.gradient)
                    .environmentObject(audio)
                    .environmentObject(library)
                    .environmentObject(playlistStore)
            }
        }
        .sheet(isPresented: $debugShowAlbum) {
            if let album = library.albums.first {
                NavigationStack { AlbumView(album: album) }
                    .environmentObject(audio)
                    .environmentObject(library)
            }
        }
        .sheet(isPresented: $debugShowScrobble) {
            ConnectScrobbleView().environmentObject(scrobbleStore)
        }
        .sheet(isPresented: $debugShowStats) {
            StatsView()
                .environmentObject(history)
                .environmentObject(proStore)
        }
        .sheet(isPresented: $debugShowServers) {
            ConnectServerView()
                .environmentObject(serverStore)
                .environmentObject(proStore)
        }
        .sheet(isPresented: $debugShowSettings) {
            SettingsView()
                .environmentObject(audio)
                .environmentObject(proStore)
                .environmentObject(serverStore)
                .environmentObject(scrobbleStore)
                .environmentObject(library)
                .environmentObject(playlistStore)
        }
        .task { applyDebugLaunchRoute() }
        #endif
        .onChange(of: audio.currentSong) { _, song in
            if let song {
                library.markPlayed(song)
                reviewPrompt.record(.trackFinished)   // active listening is a good signal
                audio.tasteProfile = library.tasteProfile   // keep endless radio on-taste
                audio.recentlyHeard = library.recents       // so shuffle stops replaying them
                scrobbleStore.scrobbleNowPlaying(song)
            }
        }
        .task {
            // Scrobble a completed listen on natural track end (not on skips).
            audio.onTrackCompleted = { scrobbleStore.scrobbleListen($0) }
            // Log listening time for the stats screen. Repeated calls carry the
            // same session id, so the store updates that listen in place.
            audio.onListenProgress = { song, seconds, session in
                history.record(song: song, seconds: seconds, session: session)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground may mean suspension without another tick,
            // so bank the in-flight listen and get it onto disk — writes while
            // playing are batched and one may still be pending.
            if phase != .active {
                audio.flushListeningTime()
                history.save()
            }
        }
        .onChange(of: playlistStore.playlists.count) { old, new in
            if new > old { reviewPrompt.record(.playlistCreated) }
        }
        .onChange(of: reviewPrompt.shouldPresent) { _, ready in
            guard ready else { return }
            requestReview()
            reviewPrompt.markPresented()
        }
        .onChange(of: selection) { _, _ in
            Haptics.selection()
        }
        .onOpenURL { url in
            // A shared playlist link: import it and take the user to Library.
            // Server tracks come back through *this* device's own credentials
            // for that host — the link never carried the sender's.
            if let shared = PlaylistSharing.playlist(from: url, resolver: {
                host, trackID, title, artist, album, duration in
                serverStore.resolveSharedTrack(host: host, trackID: trackID,
                                               title: title, artist: artist,
                                               album: album, duration: duration)
            }) {
                playlistStore.importShared(shared)
                selection = .library
            }
        }
        .task {
            audio.restoreLastSession()
            // Endless radio and "Made for you" build from the listener's own
            // server first — the best station material they have is the one
            // they already own.
            StationService.serverSearch = { [weak serverStore] query in
                guard let service = await MainActor.run(body: { serverStore?.service }) else { return [] }
                return (try? await service.search(query)) ?? []
            }
        }
        .onChange(of: proStore.isPro, initial: true) { _, pro in
            theme.enforceFreeIfNeeded(isPro: pro)   // don't keep a paid palette if Pro lapses
            serverStore.isPro = pro                 // extra servers stay saved, just unreachable
            cloudStore.isPro = pro                  // same rule for cloud drives
            AppIconManager.shared.enforceFreeIfNeeded(isPro: pro)
        }
    }

    @ViewBuilder
    private func view(for tab: AppTab) -> some View {
        switch tab {
        case .home:     HomeView()
        case .search:   SearchView()
        case .radio:    RadioView()
        case .podcasts: PodcastsView()
        case .library:  LibraryView()
        }
    }

    #if DEBUG
    /// Honours launch arguments used only to drive screens for screenshots and
    /// UI tests: `-openTab <name>`, `-demoPlay`, `-openNowPlaying`,
    /// `-openEqualizer`. No effect in a normal run.
    private func applyDebugLaunchRoute() {
        let arguments = CommandLine.arguments

        if let index = arguments.firstIndex(of: "-openTab"),
           index + 1 < arguments.count,
           let tab = AppTab(rawValue: arguments[index + 1]) {
            selection = tab
        }

        if arguments.contains("-seedPassports") {
            // Review fixture: the Backroom line on Now Playing needs a
            // passport to exist, and demo tracks are not files the scanner
            // can measure. Values are plausible, marked as fixture data.
            for song in library.songs.prefix(24) {
                PassportStore.shared.save(TrackPassport(
                    contentKey: "demo-fixture",
                    durationSeconds: song.durationSeconds ?? 200,
                    loudnessLUFS: -11.2,
                    bpm: 124, bpmConfidence: 0.9,
                    beatGrid: nil,
                    musicalKey: MusicalKey(tonic: 6, isMinor: true, confidence: 0.5),
                    analyzedAt: Date()), for: song.id)
            }
        }
        if arguments.contains("-demoPlay") {
            // Prefer the user's own files; fall back to the demo catalogue so
            // the player is reviewable on a device with an empty library.
            let queue = library.songs.isEmpty ? DemoCatalog.trending : library.songs
            if let first = queue.first { audio.play(first, in: queue) }
        }

        if arguments.contains("-openNowPlaying"), audio.currentSong != nil {
            showNowPlaying = true
        }

        if arguments.contains("-openEqualizer") { debugShowEqualizer = true }
        // Lets a screenshot show a real curve instead of a flat line.
        if let index = arguments.firstIndex(of: "-eqPreset"),
           index + 1 < arguments.count,
           let preset = EqualizerPreset.preset(id: arguments[index + 1]) {
            audio.effects.apply(preset)
        }
        if arguments.contains("-openPaywall") { debugShowPaywall = true }
        if arguments.contains("-openAIMix") { debugShowAIMix = true }
        // The icon set on one sheet, so the family can be judged as a
        // family rather than one glyph at a time on five screens.
        if arguments.contains("-openIcons") { debugShowIcons = true }
        if arguments.contains("-openAnimLab") { debugShowAnimLab = true }
        // Straight to the first record, for screenshots of the album screen —
        // simctl cannot tap, so a route is the only scriptable way in.
        if arguments.contains("-openAlbum") { debugShowAlbum = true }
        if arguments.contains("-openArtist") { debugShowArtist = true }
        if arguments.contains("-openQueue") { debugShowQueue = true }
        // Seeds a believable playback position for design captures: the demo
        // stream never resolves a duration, so without this every frame shows
        // 0:01 and an empty arc.
        if let index = arguments.firstIndex(of: "-demoProgress"),
           index + 1 < arguments.count, let fraction = Double(arguments[index + 1]) {
            audio.clock.reset(duration: 243, metered: true)
            audio.clock.currentTime = 243 * min(max(fraction, 0), 1)
        }
        // Forces any palette, including the paid ones, so a whole screen can
        // be reviewed in each rather than compared as hex values.
        if let index = arguments.firstIndex(of: "-palette"), index + 1 < arguments.count {
            ThemeManager.shared.select(ThemePalette.palette(id: arguments[index + 1]))
        }
        if arguments.contains("-openScrobble") { debugShowScrobble = true }
        // Stats need a history to show, so seeding is offered alongside.
        if arguments.contains("-seedStats") { history.seedDemoData() }
        if arguments.contains("-openStats") { debugShowStats = true }

        if let index = arguments.firstIndex(of: "-seedServers"),
           index + 1 < arguments.count,
           let count = Int(arguments[index + 1]) {
            serverStore.seedDemoServers(count: count)
        }
        if arguments.contains("-openServers") { debugShowServers = true }
        if arguments.contains("-openSettings") { debugShowSettings = true }
        // The chosen home-screen icon is system state that outlives the app, so
        // a test that changes it would otherwise poison the next one.
        if arguments.contains("-resetAppIcon") {
            AppIconManager.shared.select(.aurora)
        }
    }
    #endif
}

// MARK: - Tabs

enum AppTab: String, CaseIterable {
    case home, search, radio, podcasts, library

    var title: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .radio: return "Radio"
        case .podcasts: return "Podcasts"
        case .library: return "Library"
        }
    }

    /// The app's own glyph for each tab.
    ///
    /// Replaced a mixed set of system symbols — two filled, three hairline —
    /// where the right half of the bar was visibly heavier than the left. One
    /// family, one stroke, drawn on one grid.
    var glyph: SonavaIcon.Glyph {
        switch self {
        case .home: return .home
        case .search: return .search
        case .radio: return .radio
        case .podcasts: return .podcasts
        case .library: return .library
        }
    }
}

/// Places the mini player in the right slot for the running OS.
///
/// iOS 26 has a slot designed for exactly this — the tab view's bottom
/// accessory — which brings the glass, the shadow and the morph into the
/// contracted tab bar with it. Below that we float the player ourselves in a
/// bottom safe-area inset, which is the closest the older layout can get.
private struct MiniPlayerSlot: ViewModifier {
    /// Hidden while the full player is up: the same track would otherwise be
    /// on screen twice.
    let isHidden: Bool
    let namespace: Namespace.ID
    let onExpand: () -> Void

    @EnvironmentObject private var audio: AudioManager

    private var isVisible: Bool { audio.currentSong != nil && !isHidden }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .tabViewBottomAccessory {
                    if isVisible {
                        MiniPlayerView(style: .accessory, namespace: namespace, onExpand: onExpand)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content.safeAreaInset(edge: .bottom) {
                if isVisible {
                    MiniPlayerView(style: .docked, namespace: namespace, onExpand: onExpand)
                        .transition(.opacity)
                }
            }
        }
    }
}

