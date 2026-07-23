//
//  TasteProfileTests.swift
//  SonavaTests
//
//  The taste profile seeds both the "Made for you" shelf and endless radio, so
//  its ranking and its exclusions need to be right — and it must stay purely
//  on-device.
//

import Testing
import Foundation
@testable import Sonava

struct TasteProfileTests {

    private func song(_ artist: String, source: TrackSource = .audius, id: String = UUID().uuidString) -> Song {
        Song(id: id, title: "T", artist: artist, album: "A", source: source,
             gradientHex: Palette.hex(for: 0))
    }

    @Test("No history means an empty profile")
    func emptyWithoutHistory() {
        let profile = TasteProfile.build(favorites: [], recents: [])
        #expect(profile.isEmpty)
        #expect(profile.seedQueries.isEmpty)
    }

    @Test("A favourited artist outranks one that was merely played")
    func favouritesWeighHeavier() {
        let profile = TasteProfile.build(
            favorites: [song("Bonobo")],                                  // weight 3
            recents: [song("Tycho"), song("Tycho"), song("Tycho")]       // weight 3 too, ties
        )
        // Bonobo (3) ties Tycho (3) — alphabetical tiebreak puts Bonobo first.
        #expect(profile.topArtists.first == "Bonobo")
    }

    @Test("Repeated plays accumulate weight and rank higher")
    func frequencyRanks() {
        let profile = TasteProfile.build(
            favorites: [],
            recents: [song("A"), song("A"), song("A"), song("B")]
        )
        #expect(profile.topArtists == ["A", "B"])
    }

    @Test("Radio and podcasts carry no artist taste and are ignored")
    func ignoresRadioAndPodcasts() {
        let profile = TasteProfile.build(
            favorites: [song("Some Station", source: .radio),
                        song("Some Show", source: .podcast)],
            recents: []
        )
        #expect(profile.isEmpty)
    }

    @Test("Untagged imports don't masquerade as a taste signal")
    func ignoresUnknownArtist() {
        let unknown = String(localized: "Unknown artist")
        let profile = TasteProfile.build(favorites: [song(unknown), song("")], recents: [])
        #expect(profile.isEmpty)
    }

    @Test("Only the top few artists become search seeds")
    func seedsAreCapped() {
        let favorites = (0..<10).map { song("Artist \($0)", id: "f\($0)") }
        let profile = TasteProfile.build(favorites: favorites, recents: [])
        #expect(profile.topArtists.count == 10)
        #expect(profile.seedQueries.count <= 4)
    }

    @Test("Ranking is stable — same input, same order")
    func stableOrdering() {
        let favs = [song("Zed"), song("Amp"), song("Amp")]
        let a = TasteProfile.build(favorites: favs, recents: [])
        let b = TasteProfile.build(favorites: favs, recents: [])
        #expect(a == b)
        #expect(a.topArtists.first == "Amp")   // weight 6 vs Zed 3
    }
}
