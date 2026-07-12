//
//  AudioManager.swift
//  AudioPlayer_test
//
//  The playback engine. Wraps AVAudioPlayer, drives a live audio-level
//  meter for the visualizer, manages the queue / shuffle / repeat, and
//  integrates with the system Now Playing controls & lock screen.
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
        didSet { player?.volume = volume }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: - Private

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var baseQueue: [Song] = []
    private var currentIndex = 0

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
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlayingInfo()
    }

    func next() {
        advance(auto: false)
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        load(autoplay: true)
    }

    func seek(to time: Double) {
        guard let player = player else { return }
        let target = min(max(0, time), duration)
        player.currentTime = target
        currentTime = target
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
            // Reached the natural end of the queue — rewind and stop.
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
            print("AudioManager: missing file for \(song.fileName)")
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.isMeteringEnabled = true
            newPlayer.volume = volume
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration > 0 ? newPlayer.duration : 1
            currentTime = 0
            audioLevel = 0
            if autoplay {
                play()
            } else {
                isPlaying = false
                stopTimer()
            }
        } catch {
            print("AudioManager: failed to load \(song.fileName): \(error)")
        }
        updateNowPlayingInfo()
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
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let image = UIImage(named: song.artworkName) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Metering timer

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
        guard let player = player else { return }
        currentTime = player.currentTime
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)   // ~ -160...0 dB
        let normalized = max(0, (power + 55) / 55)        // → ~0...1
        audioLevel = audioLevel * 0.75 + CGFloat(normalized) * 0.25
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.advance(auto: true)
        }
    }
}
