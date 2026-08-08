//
//  MondayMixTests.swift
//  SonavaTests
//
//  The calendar behind the weekly ritual. The mix's value is that it does
//  NOT change until Monday — so the tests are all about when the stamp
//  rolls and when the pin refuses to serve.
//

import Foundation
import Testing
@testable import Sonava

struct MondayMixTests {

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }

    private let utc = TimeZone(identifier: "UTC")!

    @Test func stampIsStableWithinAWeek() {
        // Monday and Sunday of the same ISO week. Pinned to UTC: the first
        // version of this test used `.current` and passed or failed depending
        // on which side of midnight the test machine's timezone put Sunday
        // evening — which is exactly why the API takes a zone.
        let monday = date("2026-08-03T09:00:00Z")
        let sunday = date("2026-08-09T21:00:00Z")
        #expect(MondayMix.weekStamp(for: monday, in: utc) == MondayMix.weekStamp(for: sunday, in: utc))
    }

    @Test func stampRollsOnMonday() {
        let sunday = date("2026-08-09T12:00:00Z")
        let nextMonday = date("2026-08-10T12:00:00Z")
        #expect(MondayMix.weekStamp(for: sunday, in: utc) != MondayMix.weekStamp(for: nextMonday, in: utc))
    }

    @Test func stampRollsAtTheListenersMidnightNotUTCs() {
        // 21:00 Sunday UTC is already Monday in Moscow: the Moscow listener's
        // mix must refresh while the UTC stamp still says last week.
        let sundayEveningUTC = date("2026-08-09T21:00:00Z")
        let moscow = TimeZone(identifier: "Europe/Moscow")!
        #expect(MondayMix.weekStamp(for: sundayEveningUTC, in: moscow)
             != MondayMix.weekStamp(for: sundayEveningUTC, in: utc))
    }

    @Test func stampCrossesYearBoundarySanely() {
        // ISO week years disagree with calendar years around January 1st;
        // the stamp must follow ISO or the mix would regenerate twice.
        let stamp = MondayMix.weekStamp(for: date("2026-01-01T12:00:00Z"), in: utc)
        #expect(stamp == "2026-W01", "Jan 1 2026 is a Thursday in ISO week 1, got \(stamp)")
    }

    @Test func storePinsAndServesWithinTheWeek() {
        let store = MondayMix.Store(filename: "monday-mix-test-\(UUID().uuidString).json")
        let songs = [Song(id: "t:1", title: "One", artist: "A", album: "B", gradientHex: [0x000000, 0xFFFFFF])]
        store.pin(songs, week: "2026-W32", seed: ["a"])
        #expect(store.songs(week: "2026-W32", seed: ["a"])?.first?.id == "t:1")
    }

    @Test func storeRefusesAStaleWeek() {
        let store = MondayMix.Store(filename: "monday-mix-test-\(UUID().uuidString).json")
        let songs = [Song(id: "t:1", title: "One", artist: "A", album: "B", gradientHex: [0x000000, 0xFFFFFF])]
        store.pin(songs, week: "2026-W32", seed: ["a"])
        #expect(store.songs(week: "2026-W33", seed: ["a"]) == nil, "last week's mix must not serve this week")
    }

    @Test func storeRefusesAChangedTaste() {
        let store = MondayMix.Store(filename: "monday-mix-test-\(UUID().uuidString).json")
        let songs = [Song(id: "t:1", title: "One", artist: "A", album: "B", gradientHex: [0x000000, 0xFFFFFF])]
        store.pin(songs, week: "2026-W32", seed: ["a"])
        #expect(store.songs(week: "2026-W32", seed: ["a", "b"]) == nil,
                "the shelf claims to be made for you, and you changed")
    }

    @Test func reminderFiresMondayMorning() {
        let components = MondayMix.reminderDateComponents()
        #expect(components.weekday == 2 && components.hour == 9)
    }
}
