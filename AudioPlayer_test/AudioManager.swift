//
//  AudioManager.swift
//  AudioPlayer_test
//
//  The playback engine orchestrator. Manages the queue / shuffle / repeat,
//  delegates actual audio to a LocalAudioEngine (bundled files) or a
//  RemoteAudioEngine (network streams & radio), drives the visualizer level,
//  and integrates with the system Now Playing controls & lock screen.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AudioManager: NSObject, ObservableObject {

    static let shared = AudioManager()

    // MARK: - Published state

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var queue: [Song] = []
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffling = false
    /// Smoothed 0...1 output level used to drive the visualizer.
    @Published var audioLevel: CGFloat = 0
    @Published var volume: Float = 0.75 {
        didSet { activeEngine?.setVolume(volume) }
    }
    @Published private(set) var playbackRate: Float = 1.0

    var isLive: Bool { currentSong?.isLive ?? false }

    /// Speed control is only meaningful for spoken-word content (podcasts).
    var supportsPlaybackRate: Bool { currentSong?.source == .podcast }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        activeEngine?.setRate(rate)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: - Private

    private let localEngine = LocalAudioEngine()
    private let remoteEngine = RemoteAudioEngine()
    private var activeEngine: PlaybackEngine?
    private var timer: Timer?
    private var baseQueue: [Song] = []
    private var currentIndex = 0

    // Sleep timer
    @Published private(set) var sleepTimerMinutes: Int?
    private var sleepTimer: Timer?
    private var sleepFireDate: Date?

    var sleepRemaining: TimeInterval? {
        guard let sleepFireDate else { return nil }
        return max(0, sleepFireDate.timeIntervalSinceNow)
    }

    private override init() {
        super.init()
        configureSession()
        setupRemoteCommands()
    }

    // MARK: - Public transport

    /// Starts playback of `song`, using `context` as the surrounding queue.
    func play(_ song: Song, in context: [Song]) {
        baseQueue = context
        if isShuffling {
            let rest = context.filter { $0 != song }.shuffled()
            queue = [song] + rest
            currentIndex = 0
        } else {
            queue = context
            currentIndex = context.firstIndex(of: song) ?? 0
        }
        load(autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard activeEngine != nil else { return }
        activeEngine?.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        activeEngine?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlayingInfo()
    }

    func next() {
        advance(auto: false)
    }

    func previous() {
        if !isLive && currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        load(autoplay: true)
    }

    func seek(to time: Double) {
        guard !isLive else { return }
        activeEngine?.seek(to: time)
        currentTime = min(max(0, time), duration)
        updateNowPlayingInfo()
    }

    /// Jump straight to a specific song already inside the queue.
    func playFromQueue(_ song: Song) {
        guard let idx = queue.firstIndex(of: song) else { return }
        currentIndex = idx
        load(autoplay: true)
    }

    // MARK: - Modes

    func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    func toggleShuffle() {
        isShuffling.toggle()
        guard let current = currentSong else { return }
        if isShuffling {
            let rest = baseQueue.filter { $0 != current }.shuffled()
            queue = [current] + rest
            currentIndex = 0
        } else {
            queue = baseQueue
            currentIndex = queue.firstIndex(of: current) ?? 0
        }
    }

    // MARK: - Loading

    private func advance(auto: Bool) {
        guard !queue.isEmpty else { return }
        if auto && repeatMode == .one {
            seek(to: 0)
            play()
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            load(autoplay: true)
        } else if repeatMode == .off && auto {
            currentIndex = 0
            load(autoplay: false)
        } else {
            currentIndex = 0
            load(autoplay: true)
        }
    }

    private func load(autoplay: Bool) {
        guard queue.indices.contains(currentIndex) else { return }
        let song = queue[currentIndex]
        currentSong = song

        guard let url = song.url else {
            print("AudioManager: missing URL for \(song.id)")
            return
        }

        // Swap to the correct backend for this track.
        let engine: PlaybackEngine = song.isRemote ? remoteEngine : localEngine
        if activeEngine !== engine { activeEngine?.teardown() }
        activeEngine = engine
        engine.onFinish = { [weak self] in
            Task { @MainActor in self?.advance(auto: true) }
        }
        engine.setVolume(volume)

        currentTime = 0
        audioLevel = 0
        duration = song.isLive ? 0 : 1

        // Speed persists across podcast episodes but resets for music/radio.
        if song.source != .podcast { playbackRate = 1.0 }

        let ok = engine.prepare(url: url, isLive: song.isLive, autoplay: autoplay)
        if ok {
            engine.setRate(playbackRate)
            isPlaying = autoplay
            if autoplay { startTimer() } else { stopTimer() }
        } else {
            isPlaying = false
            stopTimer()
        }
        updateNowPlayingInfo()
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutes = minutes
        guard let minutes, minutes > 0 else {
            sleepFireDate = nil
            return
        }
        let interval = Double(minutes) * 60
        sleepFireDate = Date().addingTimeInterval(interval)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sleepTimerFired() }
        }
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }

    private func sleepTimerFired() {
        pause()
        setSleepTimer(minutes: nil)
    }

    // MARK: - Session & remote

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioManager: session error \(error)")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: song.isLive
        ]
        if !song.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if !song.isRemote, let image = UIImage(named: song.artworkName) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Sampling timer

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let engine = activeEngine else { return }
        engine.refresh()
        currentTime = engine.currentTime
        let d = engine.duration
        duration = (d.isFinite && d > 0) ? d : (isLive ? 0 : 1)
        audioLevel = engine.level
    }
}
