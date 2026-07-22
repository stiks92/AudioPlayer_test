//
//  TestAudioFile.swift
//  SonavaTests
//
//  Generates real audio on the fly so import tests exercise AVFoundation
//  metadata reading for real. The repository deliberately ships no audio
//  fixtures — see the rights note in README.
//

import AVFoundation
import Foundation
@testable import Sonava

enum TestAudioFile {

    /// Writes a short tone to a unique temporary directory and returns its URL.
    /// The caller owns the directory and should `cleanUp` when done.
    static func makeTone(
        named name: String = "tone.m4a",
        seconds: Double = 1.0
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonavaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(name)
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(sampleRate * seconds)
              )
        else { throw CocoaError(.fileWriteUnknown) }

        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = 0.25 * sinf(2.0 * .pi * 440.0 * Float(frame) / Float(sampleRate))
        }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        try file.write(from: buffer)
        return url
    }

    static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Removes everything the app copied into its media directory, so import
    /// tests do not leak state into each other.
    @MainActor
    static func clearMediaDirectory() {
        let media = LocalFileStore.mediaDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? []
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
