//
//  PlaybackModels.swift
//  Sonava
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

    var glyph: SonavaIcon.Glyph {
        self == .one ? .repeatOne : .repeatAll
    }

    var isActive: Bool { self != .off }
}
