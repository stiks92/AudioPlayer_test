//
//  ShuffleTests.swift
//  SonavaTests
//
//  Shuffle is the feature people complain about most and measure least. The
//  contract worth pinning is not "is it random" — `shuffled()` already is —
//  but "does it stop replaying what I just heard", which is what listeners
//  actually mean when they say a shuffle is broken.
//

import Testing
import Foundation
@testable import Sonava

struct ShuffleTests {

    /// A generator with a fixed sequence, so an ordering assertion is about
    /// the algorithm rather than about luck.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func songs(_ count: Int) -> [Song] {
        (0..<count).map {
            Song(id: "t\($0)", title: "Track \($0)", artist: "Artist", album: "Album",
                 source: .audius, gradientHex: Palette.hex(for: $0))
        }
    }

    @Test("Nothing is lost or duplicated")
    func isAPermutation() {
        let all = songs(40)
        let out = Shuffle.ordered(all, recent: Array(all.prefix(10)))
        #expect(out.count == all.count)
        #expect(Set(out.map(\.id)) == Set(all.map(\.id)))
    }

    @Test("Recently heard tracks sink to the back")
    func recentsAreDemoted() {
        let all = songs(40)
        let recent = Array(all.prefix(10))          // t0…t9 were just played
        let out = Shuffle.ordered(all, recent: recent)

        let recentIDs = Set(recent.map(\.id))
        let firstThirty = out.prefix(30).map(\.id)
        #expect(firstThirty.allSatisfy { !recentIDs.contains($0) },
                "a track heard minutes ago must not open the shuffle")
        #expect(out.suffix(10).allSatisfy { recentIDs.contains($0.id) })
    }

    @Test("With no history it is plain random — every track eligible")
    func noHistoryIsPlainShuffle() {
        let all = songs(12)
        let out = Shuffle.ordered(all, recent: [])
        #expect(Set(out.map(\.id)) == Set(all.map(\.id)))
    }

    @Test("Only the last 25 count as recent, so a long history can't freeze the order")
    func memoryIsBounded() {
        let all = songs(60)
        // Everything has been heard, but only the newest 25 are "recent".
        let out = Shuffle.ordered(all, recent: all)
        let demoted = Set(all.prefix(Shuffle.memory).map(\.id))
        #expect(out.prefix(35).allSatisfy { !demoted.contains($0.id) })
    }

    @Test("When everything is recent it still reshuffles rather than repeating an order")
    func fullyHeardLibraryStillVaries() {
        let all = songs(30)
        var a = SeededGenerator(state: 1)
        var b = SeededGenerator(state: 99)
        let first = Shuffle.ordered(all, recent: all, using: &a).map(\.id)
        let second = Shuffle.ordered(all, recent: all, using: &b).map(\.id)
        #expect(first != second,
                "a listener who has heard everything must not get one fixed order forever")
    }

    @Test("The same generator state reproduces the same order")
    func isDeterministicForAGivenSeed() {
        let all = songs(20)
        var a = SeededGenerator(state: 42)
        var b = SeededGenerator(state: 42)
        #expect(Shuffle.ordered(all, recent: [], using: &a).map(\.id)
                == Shuffle.ordered(all, recent: [], using: &b).map(\.id))
    }
}
