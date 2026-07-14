//
//  NowPlayingView.swift
//  AudioPlayer_test
//
//  The full-screen "hero" player: animated aurora background driven by
//  the track palette, a breathing artwork, a live visualizer, a custom
//  scrubber, and a full transport.
//

import SwiftUI

struct NowPlayingView: View {
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
            AuroraBackground(colors: song?.gradient ?? [Theme.accent, Theme.background],
                             animated: audio.isPlaying)
                .animation(.easeInOut(duration: 0.8), value: song)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                artwork
                Spacer(minLength: 0)
                info
                    .padding(.top, 18)
                scrubber
                    .padding(.top, 22)
                visualizer
                    .padding(.top, 18)
                controls
                    .padding(.top, 8)
                volume
                    .padding(.top, 22)
                bottomBar
                    .padding(.top, 22)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 26)
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
                Button("\(minutes) \(L("min"))") { audio.setSleepTimer(minutes: minutes) }
            }
            if audio.sleepTimerMinutes != nil {
                Button(L("Turn off"), role: .destructive) { audio.setSleepTimer(minutes: nil) }
            }
            Button(L("Cancel"), role: .cancel) {}
        }
        .onAppear { scrubValue = clock.progress }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.down", size: 42, iconSize: 16) {
                onClose()
            }
            Spacer()
            VStack(spacing: 2) {
                Text(L("PLAYING FROM ALBUM"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.5)
                Text(song?.album ?? "")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            CircleIconButton(systemName: "list.bullet", size: 42, iconSize: 16) {
                showQueue = true
            }
        }
    }

    private var artwork: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if let song {
                    ArtworkImage(song: song, glyphSize: 72)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: song.gradient.first?.opacity(0.6) ?? .black, radius: 34, y: 20)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(audio.isPlaying ? 1 : 0.86)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audio.isPlaying)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: 360)
    }

    private var info: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: song?.title ?? "", font: .system(size: 24, weight: .bold))
                    .frame(height: 30)
                Button {
                    if song != nil { showArtist = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(song?.artist ?? "")
                            .font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 22, weight: .semibold))
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
                .font(.system(size: 13, weight: .bold))
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
                    .fill(Color(hex: 0xFF3B6B))
                    .frame(width: 8, height: 8)
                    .opacity(audio.isPlaying ? 1 : 0.4)
                Text(L("LIVE"))
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(2)
                Spacer()
                Text(L("Radio"))
                    .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var visualizer: some View {
        AudioVisualizerView(level: clock.audioLevel, isActive: audio.isPlaying, tint: .white)
            .frame(height: 40)
            .opacity(0.9)
    }

    private var controls: some View {
        HStack {
            Button {
                withAnimation { audio.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(audio.repeatMode.isActive ? Theme.accentSoft : .white.opacity(0.7))
            }
            .buttonStyle(BouncyButtonStyle())
        }
    }

    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            ScrubberView(
                value: Binding(
                    get: { Double(audio.volume) },
                    set: { audio.volume = Float($0) }
                ),
                onEditingChanged: { _ in }
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            bottomButton("quote.bubble", active: false) { showLyrics = true }
            Spacer()
            bottomButton("moon.zzz\(audio.sleepTimerMinutes != nil ? ".fill" : "")",
                         active: audio.sleepTimerMinutes != nil) {
                showSleepOptions = true
            }
            Spacer()
            bottomButton("square.and.arrow.up", active: false) {
                if let song { shareItem = ShareCardRenderer.render(song) }
            }
            Spacer()
            bottomButton("list.bullet", active: false) { showQueue = true }
            Spacer()
        }
    }

    private func bottomButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
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
