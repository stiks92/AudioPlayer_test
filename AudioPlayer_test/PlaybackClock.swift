//
//  PlaybackClock.swift
//  AudioPlayer_test
//
//  High-frequency playback values (updated ~30×/sec) live here, separate
//  from AudioManager, so only the few views that show live time/level
//  (Now Playing, mini player, lyrics) re-render at that rate — not the
//  whole browse UI.
//

import SwiftUI

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var audioLevel: CGFloat = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func reset(duration: Double) {
        currentTime = 0
        audioLevel = 0
        self.duration = duration
    }
}
