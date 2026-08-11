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
    /// The engine started the *preloaded* track without stopping — playback
    /// never paused, so the app must catch its state up rather than load
    /// anything. Only the local engine can do this; see `preloadNext`.
    var onAdvancedToNext: (() -> Void)? { get set }
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
    /// Per-track levelling, dB. Kept apart from `setVolume` on purpose: the
    /// listener's volume and the track's correction are different facts, and
    /// folding them together would make the slider mean something different
    /// on every track.
    func setLoudnessGain(_ decibels: Double)
    func setRate(_ rate: Float)   // playback speed (podcasts)
    func apply(_ equalizer: EqualizerSettings)
    /// Headphone-correction profile, applied before the user's EQ.
    func applyCorrection(_ profile: CorrectionProfile?)
    func refresh()          // sampled by AudioManager's timer
    func teardown()

    /// Queues the next track so it begins the sample after this one ends.
    /// Returns whether the engine could do it — a format change, a stream, or
    /// an unreadable file all mean "no", and the caller falls back to loading
    /// the track the ordinary way.
    @discardableResult
    func preloadNext(url: URL) -> Bool
    /// Forgets anything queued — the queue changed under us.
    func cancelPreload()
}

extension PlaybackEngine {
    @discardableResult
    func preloadNext(url: URL) -> Bool { false }
    func cancelPreload() {}
    /// Both engines implement this now — the local one through its EQ node's
    /// global gain, the remote one through the stream processing tap — so the
    /// default is only a formality for tests' stub engines.
    func setLoudnessGain(_ decibels: Double) {}
    func applyCorrection(_ profile: CorrectionProfile?) {}
}

// MARK: - Local files (AVAudioEngine graph: player → EQ → timePitch → mixer)

final class LocalAudioEngine: PlaybackEngine {

    var onFinish: (() -> Void)?
    var onAdvancedToNext: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 10 user bands + up to 14 correction slots (12 peaks + 2 shelves).
    /// AVAudioUnitEQ's band count is fixed at init, so the headroom is
    /// allocated up front and unused slots stay bypassed.
    private static let correctionSlots = 14
    private let eq = AVAudioUnitEQ(numberOfBands: EqualizerBand.count + LocalAudioEngine.correctionSlots)
    private var correctionPreampDB: Double = 0
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var totalFrames: AVAudioFramePosition = 0
    /// The file frame the current schedule began at — the base for position.
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var playing = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    /// Per-track levelling in dB, and the listener's own pre-amp. The EQ unit
    /// offers a single `globalGain`, so these are summed rather than
    /// overwriting each other.
    private var loudnessGain: Double = 0
    private var preamp: Float = 0
    /// Bumped whenever the node is *stopped* — seek, prepare, teardown — so a
    /// completion callback from the discarded run cannot be mistaken for a
    /// track finishing. It is deliberately not bumped when queueing the next
    /// track, because that schedule must stay valid alongside the current one.
    private var scheduleGeneration = 0
    /// Identifies one scheduled segment within a run.
    private var lastSegmentID = 0
    private var playingSegmentID = 0
    /// The track queued to start the instant this one ends — the whole of
    /// gapless playback.
    private var preloaded: (id: Int, file: AVAudioFile)?
    /// Frames of this uninterrupted run already spent on *earlier* tracks.
    /// The node's clock keeps running across queued segments, so without this
    /// the second track of a gapless pair would report the first track's
    /// elapsed time as its own.
    private var runOffsetFrames: AVAudioFramePosition = 0
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
            let ownFrames = max(0, playerTime.sampleTime - runOffsetFrames)
            let played = Double(ownFrames) / playerTime.sampleRate
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
        for (index, band) in eq.bands.enumerated() {
            if index < EqualizerBand.count {
                band.filterType = .parametric
                band.frequency = EqualizerBand.frequencies[index]
                band.bandwidth = 0.5   // octaves
            }
            band.bypass = true
            band.gain = 0
        }
        eq.globalGain = 0
    }

    /// Correction lives in the slots after the user's ten. The remote tap
    /// runs the same profile through exact RBJ shelves; AVAudioUnitEQ's
    /// shelf filters take no Q, so the two paths differ slightly in shelf
    /// slope — a known, inaudible-in-practice seam, documented rather than
    /// hidden.
    func applyCorrection(_ profile: CorrectionProfile?) {
        let slots = EqualizerBand.count..<eq.bands.count
        for index in slots {
            eq.bands[index].bypass = true
            eq.bands[index].gain = 0
        }
        correctionPreampDB = 0
        if let profile, profile.isEnabled {
            correctionPreampDB = profile.preampDB
            for (offset, band) in profile.bands.prefix(Self.correctionSlots).enumerated() {
                let slot = eq.bands[EqualizerBand.count + offset]
                switch band.kind {
                case .peaking:
                    slot.filterType = .parametric
                    // AVAudioUnitEQ wants bandwidth in octaves; convert Q.
                    slot.bandwidth = Float((2 / log(2)) * asinh(1 / (2 * max(band.q, 0.1))))
                case .lowShelf:
                    slot.filterType = .lowShelf
                case .highShelf:
                    slot.filterType = .highShelf
                }
                slot.frequency = Float(min(band.frequency, 20_000))
                slot.gain = Float(band.gainDB)
                slot.bypass = false
            }
        }
        applyGlobalGain()
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

    func setLoudnessGain(_ decibels: Double) {
        loudnessGain = decibels
        applyGlobalGain()
    }

    func apply(_ equalizer: EqualizerSettings) {
        let bypass = !equalizer.isEnabled
        preamp = bypass ? 0 : equalizer.preamp
        applyGlobalGain()
        for (index, band) in eq.bands.enumerated() where index < EqualizerBand.count {
            band.bypass = bypass
            band.gain = bypass ? 0 : equalizer.gains[index]
        }
    }

    /// Clamped to the unit's own ±24 dB range. Writing the levelling straight
    /// to the node instead would work until the next EQ change silently
    /// undid it.
    private func applyGlobalGain() {
        eq.globalGain = Float(min(max(Double(preamp) + loudnessGain + correctionPreampDB, -24), 24))
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
        preloaded = nil
        runOffsetFrames = 0
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
        // Any queued follow-on belonged to the schedule being replaced.
        preloaded = nil
        runOffsetFrames = 0
        let remaining = AVAudioFrameCount(max(0, totalFrames - startFrame))
        guard remaining > 0 else { return }

        lastSegmentID += 1
        playingSegmentID = lastSegmentID
        schedule(file, from: startFrame, frames: remaining, id: playingSegmentID)
    }

    private func schedule(_ file: AVAudioFile, from startFrame: AVAudioFramePosition,
                          frames: AVAudioFrameCount, id: Int) {
        let generation = scheduleGeneration
        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frames,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.handleCompletion(generation: generation, segment: id) }
        }
    }

    /// Queues the next track behind the current one.
    ///
    /// `AVAudioPlayerNode` renders queued segments back to back with no gap at
    /// all, which is the entire trick — but only while the format stays put,
    /// because the node is connected to the graph with one format. A rate or
    /// channel-count change means the ordinary load path has to run, and the
    /// half-second it costs is honest: the hardware really is being
    /// reconfigured.
    @discardableResult
    func preloadNext(url: URL) -> Bool {
        guard let current = file, preloaded == nil else { return false }
        guard let next = try? AVAudioFile(forReading: url) else { return false }

        let a = current.processingFormat, b = next.processingFormat
        guard a.sampleRate == b.sampleRate,
              a.channelCount == b.channelCount,
              a.commonFormat == b.commonFormat else { return false }

        let frames = AVAudioFrameCount(next.length)
        guard frames > 0 else { return false }

        lastSegmentID += 1
        preloaded = (id: lastSegmentID, file: next)
        schedule(next, from: 0, frames: frames, id: lastSegmentID)
        return true
    }

    func cancelPreload() {
        // The scheduled segment cannot be un-queued without stopping the node,
        // which would break the gapless join we are protecting. Dropping the
        // reference is enough: when the current track ends, the completion
        // finds nothing queued and reports a finish, and `AudioManager` loads
        // whatever the queue now says — the extra audio is stopped by that
        // load, not heard.
        preloaded = nil
    }

    private func handleCompletion(generation: Int, segment: Int) {
        // A completion from a discarded run (we stopped to seek) means nothing.
        guard generation == scheduleGeneration, playing else { return }
        guard segment == playingSegmentID else { return }

        if let next = preloaded {
            // The node is already rendering the queued track: nothing to
            // start, only bookkeeping to catch up.
            runOffsetFrames += max(0, totalFrames - segmentStartFrame)
            file = next.file
            totalFrames = next.file.length
            sampleRate = next.file.processingFormat.sampleRate
            segmentStartFrame = 0
            lastKnownTime = 0
            playingSegmentID = next.id
            preloaded = nil
            onAdvancedToNext?()
            return
        }

        playing = false
        onFinish?()
    }

    // MARK: Metering

    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        let format = mixer.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        // Install from a nonisolated context: AVAudioEngine invokes the tap on
        // its realtime render thread, and a closure built here in @MainActor
        // scope would trap Swift 6's executor check the instant audio flows.
        Self.installMeterTap(on: mixer, format: format, into: levelBox)
    }

    nonisolated private static func installMeterTap(
        on mixer: AVAudioMixerNode,
        format: AVAudioFormat,
        into levelBox: OSAllocatedUnfairLock<Float>
    ) {
        mixer.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
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
    /// Never called: AVPlayer item transitions are not gapless, so the remote
    /// engine always reports a plain finish and lets the app load the next
    /// track.
    var onAdvancedToNext: (() -> Void)?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var playing = false
    private var live = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    private(set) var level: CGFloat = 0

    /// The EQ + loudness processor for AVPlayer content. Attached per item;
    /// reports whether it actually landed so the UI can tell the truth.
    private let tap = StreamProcessingTap()
    private var equalizer = EqualizerSettings()
    private var loudnessGainDB: Double = 0
    /// Forwarded to AudioManager: true while the current stream is actually
    /// being processed (progressive HTTP yes, HLS no).
    var onProcessingChange: ((Bool) -> Void)? {
        get { tap.onAttachChange }
        set { tap.onAttachChange = newValue }
    }

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
        // The curve must be in the DSP before the first buffer, not after:
        // a stream that opens flat and snaps into shape a second later is
        // exactly the kind of seam a listener notices once and distrusts.
        tap.dsp.update(settings: equalizer, loudnessGainDB: loudnessGainDB)
        MainActor.assumeIsolated { tap.attach(to: item) }
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

    func apply(_ equalizer: EqualizerSettings) {
        self.equalizer = equalizer
        tap.dsp.update(settings: equalizer, loudnessGainDB: loudnessGainDB)
    }

    func applyCorrection(_ profile: CorrectionProfile?) {
        tap.dsp.updateCorrection(profile)
    }

    func setLoudnessGain(_ decibels: Double) {
        loudnessGainDB = decibels
        tap.dsp.update(settings: equalizer, loudnessGainDB: decibels)
    }

    func refresh() {
        guard playing else { level = 0; return }
        let measured = tap.dsp.drainLevel()
        if tap.isAttached, measured > 0 {
            // The real level, measured in the tap — same scaling and smoothing
            // as the local engine, so the meter doesn't change personality
            // when the source does.
            let normalized = min(1, CGFloat(measured) * 3.2)
            level = level * 0.55 + normalized * 0.45
        } else {
            // No tap on this stream (HLS): synthesise a gentle level rather
            // than freeze the meter — but only then.
            let t = CACurrentMediaTime()
            let synthetic = 0.45 + 0.22 * sin(t * 3.1) + 0.12 * sin(t * 7.3)
            level = level * 0.6 + CGFloat(synthetic) * 0.4
        }
    }

    func teardown() {
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        MainActor.assumeIsolated { tap.detach() }
        player?.pause()
        player = nil
        playing = false
        level = 0
    }
}
