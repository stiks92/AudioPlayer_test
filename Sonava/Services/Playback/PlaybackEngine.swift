//
//  PlaybackEngine.swift
//  Sonava
//
//  Two interchangeable playback backends behind one interface:
//  - LocalAudioEngine  : an AVAudioEngine graph for imported files, giving a
//                        real 10-band equalizer and true tap-based metering.
//  - RemoteAudioEngine : AVPlayer for network streams & live radio.
//
//  AudioManager picks a backend per track and never touches AVFoundation
//  directly.
//

import Foundation
import AVFoundation
import QuartzCore
import os

/// Playback is driven entirely from `AudioManager`, which is main-actor
/// isolated, and both backends touch UIKit-adjacent AVFoundation state.
/// Pinning the protocol to the main actor makes that contract explicit rather
/// than something every call site has to remember.
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
    func apply(_ equalizer: EqualizerSettings)
    func refresh()          // sampled by AudioManager's timer
    func teardown()
}

// MARK: - Local files (AVAudioEngine graph: player → EQ → timePitch → mixer)

final class LocalAudioEngine: PlaybackEngine {

    var onFinish: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: EqualizerBand.count)
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var totalFrames: AVAudioFramePosition = 0
    /// The file frame the current schedule began at — the base for position.
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var playing = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    /// Bumped on every (re)schedule so a stale completion callback — fired when
    /// we stop to seek — cannot be mistaken for a track finishing.
    private var scheduleGeneration = 0
    private var lastKnownTime: Double = 0

    /// Written by the render-thread metering tap, read on the main actor.
    private let levelBox = OSAllocatedUnfairLock<Float>(initialState: 0)

    var isLive: Bool { false }
    var isPlaying: Bool { playing }
    var duration: Double { totalFrames > 0 ? Double(totalFrames) / sampleRate : 0.001 }
    private(set) var level: CGFloat = 0

    var currentTime: Double {
        if playing,
           let nodeTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: nodeTime) {
            let played = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
            lastKnownTime = min(Double(segmentStartFrame) / sampleRate + played, duration)
        }
        return lastKnownTime
    }

    init() {
        configureBands()
        engine.attach(player)
        engine.attach(eq)
        engine.attach(timePitch)
    }

    private func configureBands() {
        for (index, band) in eq.bands.enumerated() where index < EqualizerBand.count {
            band.filterType = .parametric
            band.frequency = EqualizerBand.frequencies[index]
            band.bandwidth = 0.5   // octaves
            band.bypass = true
            band.gain = 0
        }
        eq.globalGain = 0
    }

    // MARK: Transport

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        teardown()
        do {
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            let format = audioFile.processingFormat
            sampleRate = format.sampleRate
            totalFrames = audioFile.length
            segmentStartFrame = 0
            lastKnownTime = 0

            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = volume
            timePitch.rate = clampRate(rate)

            installMeterTap()
            engine.prepare()
            try engine.start()

            scheduleFrom(0)
            playing = autoplay
            if autoplay { player.play() }
            return true
        } catch {
            print("LocalAudioEngine: \(error)")
            file = nil
            return false
        }
    }

    func play() {
        if !engine.isRunning { try? engine.start() }
        player.play()
        playing = true
    }

    func pause() {
        _ = currentTime            // latch position before the node stops advancing
        player.pause()
        playing = false
    }

    func seek(to time: Double) {
        guard file != nil else { return }
        let wasPlaying = playing
        let clamped = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(clamped * sampleRate)

        scheduleGeneration += 1
        player.stop()
        segmentStartFrame = startFrame
        lastKnownTime = clamped
        scheduleFrom(startFrame)
        if wasPlaying { player.play(); playing = true }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        engine.mainMixerNode.outputVolume = volume
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        timePitch.rate = clampRate(rate)
    }

    func apply(_ equalizer: EqualizerSettings) {
        let bypass = !equalizer.isEnabled
        eq.globalGain = bypass ? 0 : equalizer.preamp
        for (index, band) in eq.bands.enumerated() where index < EqualizerBand.count {
            band.bypass = bypass
            band.gain = bypass ? 0 : equalizer.gains[index]
        }
    }

    func refresh() {
        guard playing else { return }
        let rms = levelBox.withLock { $0 }
        // Typical music RMS sits around 0.05–0.35; scale into the 0…1 the
        // visualizer expects, then smooth so the bars breathe rather than jitter.
        let normalized = min(1, CGFloat(rms) * 3.2)
        level = level * 0.7 + normalized * 0.3
    }

    func teardown() {
        scheduleGeneration += 1
        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        playing = false
        level = 0
        levelBox.withLock { $0 = 0 }
    }

    // MARK: Scheduling

    private func scheduleFrom(_ startFrame: AVAudioFramePosition) {
        guard let file else { return }
        let remaining = AVAudioFrameCount(max(0, totalFrames - startFrame))
        guard remaining > 0 else { return }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: remaining,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.handleCompletion(generation) }
        }
    }

    private func handleCompletion(_ generation: Int) {
        // Only a completion for the still-current schedule, while we believe we
        // are playing, means the track actually reached its end.
        guard generation == scheduleGeneration, playing else { return }
        playing = false
        onFinish?()
    }

    // MARK: Metering

    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        let format = mixer.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }

        mixer.installTap(onBus: 0, bufferSize: 1_024, format: format) { [levelBox] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            let samples = channels[0]
            var sum: Float = 0
            for frame in 0..<frames {
                let sample = samples[frame]
                sum += sample * sample
            }
            let rms = (sum / Float(frames)).squareRoot()
            levelBox.withLock { $0 = rms }
        }
    }

    private func clampRate(_ rate: Float) -> Float {
        min(2.0, max(0.5, rate))
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

    /// AVPlayer exposes no insertable EQ node; equalizing a live stream needs an
    /// MTAudioProcessingTap, which is a separate piece of work. Streams play
    /// flat for now, and the EQ screen says so.
    func apply(_ equalizer: EqualizerSettings) {}

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
