//
//  AppIconOption.swift
//  Sonava
//
//  Alternate home-screen icons, one per accent palette. Personalisation is the
//  cheapest kind of attachment: an icon the listener picked is an icon they
//  notice, and it pairs with the in-app theme so the two never disagree.
//
//  The default icon is free; the rest need Sonava Pro.
//

import UIKit

struct AppIconOption: Identifiable, Equatable, Sendable {
    /// Matches the palette id, so picking a theme can suggest the same icon.
    let id: String
    let name: String
    /// The asset-catalog name, or nil for the primary icon. UIKit wants nil —
    /// not the primary name — when switching back.
    let alternateName: String?
    /// Preview colours, mirroring the icon art: the glow behind the mark and
    /// the near-black it dissolves into.
    let gradientHex: [UInt]
    /// The mark's own colour in this icon — the settings miniature draws its
    /// bars with it, so the preview shows the icon that will actually land.
    let markHex: UInt
    let isPro: Bool

    var isDefault: Bool { alternateName == nil }
}

extension AppIconOption {
    // The art is the owner-chosen "glow" language: the five-bar mark over a
    // warm radial glow dissolving into near-black — the player's lit room in
    // 1024 pixels. One variant per palette; ids stay stable.
    static let aurora = AppIconOption(
        id: "aurora", name: "Ivory", alternateName: nil,
        gradientHex: [0x3A3226, 0x08080C], markHex: 0xEDE4D3, isPro: false)

    static let sunset = AppIconOption(
        id: "sunset", name: "Sunset", alternateName: "AppIcon-Sunset",
        gradientHex: [0x42160E, 0x08080C], markHex: 0xFF7A5A, isPro: true)

    static let ocean = AppIconOption(
        id: "ocean", name: "Ocean", alternateName: "AppIcon-Ocean",
        gradientHex: [0x0C2A34, 0x08080C], markHex: 0x2BD3E8, isPro: true)

    static let forest = AppIconOption(
        id: "forest", name: "Forest", alternateName: "AppIcon-Forest",
        gradientHex: [0x0E2C1C, 0x08080C], markHex: 0x3DD68C, isPro: true)

    static let rose = AppIconOption(
        id: "rose", name: "Rose", alternateName: "AppIcon-Rose",
        gradientHex: [0x38121E, 0x08080C], markHex: 0xFF5C8A, isPro: true)

    static let mono = AppIconOption(
        id: "mono", name: "Mono", alternateName: "AppIcon-Mono",
        gradientHex: [0x242430, 0x08080C], markHex: 0xC7C7D2, isPro: true)

    static let all: [AppIconOption] = [aurora, sunset, ocean, forest, rose, mono]

    static func option(alternateName: String?) -> AppIconOption {
        all.first { $0.alternateName == alternateName } ?? .aurora
    }
}

/// Owns the current icon. UIKit is the source of truth — `alternateIconName`
/// survives reinstalls of the app's own state — so nothing is duplicated into
/// UserDefaults where the two could drift.
@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var current: AppIconOption
    /// Set when the system refuses a change, so the UI can say why.
    @Published var lastError: String?

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    private init() {
        current = AppIconOption.option(alternateName: UIApplication.shared.alternateIconName)
    }

    /// Applies an icon.
    ///
    /// Uses the completion-handler API rather than its `async` counterpart on
    /// purpose: awaiting the bridged version never resumes when switching back
    /// to the primary icon, which would leave the picker frozen on whatever was
    /// selected before.
    func select(_ option: AppIconOption) {
        guard option != current else { return }
        guard supportsAlternateIcons else {
            lastError = String(localized: "This device doesn't support alternate icons.")
            return
        }
        // Optimistic: the picker follows the tap immediately and is corrected
        // below if the system refuses.
        current = option
        lastError = nil

        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            guard error != nil else { return }
            // The handler is invoked on an arbitrary thread.
            Task { @MainActor in
                // Most often: the asset wasn't bundled. Surfacing it beats a
                // silently unchanged home screen.
                self.lastError = String(localized: "Couldn't change the app icon.")
                self.current = AppIconOption.option(
                    alternateName: UIApplication.shared.alternateIconName
                )
            }
        }
    }

    /// Returns to the free icon when Pro lapses, mirroring the theme palette.
    func enforceFreeIfNeeded(isPro: Bool) {
        guard !isPro, current.isPro else { return }
        select(.aurora)
    }
}
