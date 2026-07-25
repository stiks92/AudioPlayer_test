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
    /// Preview colours, mirroring the icon's gradient.
    let gradientHex: [UInt]
    let isPro: Bool

    var isDefault: Bool { alternateName == nil }
}

extension AppIconOption {
    static let aurora = AppIconOption(
        id: "aurora", name: "Aurora", alternateName: nil,
        gradientHex: [0x4A00E0, 0x7C5CFF, 0xFF6FD8], isPro: false)

    static let sunset = AppIconOption(
        id: "sunset", name: "Sunset", alternateName: "AppIcon-Sunset",
        gradientHex: [0xB4256B, 0xFF7A5A, 0xFFB03A], isPro: true)

    static let ocean = AppIconOption(
        id: "ocean", name: "Ocean", alternateName: "AppIcon-Ocean",
        gradientHex: [0x0E5BE0, 0x2BD3E8, 0x38EF9D], isPro: true)

    static let forest = AppIconOption(
        id: "forest", name: "Forest", alternateName: "AppIcon-Forest",
        gradientHex: [0x0E7A55, 0x3DD68C, 0xC6E85A], isPro: true)

    static let rose = AppIconOption(
        id: "rose", name: "Rose", alternateName: "AppIcon-Rose",
        gradientHex: [0xB01E5A, 0xFF5C8A, 0xFF8FB4], isPro: true)

    static let mono = AppIconOption(
        id: "mono", name: "Mono", alternateName: "AppIcon-Mono",
        gradientHex: [0x2A2A32, 0x6E6E7A, 0xC7C7D2], isPro: true)

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
