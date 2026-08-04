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

    /// What the screen is lit with: the sleeve's own pixels once read
    /// (`AudioManager.sleeveHex`), the track's stored fallback pair until then.
    private var sleeve: [Color] { audio.sleeveHex?.colors ?? song?.gradient ?? [] }

    var body: some View {
        ZStack {
            // Flat ground, because the artwork is the colour.
            //
            // Three blurred blobs of the track's own palette washed the whole
            // screen, which meant a Blue Note sleeve and a Warp sleeve arrived
            // looking like the same purple record. Somebody with 12,431 files
            // needs the opposite: the sleeve doing the identifying.
            Color.black.ignoresSafeArea()
            // The reference ground: the track's colour glows from the top
            // and dissolves into pure black by mid-screen. Stops, not clips.
            LinearGradient(stops: [
                .init(color: (sleeve.first ?? Theme.accent).opacity(0.55), location: 0),
                .init(color: (sleeve.last ?? Theme.accentDeep).opacity(0.28), location: 0.22),
                .init(color: .black, location: 0.58)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(Motion.fade, value: song?.id)
            .animation(Motion.fade, value: audio.sleeveHex)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                artwork
                Spacer(minLength: 0)
                info
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
            Button { onClose() } label: {
                SonavaIcon(glyph: .chevronDown, size: 19, tint: .white.opacity(0.85))
                    .frame(width: Space.hitTarget, height: Space.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            Button { showQueue = true } label: {
                SonavaIcon(glyph: .more, size: 19, tint: .white.opacity(0.85))
                    .frame(width: Space.hitTarget, height: Space.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The disc: a circular cover inside a frosted lens, the progress as a
    /// luminous arc around it, the remaining time seated inside the glass —
    /// and the next records peeking from behind, the way the reference's
    /// carousel implies depth. Replaces the full-bleed square sleeve.
    private var artwork: some View {
        ZStack {
            // Neighbours peek out from behind the lens.
            HStack {
                if let left = audio.upNext.dropFirst().first {
                    ArtworkImage(song: left, glyphSize: 20)
                        .frame(width: 108, height: 108).clipShape(Circle())
                        .offset(x: -46).opacity(0.85)
                }
                Spacer()
                if let right = audio.upNext.first {
                    ArtworkImage(song: right, glyphSize: 20)
                        .frame(width: 108, height: 108).clipShape(Circle())
                        .offset(x: 46).opacity(0.85)
                }
            }
            // The lens.
            Circle().fill(.ultraThinMaterial)
                .frame(width: 316, height: 316)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
            // The arc is the scrubber's truth, and it is dressed the way the
            // reference dresses it: a luminous gradient trail from the track's
            // own palette into white, glowing softly, with a bright head at
            // its tip. When the duration is the unknown-sentinel (== 1) the
            // arc draws nothing rather than a lie.
            let arcProgress = clock.duration > 1 ? clock.progress : 0
            Circle().stroke(.white.opacity(0.10), lineWidth: 4)
                .frame(width: 272, height: 272)
            Circle().trim(from: 0, to: max(0.003, arcProgress))
                .stroke(
                    AngularGradient(
                        colors: [(sleeve.first ?? Theme.accentSoft).opacity(0.9),
                                 (sleeve.last ?? Theme.accent),
                                 .white],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.003, arcProgress))),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 272, height: 272)
                .shadow(color: (sleeve.first ?? Theme.accentSoft).opacity(0.7), radius: 7)
            // The head: a bright point riding the tip of the trail.
            if arcProgress > 0.004 {
                let theta = 2 * Double.pi * arcProgress - .pi / 2
                Circle().fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.9), radius: 6)
                    .offset(x: 136 * cos(theta), y: 136 * sin(theta))
            }
            // The record itself.
            if let song {
                ArtworkImage(song: song, glyphSize: 54)
                    .frame(width: 224, height: 224)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .opacity(audio.isPlaying ? 1 : 0.75)
                    .animation(Motion.fade, value: audio.isPlaying)
            }
            Text((clock.duration - clock.currentTime).asClock)
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .offset(y: 122)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
    }

    private var info: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                // Serif, because a person named this track. The rule the ramp
                // enforces: a human named it, so it is set in a book face; the
                // numbers below it are set in a machine face.
                MarqueeText(text: song?.title ?? "",
                            font: .system(.title).weight(.light))
                    .frame(height: 36)
                Button {
                    if song != nil { showArtist = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(song?.artist ?? "")
                            .font(.system(.callout))
                        SonavaIcon(glyph: .chevronRight, size: 12, tint: Theme.textTertiary)
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
                    SonavaIcon(glyph: .plus, size: 22)
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
            BareTransportButton(glyph: .previous, size: 30) {
                audio.previous()
            }
            Spacer()
            Button { audio.togglePlayPause() } label: {
                PlayPauseGlyph(isPlaying: audio.isPlaying, size: 50)
                    .frame(width: 84, height: 84)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.9))
            .accessibilityIdentifier("player.playPause")
            Spacer()
            BareTransportButton(glyph: .next, size: 30) {
                audio.next()
            }
            Spacer()
            Button {
                withAnimation { audio.cycleRepeat() }
            } label: {
                SonavaIcon(glyph: audio.repeatMode.glyph, size: 21,
                           tint: audio.repeatMode.isActive ? Theme.accentSoft : .white.opacity(0.7))
            }
            .buttonStyle(BouncyButtonStyle())
        }
    }

    private var volume: some View {
        HStack(spacing: Space.m) {
            SonavaIcon(glyph: .volumeLow, size: 16, tint: .white.opacity(0.6))
            ScrubberView(
                value: Binding(
                    get: { Double(audio.volume) },
                    set: { audio.volume = Float($0) }
                ),
                onEditingChanged: { _ in }
            )
            SonavaIcon(glyph: .volumeHigh, size: 16, tint: .white.opacity(0.6))
            // Where the sound goes, next to how loud it is.
            RoutePickerButton(tint: .white.opacity(0.6), size: 18)
                .frame(width: 30, height: 30)
                .accessibilityLabel(Text("Output device"))
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
