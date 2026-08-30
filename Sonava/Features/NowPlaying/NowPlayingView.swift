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
    @ObservedObject private var scanner = PassportScanner.shared
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var proStore: ProStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var dragOffset: CGFloat = 0
    /// The record's interactive horizontal offset while a swipe is in flight.
    @State private var artDragX: CGFloat = 0
    /// The axis a drag on the artwork committed to with its first movement.
    /// Locked for the life of the gesture: a drag that starts vertical is a
    /// dismissal even if the finger later wanders sideways, and vice versa.
    @State private var artworkDragAxis: ArtworkDragAxis?
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
                .environmentObject(proStore)
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
            // Neighbours peek out from behind the lens: the records a swipe
            // would actually land on. Left is the *previous* track — the
            // promise a rightward swipe keeps — right is the next. They lean
            // slightly with the drag so the carousel reads as one row.
            HStack {
                if let left = audio.previousSong {
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
            .offset(x: artDragX * 0.3)
            // The lens.
            Circle().fill(.ultraThinMaterial)
                .frame(width: 316, height: 316)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
            // The arc is the scrubber's truth, and it is dressed the way the
            // reference dresses it: a luminous gradient trail from the track's
            // own palette into white, glowing softly, with a bright head at
            // its tip. When the duration is the unknown-sentinel (== 1) the
            // arc draws nothing rather than a lie. While a finger holds the
            // ring the arc draws the finger, not the clock — the head must
            // never fight its own hand.
            let arcProgress = isScrubbing ? scrubValue
                            : (clock.duration > 1 ? clock.progress : 0)
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
            // The record itself. It follows the finger sideways: the swipe
            // that changes tracks is this offset made honest.
            if let song {
                ArtworkImage(song: song, glyphSize: 54)
                    .frame(width: 224, height: 224)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .opacity(audio.isPlaying ? 1 : 0.75)
                    .animation(Motion.fade, value: audio.isPlaying)
                    .offset(x: artDragX)
                    .accessibilityElement()
                    .identified(AccessibilityID.playerDisc, label: "Now Playing")
                    .accessibilityValue(Text(verbatim: song.title))
            }
            // While scrubbing this is the destination, not the countdown —
            // the number the finger is choosing, seated in the glass.
            Text(isScrubbing ? (scrubValue * clock.duration).asClock
                             : (clock.duration - clock.currentTime).asClock)
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .offset(y: 122)
            // The scrub surface: an invisible donut over the arc. It sits on
            // top of everything so the ring always belongs to seeking, while
            // its hole leaves the record to the carousel. minimumDistance: 0
            // captures the touch before the root dismiss gesture's 10pt
            // threshold can.
            ringScrubSurface
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .contentShape(Rectangle())
        .gesture(artworkDrag)
    }

    /// Whether the ring can honestly seek: live streams cannot, and a
    /// duration of 0 (live sentinel) or 1 (unknown sentinel) has no timeline
    /// to scrub — the same condition that keeps the arc from drawing a lie.
    private var canScrubRing: Bool { clock.duration > 1 && !audio.isLive }

    /// The displayed position, for VoiceOver: the finger's while it holds the
    /// ring, the clock's otherwise.
    private var ringProgressForAccessibility: Double {
        isScrubbing ? scrubValue : clock.progress
    }

    private var ringScrubSurface: some View {
        Circle()
            .fill(Color.clear)
            .frame(width: 316, height: 316)
            .contentShape(RingHitShape(ringRadius: 136, hitWidth: Space.hitTarget),
                          eoFill: true)
            .gesture(ringScrubGesture, isEnabled: canScrubRing)
            .accessibilityElement()
            .identified(AccessibilityID.playerRing, label: "Progress")
            .accessibilityValue(Text(verbatim:
                "\(Int((ringProgressForAccessibility * 100).rounded()))%"))
            .accessibilityAdjustableAction { direction in
                guard canScrubRing else { return }
                let step: Double = direction == .increment ? 0.05 : -0.05
                let target = min(max(clock.progress + step, 0), 1)
                audio.seek(to: target * clock.duration)
            }
            // A seek control on a live stream would be a lie told to
            // VoiceOver specifically; the element withdraws instead.
            .accessibilityHidden(!canScrubRing)
    }

    /// "In your life since 2014 · 312 plays" — the imported biography's
    /// stitch to this exact song. The single line that makes twenty years of
    /// history feel attached to the file rather than trapped in a service.
    private func provenanceLine(for song: Song) -> String? {
        guard let entry = journeyStore.entry(for: song) else { return nil }
        let year = Calendar.current.component(.year,
            from: Date(timeIntervalSince1970: entry.firstListen))
        return String(localized: "In your life since \(String(year)) · \(entry.plays) plays")
    }

    /// "124 BPM · F♯m" from the track's passport — facts, so the machine
    /// face; absent until the Backroom has actually measured them. Reading
    /// `scanner.revision` keeps the line live as scans complete.
    private func passportLine(for song: Song) -> String? {
        _ = scanner.revision
        guard let passport = PassportStore.shared.passport(for: song.id) else { return nil }
        var parts: [String] = []
        if let bpm = passport.bpm, (passport.bpmConfidence ?? 0) >= 0.4 {
            parts.append(String(localized: "\(Int(bpm.rounded())) BPM"))
        }
        if let key = passport.musicalKey, key.confidence >= 0.15 {
            parts.append(key.label)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                // "FLAC · 320" — the audiophile's one question, answered in
                // the machine face because it is a measured fact. Absent
                // entirely when the source didn't report it: a quality badge
                // that guesses is worse than none.
                if let song {
                    let passport = passportLine(for: song)
                    if song.qualityParts.format != nil || song.qualityParts.kbps != nil || passport != nil {
                        HStack(spacing: 4) {
                            if let format = song.qualityParts.format {
                                Text(verbatim: format)
                            }
                            if let rate = song.qualityParts.kbps {
                                if song.qualityParts.format != nil { Text(verbatim: "·") }
                                Text("\(rate) kbps")
                            }
                            // The Backroom's first visible dividend: measured
                            // tempo and key, shown only once measured.
                            if let passport {
                                if song.qualityParts.format != nil || song.qualityParts.kbps != nil {
                                    Text(verbatim: "·")
                                }
                                Text(verbatim: passport)
                            }
                        }
                        .font(.sonavaFact)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 2)
                    }
                    if let provenance = provenanceLine(for: song) {
                        Text(verbatim: provenance)
                            .font(.sonavaFact)
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.top, 1)
                    }
                }
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

    // The dead `scrubber` (with its live pill), `visualizer` and `volume`
    // blocks that sat here unreferenced are gone: live playback has its own
    // screen now (`RadioLiveView` carries the LIVE stamp in `Theme.live`),
    // and the volume block lives on as the shared `VolumeRow` in
    // DesignComponents.

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

    /// The dismiss handlers stand alone so two gestures can share them: the
    /// root drag below, and the vertical branch of the artwork drag — a pull
    /// down that happens to start on the record must close the player exactly
    /// like a pull down anywhere else.
    private func dismissDragChanged(_ value: DragGesture.Value) {
        if value.translation.height > 0 {
            dragOffset = value.translation.height
        }
    }

    private func dismissDragEnded(_ value: DragGesture.Value) {
        if value.translation.height > 140 {
            onClose()
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = 0
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dismissDragChanged($0) }
            .onEnded { dismissDragEnded($0) }
    }

    // MARK: - Ring scrubbing

    /// Finger on the arc → position in the track. The donut's `contentShape`
    /// keeps this to the ring; the geometry lives in `RingScrubberGeometry`
    /// so it is testable as arithmetic.
    private var ringScrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canScrubRing else { return }
                let center = CGPoint(x: 158, y: 158)   // the 316pt surface's middle
                guard let raw = RingScrubberGeometry.progress(at: value.location,
                                                              center: center) else { return }
                if isScrubbing {
                    scrubValue = RingScrubberGeometry.resolved(raw: raw,
                                                               previous: scrubValue)
                } else {
                    isScrubbing = true
                    scrubValue = raw
                    Haptics.selection()
                }
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                audio.seek(to: scrubValue * clock.duration)
                isScrubbing = false
            }
    }

    // MARK: - Artwork swipe (carousel / dismiss)

    private enum ArtworkDragAxis { case horizontal, vertical }

    /// One gesture, two meanings, decided once. The first movement picks the
    /// axis and the gesture keeps it: mostly-horizontal drags drive the track
    /// carousel, anything else delegates to the dismiss handlers so the
    /// pull-down keeps working from the record itself.
    private var artworkDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let axis = artworkDragAxis
                    ?? (abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical)
                artworkDragAxis = axis
                switch axis {
                case .horizontal: artDragX = value.translation.width
                case .vertical: dismissDragChanged(value)
                }
            }
            .onEnded { value in
                let axis = artworkDragAxis
                artworkDragAxis = nil
                switch axis {
                case .horizontal: endArtworkSwipe(value)
                case .vertical, nil: dismissDragEnded(value)
                }
            }
    }

    private func endArtworkSwipe(_ value: DragGesture.Value) {
        let width = value.translation.width
        // Either a real displacement or a flick: a short, fast swipe is the
        // most common way people actually skip tracks.
        let commits = abs(width) > 60 || abs(value.velocity.width) > 500
        guard commits, audio.currentSong != nil else {
            withAnimation(Motion.standard) { artDragX = 0 }
            return
        }
        Haptics.selection()
        let forward = width < 0    // leftward swipe pushes the row left → next
        if reduceMotion {
            // No transit: the record changes in place (PlayerShell's pattern).
            artDragX = 0
            if forward { audio.next() } else { audio.previous() }
            return
        }
        // The record leaves in the direction of the throw, the incoming one
        // arrives from the other side — the neighbours made literal.
        let exit: CGFloat = forward ? -340 : 340
        withAnimation(Motion.standard, completionCriteria: .logicallyComplete) {
            artDragX = exit
        } completion: {
            if forward { audio.next() } else { audio.previous() }
            artDragX = -exit
            withAnimation(Motion.standard) { artDragX = 0 }
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
