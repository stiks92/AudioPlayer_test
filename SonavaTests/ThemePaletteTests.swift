//
//  ThemePaletteTests.swift
//  SonavaTests
//
//  The palette drives every accent in the app, and lapsing Pro must not leave
//  a paid palette applied, so the small amount of logic here is worth pinning.
//

import Testing
@testable import Sonava

struct ThemePaletteTests {

    @Test("The default palette is free; the rest are Pro")
    func defaultIsFree() {
        #expect(ThemePalette.aurora.isPro == false)
        for palette in ThemePalette.all where palette.id != "aurora" {
            #expect(palette.isPro, "\(palette.id) should be Pro")
        }
    }

    @Test("Palette ids are unique and lookup falls back to the default")
    func lookup() {
        let ids = ThemePalette.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ThemePalette.palette(id: "ocean").id == "ocean")
        #expect(ThemePalette.palette(id: nil).id == "aurora")
        #expect(ThemePalette.palette(id: "nope").id == "aurora")
    }

    @Test("Every palette defines a full accent family")
    func fullFamily() {
        for palette in ThemePalette.all {
            // Distinct stops make a real gradient, not a flat blob.
            let stops = Set([palette.accent, palette.accentSoft, palette.accentDeep, palette.accentWarm])
            #expect(stops.count >= 3, "\(palette.id) has too few distinct stops")
            #expect(palette.swatch.count == 3)
        }
    }

    @MainActor
    @Test("Selecting a palette persists it")
    func selectionPersists() {
        let manager = ThemeManager.shared
        let original = manager.palette
        manager.select(.forest)
        #expect(manager.palette.id == "forest")
        manager.select(original)   // restore so the test leaves no trace
    }

    @MainActor
    @Test("A paid palette is dropped to the default when Pro lapses")
    func enforcesFreeWhenProLapses() {
        let manager = ThemeManager.shared
        manager.select(.rose)
        manager.enforceFreeIfNeeded(isPro: false)
        #expect(manager.palette.id == "aurora")

        // Still Pro → keep the paid palette.
        manager.select(.ocean)
        manager.enforceFreeIfNeeded(isPro: true)
        #expect(manager.palette.id == "ocean")
        manager.select(.aurora)
    }
}
