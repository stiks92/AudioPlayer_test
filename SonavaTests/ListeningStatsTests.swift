//
//  ListeningStatsTests.swift
//  SonavaTests
//
//  Stats are shown to the user as facts about their own listening, and the
//  streak is a retention hook people will notice the moment it's wrong — so
//  the windowing, ranking, bucketing and streak maths are all pinned here.
//
//  Every test injects `now` and a fixed-timezone calendar: a suite that passes
//  in London and fails in Vladivostok is worse than no suite at all.
//

import Testing
import Foundation
@testable import Sonava

struct ListeningStatsTests {

    /// Fixed reference point: 2026-03-15 20:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_773_604_800)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// An event `daysAgo` days before `now`, at `hour` o'clock UTC.
    private func event(
        _ artist: String,
        title: String = "T",
        seconds: Double = 180,
        daysAgo: Int = 0,
        hour: Int = 12,
        source: TrackSource = .audius
    ) -> PlayEvent {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Self.now)!
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return PlayEvent(session: UUID(), songID: "\(artist)-\(title)-\(daysAgo)-\(hour)",
                         title: title, artist: artist, source: source,
                         date: date, seconds: seconds)
    }

    private func build(_ events: [PlayEvent], range: StatsRange = .week) -> ListeningStats {
        ListeningStats.build(events: events, range: range, now: Self.now, calendar: calendar)
    }

    // MARK: - Windowing

    @Test("An empty log produces empty stats")
    func emptyLog() {
        let stats = build([])
        #expect(stats.isEmpty)
        #expect(stats.totalSeconds == 0)
        #expect(stats.streak == 0)
        #expect(stats.peakHour == nil)
        #expect(stats.topArtists.isEmpty)
    }

    @Test("The week window keeps the last 7 days and drops the 8th")
    func weekWindow() {
        let stats = build([
            event("A", daysAgo: 0),
            event("A", daysAgo: 6),      // still inside a 7-day window
            event("A", daysAgo: 7)       // one day too old
        ])
        #expect(stats.plays == 2)
        #expect(stats.totalSeconds == 360)
    }

    @Test("A longer range keeps what the week dropped")
    func longerRangesWiden() {
        let events = [event("A", daysAgo: 0), event("A", daysAgo: 20), event("A", daysAgo: 200)]
        #expect(build(events, range: .week).plays == 1)
        #expect(build(events, range: .month).plays == 2)
        #expect(build(events, range: .all).plays == 3)
    }

    // MARK: - Ranking

    @Test("Artists rank by time listened, not by play count")
    func rankByTime() {
        let stats = build([
            event("Short", seconds: 60), event("Short", seconds: 60), event("Short", seconds: 60),
            event("Long", seconds: 600)
        ])
        #expect(stats.topArtists.first?.name == "Long")
        #expect(stats.topArtists.first?.plays == 1)
        #expect(stats.topArtists.last?.name == "Short")
        #expect(stats.topArtists.last?.plays == 3)
        #expect(stats.artistCount == 2)
    }

    @Test("Top tracks carry their artist and merge repeats of the same title")
    func trackRanking() {
        let stats = build([
            event("A", title: "Hit", seconds: 100),
            event("A", title: "Hit", seconds: 200),
            event("A", title: "Deep cut", seconds: 120)
        ])
        let top = stats.topTracks.first
        #expect(top?.name == "Hit")
        #expect(top?.detail == "A")
        #expect(top?.seconds == 300)
        #expect(top?.plays == 2)
    }

    @Test("Ties resolve by name so the order never wobbles")
    func stableOrdering() {
        let events = [event("Zoe", seconds: 100), event("Ada", seconds: 100)]
        #expect(build(events).topArtists.map(\.name) == ["Ada", "Zoe"])
        // Same input in the other order must give the same answer.
        #expect(build(events.reversed()).topArtists.map(\.name) == ["Ada", "Zoe"])
    }

    @Test("Only the top N entries come back")
    func limitsRankedLists() {
        let events = (1...9).map { event("Artist \($0)", seconds: Double($0) * 10) }
        let stats = ListeningStats.build(events: events, range: .week, now: Self.now,
                                         calendar: calendar, limit: 3)
        #expect(stats.topArtists.count == 3)
        #expect(stats.topArtists.map(\.name) == ["Artist 9", "Artist 8", "Artist 7"])
    }

    // MARK: - Exclusions

    @Test("Radio and podcasts count as time spent but not as musical taste")
    func radioAndPodcastsExcludedFromTaste() {
        let stats = build([
            event("Some Station", seconds: 3_600, source: .radio),
            event("Some Show", seconds: 1_800, source: .podcast),
            event("Real Artist", seconds: 300)
        ])
        // All of it is time the listener spent in the app…
        #expect(stats.totalSeconds == 5_700)
        #expect(stats.plays == 3)
        // …but a station name is not an artist.
        #expect(stats.topArtists.map(\.name) == ["Real Artist"])
        #expect(stats.artistCount == 1)
    }

    @Test("An unknown artist is skipped rather than charted as a blank row")
    func blankArtistSkipped() {
        let stats = build([event("", seconds: 300), event("Real", seconds: 100)])
        #expect(stats.topArtists.map(\.name) == ["Real"])
    }

    // MARK: - Chart buckets

    @Test("The week chart has one bucket per day, oldest first, gaps filled")
    func weekBuckets() {
        let stats = build([event("A", seconds: 120, daysAgo: 0), event("A", seconds: 60, daysAgo: 2)])
        #expect(stats.days.count == 7)
        #expect(stats.days.map(\.day) == stats.days.map(\.day).sorted())
        #expect(stats.days.last?.seconds == 120)          // today
        #expect(stats.days[stats.days.count - 3].seconds == 60)
        #expect(stats.days[stats.days.count - 2].seconds == 0)   // a quiet day still charts
    }

    @Test("Longer ranges chart 30 days so the bars stay readable")
    func monthBuckets() {
        #expect(build([], range: .month).days.count == 30)
        #expect(build([], range: .all).days.count == 30)
    }

    // MARK: - Streak

    @Test("Consecutive days build a streak and a gap ends it")
    func streakCounting() {
        let unbroken = build([event("A", daysAgo: 0), event("A", daysAgo: 1), event("A", daysAgo: 2)])
        #expect(unbroken.streak == 3)

        let broken = build([event("A", daysAgo: 0), event("A", daysAgo: 2), event("A", daysAgo: 3)])
        #expect(broken.streak == 1)
    }

    @Test("A streak survives a today with no listening yet")
    func streakSurvivesQuietToday() {
        #expect(build([event("A", daysAgo: 1), event("A", daysAgo: 2)]).streak == 2)
        // But not two quiet days.
        #expect(build([event("A", daysAgo: 2), event("A", daysAgo: 3)]).streak == 0)
    }

    @Test("Several listens on one day still count as one streak day")
    func streakCountsDaysNotPlays() {
        #expect(build([event("A", hour: 9), event("A", hour: 14), event("A", hour: 21)]).streak == 1)
    }

    @Test("The streak is all-time and doesn't shrink with the selected window")
    func streakIgnoresWindow() {
        // 10 consecutive days: longer than the 7-day window being displayed.
        let events = (0..<10).map { event("A", daysAgo: $0) }
        #expect(build(events, range: .week).streak == 10)
    }

    // MARK: - Peak hour

    @Test("Peak hour is the hour with the most time, not the most plays")
    func peakHour() {
        let stats = build([
            event("A", seconds: 60, hour: 9), event("A", title: "B", seconds: 60, hour: 9),
            event("A", title: "C", seconds: 900, hour: 23)
        ])
        #expect(stats.peakHour == 23)
    }

    // MARK: - Formatting

    @Test("Durations read naturally at every scale")
    func durationFormatting() {
        let en = Locale(identifier: "en_US")
        #expect(ListeningStats.duration(0, locale: en) == "0s")
        #expect(ListeningStats.duration(45, locale: en) == "45s")
        #expect(ListeningStats.duration(90, locale: en) == "2m")
        #expect(ListeningStats.duration(12_240, locale: en) == "3h 24m")
    }

    @Test("Duration units are translated, not hard-coded English")
    func durationIsLocalized() {
        // The units are text on screen: shipping "3h 24m" to a Russian reader
        // is exactly the class of bug the String Catalog migration was for.
        let russian = ListeningStats.duration(12_240, locale: Locale(identifier: "ru_RU"))
        #expect(russian.contains("ч"))
        #expect(russian.contains("м"))
        #expect(!russian.contains("h"))
    }

    // MARK: - Share card

    @MainActor
    @Test("The share card renders to an image at the size social apps expect")
    func shareCardRenders() {
        let stats = build([
            event("Bonobo", seconds: 900), event("Tycho", seconds: 600), event("Four Tet", seconds: 300)
        ])
        let shareable = StatsShareCardRenderer.render(stats, range: .week)
        #expect(shareable != nil)
        #expect(shareable?.image.size == CGSize(width: 1080, height: 1350))
    }

    // MARK: - Range metadata

    @Test("Only the week view is free")
    func weekIsFree() {
        #expect(StatsRange.week.isPro == false)
        #expect(StatsRange.month.isPro)
        #expect(StatsRange.all.isPro)
        #expect(StatsRange.all.days == nil)
    }
}
