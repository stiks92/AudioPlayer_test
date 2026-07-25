//
//  ListeningStats.swift
//  Sonava
//
//  The listener's own year-in-review, computed on device. Pure value types:
//  a log of what was played goes in, a summary comes out. No I/O, no clock of
//  its own — `now` and the calendar are injected so the maths is testable and
//  time-zone honest.
//

import Foundation
import SwiftUI

/// One continuous listen. `seconds` is time actually heard, with paused time
/// excluded, and `session` identifies the listen so a still-playing track can
/// be updated in place instead of logged twice.
struct PlayEvent: Codable, Equatable, Sendable {
    let session: UUID
    let songID: String
    let title: String
    let artist: String
    let source: TrackSource
    let date: Date
    var seconds: Double

    /// Radio has no per-track metadata and podcasts aren't music, so neither
    /// belongs in a "top artists" chart — but both still count as time spent.
    var countsTowardsTaste: Bool {
        source != .radio && source != .podcast && !artist.isEmpty
    }
}

/// The window a summary covers. Only the last week is free; the longer views
/// are a Sonava Pro perk.
enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case week, month, all

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        case .all:   return "All time"
        }
    }

    /// How many days back the window reaches, counting today. `nil` = no limit.
    var days: Int? {
        switch self {
        case .week:  return 7
        case .month: return 30
        case .all:   return nil
        }
    }

    var isPro: Bool { self != .week }

    /// Buckets drawn in the chart. The all-time view still shows the last 30
    /// days — a year of bars would be unreadable on a phone.
    var chartDays: Int { self == .week ? 7 : 30 }
}

struct ListeningStats: Equatable, Sendable {

    /// A ranked row — an artist, or a track with its artist as `detail`.
    struct Entry: Identifiable, Equatable, Sendable {
        let name: String
        let detail: String
        let plays: Int
        let seconds: Double
        var id: String { "\(name)\u{1}\(detail)" }
    }

    /// One day of the chart. Days with no listening are present with zero, so
    /// the chart keeps an even axis.
    struct DayBucket: Identifiable, Equatable, Sendable {
        let day: Date
        let seconds: Double
        var id: Date { day }
    }

    let totalSeconds: Double
    let plays: Int
    let artistCount: Int
    let topArtists: [Entry]
    let topTracks: [Entry]
    let days: [DayBucket]
    /// Consecutive days listened, up to and including today (or ending
    /// yesterday, so a streak doesn't look broken before you've played anything).
    let streak: Int
    /// Hour of day (0–23) with the most listening, if there is any.
    let peakHour: Int?

    var isEmpty: Bool { plays == 0 }

    static let empty = ListeningStats(
        totalSeconds: 0, plays: 0, artistCount: 0,
        topArtists: [], topTracks: [], days: [], streak: 0, peakHour: nil
    )

    // MARK: - Building

    static func build(
        events: [PlayEvent],
        range: StatsRange,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 5
    ) -> ListeningStats {
        let today = calendar.startOfDay(for: now)
        let windowed = inWindow(events, range: range, today: today, calendar: calendar)

        let totalSeconds = windowed.reduce(0) { $0 + $1.seconds }
        let taste = windowed.filter(\.countsTowardsTaste)

        return ListeningStats(
            totalSeconds: totalSeconds,
            plays: windowed.count,
            artistCount: Set(taste.map(\.artist)).count,
            topArtists: rank(taste, by: \.artist, detail: { _ in "" }, limit: limit),
            topTracks: rank(taste, by: \.title, detail: { $0.artist }, limit: limit),
            days: buckets(windowed, count: range.chartDays, today: today, calendar: calendar),
            // A streak is inherently all-time: it must not shrink just because
            // the user is looking at the week view.
            streak: streak(events, today: today, calendar: calendar),
            peakHour: peakHour(windowed, calendar: calendar)
        )
    }

    private static func inWindow(
        _ events: [PlayEvent],
        range: StatsRange,
        today: Date,
        calendar: Calendar
    ) -> [PlayEvent] {
        guard let days = range.days,
              let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        else { return events }
        return events.filter { $0.date >= cutoff }
    }

    /// Groups by a key, summing time and plays, then takes the biggest by time.
    private static func rank(
        _ events: [PlayEvent],
        by key: (PlayEvent) -> String,
        detail: (PlayEvent) -> String,
        limit: Int
    ) -> [Entry] {
        var totals: [String: (detail: String, plays: Int, seconds: Double)] = [:]
        for event in events {
            let name = key(event)
            guard !name.isEmpty else { continue }
            var bucket = totals[name] ?? (detail(event), 0, 0)
            bucket.plays += 1
            bucket.seconds += event.seconds
            totals[name] = bucket
        }
        return totals
            .map { Entry(name: $0.key, detail: $0.value.detail, plays: $0.value.plays, seconds: $0.value.seconds) }
            // Sort by time, then plays, then name so the order is deterministic
            // even when two artists tie — a wobbling chart looks broken.
            .sorted {
                if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
                if $0.plays != $1.plays { return $0.plays > $1.plays }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func buckets(
        _ events: [PlayEvent],
        count: Int,
        today: Date,
        calendar: Calendar
    ) -> [DayBucket] {
        var totals: [Date: Double] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            totals[day, default: 0] += event.seconds
        }
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayBucket(day: day, seconds: totals[day] ?? 0)
        }
    }

    private static func streak(_ events: [PlayEvent], today: Date, calendar: Calendar) -> Int {
        let listened = Set(events.map { calendar.startOfDay(for: $0.date) })
        guard !listened.isEmpty else { return 0 }

        // Today may simply not have started yet, so a streak that ran through
        // yesterday still counts. Anything older is broken.
        var cursor = today
        if !listened.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  listened.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while listened.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func peakHour(_ events: [PlayEvent], calendar: Calendar) -> Int? {
        guard !events.isEmpty else { return nil }
        var totals: [Int: Double] = [:]
        for event in events {
            totals[calendar.component(.hour, from: event.date), default: 0] += event.seconds
        }
        // Ties resolve to the earlier hour so the answer is stable.
        return totals.max { ($0.value, -Double($0.key)) < ($1.value, -Double($1.key)) }?.key
    }
}

// MARK: - Formatting

extension ListeningStats {
    /// "3h 24m" / "24m" / "45s", in the reader's language — the units are part
    /// of the sentence, so hard-coding "h" and "m" would ship an English number
    /// onto a Russian screen.
    ///
    /// `locale` is injectable so tests assert one language instead of whichever
    /// the simulator happens to be running.
    static func duration(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let rounded = max(0, seconds.rounded())
        // Only show the units that carry information: an hours field on a
        // 45-second total reads as noise.
        let allowed: Set<Duration.UnitsFormatStyle.Unit> =
            rounded >= 3_600 ? [.hours, .minutes] : (rounded >= 60 ? [.minutes] : [.seconds])
        return Duration.seconds(rounded)
            .formatted(.units(allowed: allowed, width: .narrow).locale(locale))
    }
}
