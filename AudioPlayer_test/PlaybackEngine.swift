//
//  PlaybackEngine.swift
//  AudioPlayer_test
//
//  Two interchangeable playback backends behind one interface:
//  - LocalAudioEngine  : AVAudioPlayer for bundled files (real metering)
//  - RemoteAudioEngine : AVPlayer for network streams & live radio
//

import Foundation
import AVFoundation
import QuartzCore

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
    func refresh()          // sampled by AudioManager's timer
    func teardown()
}

// MARK: - Local files (AVAudioPlayer + metering)

final class LocalAudioEngine: NSObject, PlaybackEngine, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private var player: AVAudioPlayer?
    private(set) var level: CGFloat = 0
    private var volume: Float = 0.75

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
            p.volume = volume
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

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
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
        let p = AVPlayer(playerItem: item)
        p.volume = volume
        player = p
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playing = false
            self?.onFinish?()
        }
        if autoplay { play() }
        return true
    }

    func play() { player?.play(); playing = true }
    func pause() { player?.pause(); playing = false }

    func seek(to time: Double) {
        guard !live else { return }
        player?.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    func setVolume(_ volume: Float) { self.volume = volume; player?.volume = volume }

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
