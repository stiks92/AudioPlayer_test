//
//  AppleMusicEngine.swift
//  Sonava
//
//  MusicKit's ApplicationMusicPlayer wrapped in the app's own engine
//  protocol, so an Apple Music track slots into the same queue, the same
//  transport, the same Now Playing as everything else.
//
//  Honest boundaries: the audio runs in Apple's DRM player outside our
//  graph, so apply()/applyCorrection()/setLoudnessGain() are deliberate
//  no-ops here (the EQ screen states this per-source), the visualizer gets
//  a synthesised level like un-tappable HLS does, and there is no gapless
//  preload — Apple's player owns its own queue transitions.
//

import Foundation
@preconcurrency import MusicKit
import QuartzCore

@MainActor
final class AppleMusicEngine: PlaybackEngine {

    var onFinish: (() -> Void)?
    var onAdvancedToNext: (() -> Void)?

    private let player = ApplicationMusicPlayer.shared
    private var playing = false
    private var live = false
    private var lastDuration: Double = 1
    private(set) var level: CGFloat = 0
    private var finishWatchdog: Timer?

    var isLive: Bool { false }
    var isPlaying: Bool { playing }

    var currentTime: Double { player.playbackTime }

    var duration: Double {
        if let duration = player.queue.currentEntry?.item.flatMap({ item -> TimeInterval? in
            if case .song(let song) = item { return song.duration }
            return nil
        }) {
            lastDuration = duration
        }
        return max(lastDuration, 1)
    }

    /// Loads one catalogue song (by the id our Song carries) and plays it.
    /// The engine protocol's prepare() takes a URL, which Apple Music does
    /// not have — AudioManager calls this instead for `.appleMusic` tracks.
    func prepareCatalogSong(id: String, autoplay: Bool) async -> Bool {
        do {
            let request = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            guard let song = response.items.first else { return false }
            lastDuration = song.duration ?? 1
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            try await player.prepareToPlay()
            if autoplay {
                try await player.play()
                playing = true
            }
            startWatchdog()
            return true
        } catch {
            playing = false
            return false
        }
    }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        // Not this engine's door; AudioManager routes catalogue songs via
        // prepareCatalogSong.
        false
    }

    func play() {
        Task { try? await player.play() }
        playing = true
    }

    func pause() {
        player.pause()
        playing = false
    }

    func seek(to time: Double) {
        player.playbackTime = max(0, min(time, duration))
    }

    func setVolume(_ volume: Float) {
        // Apple's player follows the system volume; per-app volume is not
        // exposed. The slider still governs every other source.
    }

    func setRate(_ rate: Float) {}

    func apply(_ equalizer: EqualizerSettings) {}          // DRM: cannot touch
    func applyCorrection(_ profile: CorrectionProfile?) {} // DRM: cannot touch
    func setLoudnessGain(_ decibels: Double) {}            // DRM: cannot touch

    func refresh() {
        playing = player.state.playbackStatus == .playing
        guard playing else { level = 0; return }
        let t = CACurrentMediaTime()
        let synthetic = 0.45 + 0.22 * sin(t * 3.1) + 0.12 * sin(t * 7.3)
        level = level * 0.6 + CGFloat(synthetic) * 0.4
    }

    func teardown() {
        finishWatchdog?.invalidate()
        finishWatchdog = nil
        player.pause()
        playing = false
        level = 0
    }

    /// ApplicationMusicPlayer has no end-of-item callback; poll the status
    /// and report a finish when playback stops at the tail. Coarse, honest,
    /// and only running while this engine is active.
    private func startWatchdog() {
        finishWatchdog?.invalidate()
        finishWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playing else { return }
                let status = self.player.state.playbackStatus
                let nearEnd = self.currentTime >= self.duration - 1.2
                if status != .playing, nearEnd {
                    self.playing = false
                    self.finishWatchdog?.invalidate()
                    self.finishWatchdog = nil
                    self.onFinish?()
                }
            }
        }
    }
}
