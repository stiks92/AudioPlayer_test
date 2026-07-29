//
//  PlaybackClock.swift
//  Sonava
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

    /// Whether `audioLevel` is a measurement or a decoration.
    ///
    /// `LocalAudioEngine` installs a real RMS tap on the output node.
    /// `RemoteAudioEngine` cannot — `AVPlayer` exposes no metering — so it
    /// synthesises a level from two sine waves. That was fine while the level
    /// only drove an ornament, and dishonest the moment anything is read from
    /// it: on every stream and every radio station the meter was animating
    /// arithmetic, not audio.
    ///
    /// So the meter asks first. When this is false it draws a flat line and
    /// says there is no signal, which is what a piece of hardware does with
    /// nothing on the input — and it makes the moving needle mean something
    /// specific: you are playing a file you own.
    @Published var isMetered = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func reset(duration: Double, metered: Bool = false) {
        currentTime = 0
        audioLevel = 0
        isMetered = metered
        self.duration = duration
    }
}
