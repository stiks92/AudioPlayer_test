//
//  NowPlayingView.swift
//  Sonava
//
//  The full-screen "hero" player: animated aurora background driven by
//  the track palette, a breathing artwork, a live visualizer, a custom
//  scrubber, and a full transport.
//

import SwiftUI

struct NowPlayingView: View {
    let namespace: Namespace.ID
    let onClose: () -> Void

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showSleepOptions = false
    @State private var showAddToPlaylist = false
    @State private var showArtist = false
    @State private var shareItem: ShareableImage?

    private var song: Song? { audio.currentSong }

    var body: some View {
        ZStack {
            // Flat ground, because the artwork is the colour.
            //
            // Three blurred blobs of the track's own palette washed the whole
            // screen, which meant a Blue Note sleeve and a Warp sleeve arrived
            // looking like the same purple record. Somebody with 12,431 files
            // needs the opposite: the sleeve doing the identifying.
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                artwork
                Spacer(minLength: 0)
                info
                    .padding(.top, Space.l)
                scrubber
                    .padding(.top, Space.xl)
                visualizer
                    .padding(.top, Space.l)
                controls
                    .padding(.top, 8)
                bottomBar
                    .padding(.top, Space.xl)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
            .foregroundColor(.white)
        }
        .offset(y: dragOffset)
        .gesture(dismissDrag)
        .sheet(isPresented: $showQueue) {
            QueueView().environmentObject(audio).environmentObject(library)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView().environmentObject(audio).environmentObject(clock)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song {
                AddToPlaylistView(song: song).environmentObject(playlistStore)
            }
        }
        .sheet(isPresented: $showArtist) {
            if let song {
                ArtistView(artistName: song.artist, gradient: song.gradient)
                    .environmentObject(audio)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .confirmationDialog("Sleep timer", isPresented: $showSleepOptions, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) min") { audio.setSleepTimer(minutes: minutes) }
            }
            if audio.sleepTimerMinutes != nil {
                Button("Turn off", role: .destructive) { audio.setSleepTimer(minutes: nil) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { scrubValue = clock.progress }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.down", size: 42, iconSize: 16) {
                onClose()
            }
            .identified("player.collapse", label: "Collapse player")
            Spacer()
            // Was "PLAYING FROM ALBUM" over the album name — a centred caps
            // label duplicating a fact printed 26pt lower. What belongs here is
            // where the audio is coming from, which is the one thing this app
            // knows and a streaming client cannot.
            Text(provenance)
                .font(.sonavaStamp)
                .tracking(1.2)
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
            Spacer()
            CircleIconButton(systemName: "list.bullet", size: 42, iconSize: 16) {
                showQueue = true
            }
        }
    }

    /// The sleeve: full bleed, square, radius 0, no shadow.
    ///
    /// It is the only object in the app permitted to touch the trim, which is
    /// what stops it reading as a card the instant you see it. The 28pt radius
    /// and the coloured drop shadow were the two things that made it one.
    ///
    /// The 0.86 scale on pause is gone as well. A deck does not shrink its
    /// platter to tell you it stopped — the transport key does that, and it now
    /// does it by morphing. What marks the paused state here is a 22% black
    /// veil, which is a dimmed lamp rather than a shrinking record.
    private var artwork: some View {
        ZStack {
            if let song {
                ArtworkImage(song: song, glyphSize: 72)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(audio.isPlaying ? 0 : 0.22))
                    .animation(Motion.fade, value: audio.isPlaying)
            }
        }
        .padding(.horizontal, -Space.xl)
    }

    private var info: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                // Serif, because a person named this track. The rule the ramp
                // enforces: a human named it, so it is set in a book face; the
                // numbers below it are set in a machine face.
                MarqueeText(text: song?.title ?? "",
                            font: .system(.title, design: .serif).weight(.bold))
                    .frame(height: 34)
                Button {
                    if song != nil { showArtist = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(song?.artist ?? "")
                            .font(.sonavaAttribution)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2).weight(.semibold))
                            .opacity(0.6)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if audio.supportsPlaybackRate {
                speedMenu
            }
            if song != nil {
                Button {
                    showAddToPlaylist = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(.title2).weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(BouncyButtonStyle())
            }
            if let song {
                HeartButton(isOn: library.isFavorite(song), size: 24) {
                    withAnimation { library.toggleFavorite(song) }
                }
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.8, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button {
                    audio.setPlaybackRate(Float(rate))
                    Haptics.selection()
                } label: {
                    if audio.playbackRate == Float(rate) {
                        Label(String(format: "%g×", rate), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%g×", rate))
                    }
                }
            }
        } label: {
            Text(String(format: "%g×", Double(audio.playbackRate)))
                .font(.system(.footnote).weight(.bold))
                .foregroundColor(.white)
                .frame(minWidth: 40)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
        }
    }

    @ViewBuilder
    private var scrubber: some View {
        if audio.isLive {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.destructive)
                    .frame(width: 8, height: 8)
                    .opacity(audio.isPlaying ? 1 : 0.4)
                Text("LIVE")
                    .font(.system(.footnote).weight(.heavy))
                    .tracking(2)
                Spacer()
                Text("Radio")
                    .font(.system(.caption).weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(height: 24)
        } else {
            VStack(spacing: 6) {
                ScrubberView(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : clock.progress },
                        set: { scrubValue = $0 }
                    ),
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                        } else {
                            audio.seek(to: scrubValue * clock.duration)
                            isScrubbing = false
                        }
                    }
                )
                HStack {
                    Text((isScrubbing ? scrubValue * clock.duration : clock.currentTime).asClock)
                    Spacer()
                    Text(clock.duration.asClock)
                }
                .font(.system(.caption).weight(.medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var visualizer: some View {
        OutputMeter(level: clock.audioLevel,
                    metered: clock.isMetered,
                    isPlaying: audio.isPlaying)
    }

    private var controls: some View {
        HStack {
            Button {
                withAnimation { audio.toggleShuffle() }
            } label: {
                SonavaIcon(glyph: .shuffle, size: 20)
                    .font(.system(.body).weight(.semibold))
                    .foregroundColor(audio.isShuffling ? Theme.accentSoft : .white.opacity(0.7))
            }
            .buttonStyle(BouncyButtonStyle())
            Spacer()
            CircleIconButton(systemName: "backward.fill", size: 56, iconSize: 22) {
                audio.previous()
            }
            Spacer()
            PlayPauseButton(isPlaying: audio.isPlaying) {
                audio.togglePlayPause()
            }
            Spacer()
            CircleIconButton(systemName: "forward.fill", size: 56, iconSize: 22) {
                audio.next()
            }
            Spacer()
            Button {
                withAnimation { audio.cycleRepeat() }
            } label: {
                Image(systemName: audio.repeatMode.systemImage)
                    .font(.system(.body).weight(.semibold))
                    .foregroundColor(audio.repeatMode.isActive ? Theme.accentSoft : .white.opacity(0.7))
            }
            .buttonStyle(BouncyButtonStyle())
        }
    }

    private var volume: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "speaker.fill")
                .font(.system(.footnote))
                .foregroundColor(.white.opacity(0.6))
            ScrubberView(
                value: Binding(
                    get: { Double(audio.volume) },
                    set: { audio.volume = Float($0) }
                ),
                onEditingChanged: { _ in }
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(.footnote))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    /// Words, not glyphs.
    ///
    /// Four unlabelled SF Symbols sat here — a speech bubble, a moon, a share
    /// arrow and a list — and between them they were four guesses. The sleep
    /// entry now shows the countdown when a timer is armed, which is a fact the
    /// app already computes and previously rendered as a filled moon.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            barWord("Lyrics", active: false) { showLyrics = true }
            barWord(sleepWord, active: audio.sleepTimerMinutes != nil) { showSleepOptions = true }
            barWord("Share", active: false) {
                if let song { shareItem = ShareCardRenderer.render(song) }
            }
            barWord("Queue", active: false) { showQueue = true }
        }
    }

    private var sleepWord: LocalizedStringKey {
        guard let minutes = audio.sleepTimerMinutes else { return "Sleep" }
        return LocalizedStringKey("\(minutes) min")
    }

    private func barWord(_ title: LocalizedStringKey, active: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sonavaDepartment)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(active ? Theme.accentSoft : Theme.textSecondary)
                // Cyrillic in tracked caps runs far wider than Latin:
                // "ПОДЕЛИТЬСЯ" against "SHARE" broke across two lines with a
                // hyphen inside an equal-width column. One line, and it shrinks
                // rather than hyphenating.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bottomButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.body).weight(.semibold))
                .foregroundColor(active ? Theme.accentSoft : .white.opacity(0.7))
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Drag to dismiss

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 140 {
                    onClose()
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }
}

extension NowPlayingView {
    /// Where this audio is actually coming from, named as specifically as the
    /// app can truthfully name it.
    var provenance: String {
        guard let song else { return "" }
        if audio.downloads.isDownloaded(song) { return String(localized: "OFFLINE") }
        switch song.source {
        case .local:    return String(localized: "YOUR FILES")
        case .subsonic: return serverName ?? String(localized: "YOUR SERVER")
        case .radio:    return String(localized: "LIVE")
        default:        return song.source.badge ?? ""
        }
    }

    /// The app does not thread the server identity down to the player, and
    /// inventing one here would be a guess printed as a fact. The generic label
    /// is the honest fallback until it is plumbed.
    var serverName: String? { nil }
}
