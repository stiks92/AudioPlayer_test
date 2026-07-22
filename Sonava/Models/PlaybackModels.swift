//
//  PlaybackModels.swift
//  AudioPlayer_test
//
//  Small value types describing playback state.
//

import SwiftUI

/// How the queue behaves once a track finishes.
enum RepeatMode: Int, CaseIterable {
    case off
    case all
    case one

    var next: RepeatMode {
        RepeatMode(rawValue: (rawValue + 1) % RepeatMode.allCases.count) ?? .off
    }

    var systemImage: String {
        switch self {
        case .off, .all: return "repeat"
        case .one:       return "repeat.1"
        }
    }

    var isActive: Bool { self != .off }
}
