//
//  PlaybackEngine.swift
//  Sonava
//
//  Two interchangeable playback backends behind one interface:
//  - LocalAudioEngine  : AVAudioPlayer for bundled files (real metering)
//  - RemoteAudioEngine : AVPlayer for network streams & live radio
//

import Foundation
import AVFoundation
import QuartzCore

/// Playback is driven entirely from `AudioManager`, which is main-actor
/// isolated, and both backends touch UIKit-adjacent AVFoundation state.
/// Pinning the protocol to the main actor makes that contract explicit
/// rather than something every call site has to remember.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onFinish: (() -> Void)? { get set }
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var level: CGFloat { get }
    var isLive: Bool { get }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool
    func play()
    func pause()
    func seek(to time: Double)
    func setVolume(_ volume: Float)
    func setRate(_ rate: Float)   // playback speed (podcasts)
    func refresh()          // sampled by AudioManager's timer
    func teardown()
}

// MARK: - Local files (AVAudioPlayer + metering)

final class LocalAudioEngine: NSObject, PlaybackEngine, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private var player: AVAudioPlayer?
    private(set) var level: CGFloat = 0
    private var volume: Float = 0.75
    private var rate: Float = 1.0

    var isLive: Bool { false }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: Double { player?.currentTime ?? 0 }
    var duration: Double { max(player?.duration ?? 1, 0.001) }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.isMeteringEnabled = true
            p.enableRate = true
            p.volume = volume
            p.rate = rate
            p.prepareToPlay()
            player = p
            level = 0
            if autoplay { p.play() }
            return true
        } catch {
            print("LocalAudioEngine: \(error)")
            player = nil
            return false
        }
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(to time: Double) { player?.currentTime = max(0, min(time, duration)) }
    func setVolume(_ volume: Float) { self.volume = volume; player?.volume = volume }

    func setRate(_ rate: Float) {
        self.rate = rate
        player?.enableRate = true
        if player?.isPlaying == true { player?.rate = rate }
    }

    func refresh() {
        guard let player = player, player.isPlaying else { return }
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)      // ~ -160...0 dB
        let normalized = max(0, (power + 55) / 55)
        level = level * 0.75 + CGFloat(normalized) * 0.25
    }

    func teardown() {
        player?.stop()
        player?.delegate = nil
        player = nil
        level = 0
    }

    // AVAudioPlayer calls its delegate on the run loop that started playback —
    // always the main one here — but the protocol itself is not isolated, so
    // the conformance has to be `nonisolated` and assert the actor.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated { onFinish?() }
    }
}

// MARK: - Network streams & live radio (AVPlayer)

final class RemoteAudioEngine: NSObject, PlaybackEngine {
    var onFinish: (() -> Void)?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var playing = false
    private var live = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    private(set) var level: CGFloat = 0

    var isLive: Bool { live }
    var isPlaying: Bool { playing }

    var currentTime: Double {
        let t = player?.currentTime().seconds ?? 0
        return t.isFinite ? t : 0
    }

    var duration: Double {
        guard let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 else {
            return live ? 0 : 1
        }
        return d
    }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        teardown()
        live = isLive
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain   // natural voice at higher speeds
        let p = AVPlayer(playerItem: item)
        p.volume = volume
        player = p
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            // Posted on .main by the queue above, so this is already the
            // main actor — assert it instead of hopping and losing ordering.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playing = false
                self.onFinish?()
            }
        }
        if autoplay { play() }
        return true
    }

    func play() {
        playing = true
        // Setting rate resumes playback; live streams always play at 1×.
        player?.rate = live ? 1.0 : rate
    }

    func pause() { player?.pause(); playing = false }

    func seek(to time: Double) {
        guard !live else { return }
        player?.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    func setVolume(_ volume: Float) { self.volume = volume; player?.volume = volume }

    func setRate(_ rate: Float) {
        self.rate = rate
        if playing && !live { player?.rate = rate }
    }

    func refresh() {
        // AVPlayer exposes no metering; synthesise a gentle animated level.
        guard playing else { level = 0; return }
        let t = CACurrentMediaTime()
        let synthetic = 0.45 + 0.22 * sin(t * 3.1) + 0.12 * sin(t * 7.3)
        level = level * 0.6 + CGFloat(synthetic) * 0.4
    }

    func teardown() {
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
        playing = false
        level = 0
    }
}
