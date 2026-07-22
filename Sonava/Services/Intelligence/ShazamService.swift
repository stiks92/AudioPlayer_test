//
//  ShazamService.swift
//  Sonava
//
//  "What's playing?" recognition via ShazamKit. Captures the mic, matches
//  against the Shazam catalogue, and restores the playback session when done.
//
//  Note: matching against the Shazam catalogue requires the ShazamKit
//  capability on the App ID, and NSMicrophoneUsageDescription in Info.plist.
//

import Foundation
import AVFoundation
import ShazamKit

@MainActor
final class ShazamService: NSObject, ObservableObject {

    struct Result: Equatable {
        let title: String
        let artist: String
        let artworkURL: URL?
        let appleMusicURL: URL?
    }

    enum State: Equatable {
        case idle
        case listening
        case noMatch
        case failed(String)
        case matched(Result)
    }

    @Published private(set) var state: State = .idle

    private let audioEngine = AVAudioEngine()
    private var session: SHSession?
    private var isRunning = false

    var isListening: Bool { if case .listening = state { return true } else { return false } }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        state = .listening
        let session = SHSession()
        session.delegate = self
        self.session = session
        requestPermissionAndListen()
    }

    func reset() {
        stop()
        state = .idle
    }

    private func requestPermissionAndListen() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.beginAudio()
                } else {
                    self.state = .failed("Microphone access is needed to recognize music.")
                }
            }
        }
    }

    private func beginAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            let capturedSession = session
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                capturedSession?.matchStreamingBuffer(buffer, at: time)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true

            // Give up gracefully after a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, self.isRunning, self.isListening else { return }
                self.stop()
                self.state = .noMatch
            }
        } catch {
            state = .failed("Couldn't start listening.")
            restoreSession()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        restoreSession()
    }

    private func restoreSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Best effort — playback session will be reset on next load.
        }
    }
}

// MARK: - SHSessionDelegate

extension ShazamService: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let result = Result(
            title: item.title ?? "Unknown title",
            artist: item.artist ?? "",
            artworkURL: item.artworkURL,
            appleMusicURL: item.appleMusicURL
        )
        Task { @MainActor in
            self.stop()
            self.state = .matched(result)
            Haptics.success()
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            guard self.isRunning else { return }
            self.stop()
            self.state = .noMatch
        }
    }
}
