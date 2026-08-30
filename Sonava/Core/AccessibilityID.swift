//
//  AccessibilityID.swift
//  Sonava
//
//  Stable identifiers for the controls UI tests drive. Shared by the app and
//  the test target so the two can never drift — the alternative is tests that
//  match on visible text, which breaks the moment a string is translated.
//
//  Identifiers are for automation. The `accessibilityLabel` alongside each one
//  is for VoiceOver, and matters more: several of these are icon-only buttons
//  that would otherwise announce nothing.
//

import SwiftUI

enum AccessibilityID {
    static let settingsButton = "home.settings"
    static let shazamButton = "home.shazam"
    static let aiMixCard = "home.aiMix"

    static let searchField = "search.query"

    static let librarySegment = "library.segment"
    static let importButton = "library.import"

    static let miniPlayer = "player.mini"
    static let playPauseButton = "player.playPause"
    /// The circular progress ring around the record — the seek control.
    static let playerRing = "player.ring"
    /// The record itself: swipe left/right to change track, down to dismiss.
    /// ("player.artwork" is taken — it is the matched-geometry id in
    /// `PlayerTransition`, which is a different namespace, but two meanings
    /// for one string is how tests end up matching the wrong thing.)
    static let playerDisc = "player.disc"

    static let eqEnable = "eq.enable"

    static let paywallClose = "paywall.close"

    static let statsCard = "home.stats"
    static let statsMenu = "stats.menu"
    static let statsTotal = "stats.total"
}

extension View {
    /// Sets the automation identifier and the spoken label together, so adding
    /// one never quietly leaves out the other.
    func identified(_ id: String, label: LocalizedStringKey) -> some View {
        accessibilityIdentifier(id)
            .accessibilityLabel(Text(label))
    }
}
