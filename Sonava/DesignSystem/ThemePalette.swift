//
//  ThemePalette.swift
//  Sonava
//
//  Selectable accent palettes — a Sonava Pro personalisation. Only the brand
//  accent family changes; the dark ground, surfaces, text and semantic colours
//  stay constant so contrast and legibility never regress. `Theme` reads the
//  current palette, so every existing `Theme.accent` call site recolours for
//  free.
//

import SwiftUI

struct ThemePalette: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let accent: UInt
    let accentSoft: UInt
    let accentDeep: UInt
    let accentPink: UInt
    /// Whether this palette needs Sonava Pro. The default is always free.
    let isPro: Bool

    var accentColor: Color { Color(hex: accent) }
    var swatch: [Color] { [Color(hex: accent), Color(hex: accentPink), Color(hex: accentDeep)] }
}

extension ThemePalette {
    //                                       accent    soft      deep      pink
    static let aurora = ThemePalette(id: "aurora", name: "Aurora",
        accent: 0x7C5CFF, accentSoft: 0xB9A8FF, accentDeep: 0x4A00E0, accentPink: 0xFF6FD8, isPro: false)

    static let sunset = ThemePalette(id: "sunset", name: "Sunset",
        accent: 0xFF7A5A, accentSoft: 0xFFC4A3, accentDeep: 0xB4256B, accentPink: 0xFFB03A, isPro: true)

    static let ocean = ThemePalette(id: "ocean", name: "Ocean",
        accent: 0x2BD3E8, accentSoft: 0xA8ECF5, accentDeep: 0x0E5BE0, accentPink: 0x38EF9D, isPro: true)

    static let forest = ThemePalette(id: "forest", name: "Forest",
        accent: 0x3DD68C, accentSoft: 0xAEEFCB, accentDeep: 0x0E7A55, accentPink: 0xC6E85A, isPro: true)

    static let rose = ThemePalette(id: "rose", name: "Rose",
        accent: 0xFF5C8A, accentSoft: 0xFFB3C9, accentDeep: 0xB01E5A, accentPink: 0xFF8FB4, isPro: true)

    static let mono = ThemePalette(id: "mono", name: "Mono",
        accent: 0xC7C7D2, accentSoft: 0xE6E6EE, accentDeep: 0x6E6E7A, accentPink: 0x9A9AA6, isPro: true)

    static let all: [ThemePalette] = [aurora, sunset, ocean, forest, rose, mono]

    static func palette(id: String?) -> ThemePalette {
        all.first { $0.id == id } ?? .aurora
    }
}

/// Single source of truth for the active palette. `Theme` reads `shared`; the
/// app observes it and re-renders on change.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var palette: ThemePalette

    private let key = "theme.palette.v1"

    private init() {
        palette = ThemePalette.palette(id: UserDefaults.standard.string(forKey: key))
    }

    func select(_ palette: ThemePalette) {
        self.palette = palette
        UserDefaults.standard.set(palette.id, forKey: key)
    }

    /// Falls back to the free default — used when Pro lapses so a paid palette
    /// doesn't silently persist.
    func enforceFreeIfNeeded(isPro: Bool) {
        if !isPro, palette.isPro { select(.aurora) }
    }
}
