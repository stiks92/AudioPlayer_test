//
//  RadioLiveView.swift
//  Sonava
//
//  The radio booth: the full-screen player a live stream deserves.
//
//  The track player is built around a timeline — a progress arc, a countdown
//  in the glass, a seek ring — and a live stream has none of those things.
//  Rendering a station through that screen printed a frozen "0:00" and an
//  empty arc: two small lies per frame. This screen replaces the timeline
//  with the facts a broadcast honestly has: a closed ring (the air has no
//  ends), a LIVE stamp, the stream's real state, the station's ICY
//  now-playing line when it sends one, and the time *this listener* has been
//  tuned in — a measurement about the session, not a guess about the stream.
//
//  Honesty rules carried over from the rest of the app: the ring breathes
//  only while the processing tap is measuring real RMS
//  (`audio.streamProcessingActive`); when the tap could not attach (HLS) the
//  ring holds still and the meter says NO METER. Nothing on this screen
//  animates arithmetic.
//

import SwiftUI
import Accessibility

struct RadioLiveView: View {
    let namespace: Namespace.ID
    let onClose: () -> Void

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var proStore: ProStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var dragOffset: CGFloat = 0
    @State private var showStations = false
    @State private var showSleepOptions = false
    @State private var shareItem: ShareableImage?
    /// When this listening session began — reset on every station change.
    @State private var tunedInAt = Date()

    private var song: Song? { audio.currentSong }

    /// The sleeve's own colours once read, the station's stored pair until
    /// then — the same source every surface takes its colour from.
    private var sleeve: [Color] { audio.sleeveHex?.colors ?? song?.gradient ?? [] }

    // MARK: - Screen state

    /// The booth's five faces: the engine's four honest stream states plus
    /// the listener's own stop, which is about the transport, not the stream.
    private enum BoothState { case connecting, buffering, onAir, dropped, stopped }

    private var boothState: BoothState {
        if audio.liveState == .dropped { return .dropped }
        if !audio.isPlaying { return .stopped }
        switch audio.liveState {
        case .connecting: return .connecting
        case .buffering:  return .buffering
        case .onAir, .dropped: return .onAir
        }
    }

    /// The lens contracts at accessibility type sizes so the words keep room.
    private var lensSide: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 316 }
    private var ringSide: CGFloat { lensSide - 44 }
    private var discSide: CGFloat { lensSide - 92 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // The reference ground: the station's colour glows from the top
            // and dissolves into pure black by mid-screen.
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
                lens
                Spacer(minLength: 0)
                identity
                    .padding(.top, Space.l)
                icyRow
                    .padding(.top, Space.s)
                meterAndStatus
                    .padding(.top, Space.m)
                transport
                    .padding(.top, 8)
                VolumeRow(showsRoutePicker: false)
                    .padding(.top, Space.m)
                bottomBar
                    .padding(.top, Space.l)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
            .foregroundColor(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.radioLive)
        .offset(y: dragOffset)
        .gesture(dismissDrag)
        .onAppear { tunedInAt = Date() }
        .onChange(of: song?.id) { _, _ in tunedInAt = Date() }
        .onChange(of: audio.liveState) { _, state in
            announce(state)
        }
        .sheet(isPresented: $showStations) {
            StationsSheet()
                .environmentObject(audio)
                .environmentObject(library)
                .environmentObject(proStore)
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
    }

    // MARK: - Zone 1 · Header

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
            // Provenance, radio-grade: where the signal is from, with the
            // live dot in the one colour that means "broadcasting now".
            HStack(spacing: 6) {
                Circle().fill(Theme.live).frame(width: 6, height: 6)
                Text(verbatim: provenanceStamp)
                    .font(.sonavaStamp)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            .foregroundColor(Theme.textTertiary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: provenanceStamp))
            Spacer()
            stationMenu
        }
    }

    private var provenanceStamp: String {
        let live = String(localized: "LIVE")
        guard let subtitle = song?.artist, !subtitle.isEmpty else { return live }
        return "\(live) · \(subtitle.uppercased())"
    }

    private var stationMenu: some View {
        Menu {
            if let song {
                Button {
                    withAnimation { library.toggleFavorite(song) }
                } label: {
                    Text(library.isFavorite(song) ? "Remove favourite" : "Add to favourites")
                }
                Button {
                    shareItem = ShareCardRenderer.render(song)
                } label: {
                    Text("Share")
                }
            }
        } label: {
            SonavaIcon(glyph: .more, size: 19, tint: .white.opacity(0.85))
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Zone 2 · The lens

    private var lens: some View {
        ZStack {
            // Neighbours peek out from behind the lens: the stations a
            // next/previous would actually land on — the hint that the dial
            // turns. Hidden at accessibility sizes to give the lens room.
            if !dynamicTypeSize.isAccessibilitySize {
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
                .accessibilityHidden(true)
            }
            // The lens — the family signature, unchanged.
            Circle().fill(.ultraThinMaterial)
                .frame(width: lensSide, height: lensSide)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
            // The ether ring: closed — no trim, no head — because the air has
            // no timeline. It breathes only from a measured level.
            etherRing
            // The station's disc.
            if let song {
                RadioDiscView(song: song, side: discSide)
                    .opacity(discOpacity)
                    .animation(Motion.fade, value: boothState)
                    .accessibilityHidden(true)
            }
            // Where the track player seats its countdown, the booth seats the
            // one word that is true instead.
            liveBadge
                .offset(y: lensSide * 0.386)
        }
        .frame(maxWidth: .infinity)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : 360)
        .animation(Motion.fade, value: song?.id)
    }

    private var discOpacity: Double {
        switch boothState {
        case .connecting:        return 0.6
        case .dropped, .stopped: return 0.75
        case .buffering, .onAir: return 1
        }
    }

    /// True only when there is a real number to breathe from.
    private var ringBreathes: Bool {
        boothState == .onAir && audio.streamProcessingActive && !reduceMotion
    }

    private var ringOpacity: Double {
        switch boothState {
        case .connecting: return 0.15
        case .buffering:  return 0.35
        case .stopped:    return 0.20
        case .dropped:    return 1        // drawn as the dead grey backing below
        case .onAir:      return ringBreathes ? 0.35 + Double(clock.audioLevel) * 0.55 : 0.35
        }
    }

    @ViewBuilder
    private var etherRing: some View {
        if boothState == .dropped {
            // The signal is gone; the ring goes out to the empty backing.
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 4)
                .frame(width: ringSide, height: ringSide)
                .accessibilityHidden(true)
        } else {
            let head = sleeve.first ?? Theme.accentSoft
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [head, sleeve.last ?? Theme.accent, head],
                        center: .center),
                    lineWidth: 4)
                .frame(width: ringSide, height: ringSide)
                .opacity(ringOpacity)
                .shadow(color: head.opacity(ringBreathes ? 0.7 : 0.35),
                        radius: ringBreathes ? 4 + clock.audioLevel * 6 : 4)
                .animation(Motion.fade, value: boothState)
                .accessibilityHidden(true)
        }
    }

    /// The pulse point and the word LIVE, in the glass. The dot moves only
    /// while something is actually happening on air, and Reduce Motion holds
    /// it still without hiding the fact it stands for.
    private var liveBadge: some View {
        HStack(spacing: 6) {
            if boothState != .connecting {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: dotIsStatic)) { timeline in
                    let phase = dotPhase(at: timeline.date.timeIntervalSinceReferenceDate)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(phase.scale)
                        .opacity(phase.opacity)
                }
                .frame(width: 10, height: 10)
            }
            Text("LIVE")
                .font(.sonavaStamp)
                .tracking(1.6)
        }
        .foregroundColor(.white.opacity(0.85))
        .accessibilityHidden(true)   // the status line below carries this fact
    }

    private var dotIsStatic: Bool {
        reduceMotion || !(boothState == .onAir || boothState == .buffering)
    }

    private var dotColor: Color {
        switch boothState {
        case .onAir, .buffering, .connecting: return Theme.live
        case .dropped, .stopped:              return .white.opacity(0.35)
        }
    }

    private func dotPhase(at t: TimeInterval) -> (scale: CGFloat, opacity: Double) {
        switch boothState {
        case .onAir:
            guard !reduceMotion else { return (1, 1) }
            let wave = 0.5 + 0.5 * sin(t * 2 * .pi / 2)      // 2 s pulse
            return (1 + 0.12 * wave, 0.75 + 0.25 * wave)
        case .buffering:
            guard !reduceMotion else { return (1, 0.5) }
            let wave = 0.5 + 0.5 * sin(t * 2 * .pi / 1.2)    // 1.2 s blink
            return (1, 0.5 + 0.5 * wave)
        default:
            return (1, 1)
        }
    }

    // MARK: - Zone 3 · Station identity

    private var identity: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: song?.title ?? "",
                            font: .system(.title).weight(.light))
                    .frame(height: 36)
                Text(verbatim: song?.artist ?? "")
                    .font(.system(.callout))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                // "AAC+ · 256 kbps" — only when the directory reported it.
                // A quality badge that guesses is worse than none.
                if let song,
                   song.qualityParts.format != nil || song.qualityParts.kbps != nil {
                    HStack(spacing: 4) {
                        if let format = song.qualityParts.format {
                            Text(verbatim: format)
                        }
                        if let rate = song.qualityParts.kbps {
                            if song.qualityParts.format != nil { Text(verbatim: "·") }
                            Text("\(rate) kbps")
                        }
                    }
                    .font(.sonavaFact)
                    .foregroundColor(Theme.textTertiary)
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.radioStation)
            .accessibilityLabel(Text(verbatim: stationAccessibilityLabel))
            .accessibilityValue(icyAccessibilityValue)
            .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 8)
            if let song {
                HeartButton(isOn: library.isFavorite(song), size: 24) {
                    withAnimation { library.toggleFavorite(song) }
                }
                .accessibilityIdentifier(AccessibilityID.radioHeart)
                .accessibilityLabel(Text("Favourite station"))
                .accessibilityAddTraits(library.isFavorite(song) ? .isSelected : [])
                // "1"/"0" rather than a word: the UI test reads this across
                // both languages, and VoiceOver already has the trait above.
                .accessibilityValue(Text(verbatim: library.isFavorite(song) ? "1" : "0"))
            }
        }
    }

    private var stationAccessibilityLabel: String {
        [song?.title, song?.artist]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }

    private var icyAccessibilityValue: Text {
        guard let icy = audio.liveNowPlaying else { return Text(verbatim: "") }
        return Text("Now playing: \(icy)")
    }

    // MARK: - Zone 4 · ICY now-playing

    /// Appears only when the station actually says what it is playing. The
    /// fixed-height slot keeps the vertical rhythm when it says nothing.
    private var icyRow: some View {
        ZStack {
            if let icy = audio.liveNowPlaying {
                HStack(spacing: Space.s) {
                    SonavaIcon(glyph: .note, size: 12, tint: Theme.textTertiary)
                    MarqueeText(text: icy,
                                font: .system(.subheadline),
                                color: .white.opacity(0.75))
                        .frame(height: 20)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(Motion.standard, value: audio.liveNowPlaying)
        .accessibilityHidden(true)   // spoken as the station element's value
    }

    // MARK: - Zone 5 · Instrument + status

    private var meterAndStatus: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            OutputMeter(level: clock.audioLevel,
                        metered: audio.streamProcessingActive,
                        isPlaying: audio.isPlaying,
                        caption: audio.streamProcessingActive ? "RMS · STREAM" : "NO METER · STREAM")
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                statusText(now: timeline.date)
                    .font(.sonavaStamp)
                    .tracking(1.2)
                    .foregroundColor(boothState == .dropped ? Theme.warning : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.radioStatus)
            .accessibilityLabel(Text("Air"))
            .accessibilityValue(statusAccessibilityValue)
        }
    }

    private func statusText(now: Date) -> Text {
        switch boothState {
        case .connecting: return Text("CONNECTING…")
        case .buffering:  return Text("BUFFERING…")
        case .dropped:    return Text("SIGNAL LOST")
        case .stopped:    return Text("TUNED OUT")
        case .onAir:
            return Text("ON AIR · IN TUNE \(max(0, now.timeIntervalSince(tunedInAt)).asClock)")
        }
    }

    private var statusAccessibilityValue: Text {
        switch boothState {
        case .connecting: return Text("Connecting")
        case .buffering:  return Text("Buffering")
        case .dropped:    return Text("Signal lost")
        case .stopped:    return Text("Tuned out")
        case .onAir:      return Text("On air")
        }
    }

    private func announce(_ state: LiveStreamState) {
        guard audio.isLive else { return }
        let phrase: String
        switch state {
        case .connecting: phrase = String(localized: "Connecting")
        case .buffering:  phrase = String(localized: "Buffering")
        case .onAir:      phrase = String(localized: "On air")
        case .dropped:    phrase = String(localized: "Signal lost")
        }
        AccessibilityNotification.Announcement(phrase).post()
    }

    // MARK: - Zone 6 · Transport

    private var transport: some View {
        HStack {
            // For a broadcast, where the sound goes outranks shuffle.
            RoutePickerButton(tint: .white.opacity(0.7), size: 20)
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .accessibilityLabel(Text("Output device"))
            Spacer()
            BareTransportButton(glyph: .previous, size: 30) {
                audio.previous()
            }
            .accessibilityIdentifier(AccessibilityID.radioPrevious)
            .accessibilityLabel(Text("Previous station"))
            Spacer()
            // Play/stop, not play/pause: resuming a live stream rejoins the
            // live edge, so the honest pair is tune in / tune out. After a
            // drop the play face *is* the retry.
            Button { audio.togglePlayPause() } label: {
                ZStack {
                    if audio.isPlaying {
                        SonavaIcon(glyph: .stop, size: 50).transition(.opacity)
                    } else {
                        SonavaIcon(glyph: .play, size: 50).transition(.opacity)
                    }
                }
                .animation(Motion.fade, value: audio.isPlaying)
                .frame(width: 84, height: 84)
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.9))
            .accessibilityIdentifier(AccessibilityID.radioPlayStop)
            .accessibilityLabel(Text(audio.isPlaying ? "Stop" : "Play"))
            Spacer()
            BareTransportButton(glyph: .next, size: 30) {
                audio.next()
            }
            .accessibilityIdentifier(AccessibilityID.radioNext)
            .accessibilityLabel(Text("Next station"))
            Spacer()
            Button { showSleepOptions = true } label: {
                Text(sleepWord)
                    .font(.sonavaDepartment)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(audio.sleepTimerMinutes != nil ? Theme.accentSoft : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Space.hitTarget + 8, height: Space.hitTarget + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Zone 8 · Words

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barWord("Stations", active: false) { showStations = true }
            barWord(sleepWord, active: audio.sleepTimerMinutes != nil) { showSleepOptions = true }
            barWord("Share", active: false) {
                if let song { shareItem = ShareCardRenderer.render(song) }
            }
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drag to dismiss

    /// The same physics the track player uses: a pull past 140pt closes the
    /// booth, anything less springs back.
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

// MARK: - The station's disc

/// The station pressed as a record: its own gradient as the vinyl, the
/// favicon as a small centre label — never stretched to fill the disc,
/// because favicons are 32–64px squares and a lens-sized blow-up is mush.
/// No favicon (or it fails): the radio glyph over the gradient, exactly the
/// fallback every missing cover in the app already wears.
struct RadioDiscView: View {
    let song: Song
    var side: CGFloat = 224

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: song.gradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url = song.artworkURL {
                AsyncImage(url: url,
                           transaction: Transaction(animation: .easeOut(duration: 0.35))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: side * 0.4, height: side * 0.4)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    case .empty, .failure:
                        fallbackGlyph
                    @unknown default:
                        fallbackGlyph
                    }
                }
            } else {
                fallbackGlyph
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

    private var fallbackGlyph: some View {
        SonavaIcon(glyph: .radio, size: side * 0.24, tint: .white.opacity(0.9))
    }
}

// MARK: - The dial

/// Every station on the current dial — the queue behind next/previous —
/// as plain rows. Tap to tune.
private struct StationsSheet: View {
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(audio.queue) { station in
                            Button {
                                audio.playFromQueue(station)
                            } label: {
                                SongRow(song: station)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.top, Space.m)
                }
            }
            .navigationTitle(Text("Stations"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
        }
        .preferredColorScheme(.dark)
    }
}
