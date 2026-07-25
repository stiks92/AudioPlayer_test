//
//  ListeningHistory.swift
//  Sonava
//
//  The play log behind the stats screen. It stays on device — no account, no
//  upload — which is the whole point of the privacy positioning.
//
//  `AudioManager` reports the running total for the track it is playing, over
//  and over, always tagged with the same session id. Recording therefore
//  *updates* the last entry rather than appending, so a 40-minute listen is one
//  event of 40 minutes and not 160 events of 15 seconds.
//

import SwiftUI
import Combine

@MainActor
final class ListeningHistory: ObservableObject {

    @Published private(set) var events: [PlayEvent] = []

    private let store: JSONFileStore<[PlayEvent]>

    /// Anything shorter than this is a skip, not a listen.
    static let minimumListen: Double = 20
    private static let maxEvents = 4_000
    private static let retentionDays = 400

    init(store: JSONFileStore<[PlayEvent]> = JSONFileStore("listening.json", default: [])) {
        self.store = store
        events = store.read()
        prune(now: Date())
    }

    // MARK: - Recording

    /// Records the running total for one continuous listen.
    ///
    /// - Parameters:
    ///   - seconds: total time heard so far in this session, not a delta.
    ///   - session: identifies the listen; repeat calls with the same id
    ///     overwrite rather than accumulate, so this is safe to call on a timer.
    func record(song: Song, seconds: Double, session: UUID, now: Date = Date()) {
        guard seconds >= Self.minimumListen else { return }

        if let index = events.lastIndex(where: { $0.session == session }) {
            events[index].seconds = seconds
        } else {
            events.append(
                PlayEvent(
                    session: session,
                    songID: song.id,
                    title: song.title,
                    artist: song.artist,
                    source: song.source,
                    date: now,
                    seconds: seconds
                )
            )
            prune(now: now)
        }
        store.write(events)
    }

    // MARK: - Reading

    func stats(range: StatsRange, now: Date = Date(), calendar: Calendar = .current) -> ListeningStats {
        ListeningStats.build(events: events, range: range, now: now, calendar: calendar)
    }

    /// Whether there is enough history to be worth showing at all.
    var hasHistory: Bool { !events.isEmpty }

    func clear() {
        events = []
        store.write(events)
    }

    // MARK: - Housekeeping

    #if DEBUG
    /// Fills the log with a plausible fortnight so the stats screen can be
    /// driven for UI tests and App Store screenshots. Debug builds only, and
    /// only ever reached from a launch argument.
    func seedDemoData(now: Date = Date()) {
        let catalogue: [(String, String)] = [
            ("Nils Frahm", "Says"), ("Bonobo", "Kerala"), ("Tycho", "Awake"),
            ("Ólafur Arnalds", "Near Light"), ("Jon Hopkins", "Emerald Rush"),
            ("Bonobo", "Cirrus"), ("Nils Frahm", "Hammers"), ("Four Tet", "Two Thousand")
        ]
        var seeded: [PlayEvent] = []
        for day in 0..<14 {
            // A varying but deterministic handful of plays per day.
            for slot in 0..<(3 + day % 3) {
                let (artist, title) = catalogue[(day * 3 + slot) % catalogue.count]
                guard let date = Calendar.current.date(byAdding: .day, value: -day, to: now),
                      let stamped = Calendar.current.date(bySettingHour: 9 + (slot * 4) % 13,
                                                          minute: 0, second: 0, of: date)
                else { continue }
                seeded.append(
                    PlayEvent(session: UUID(), songID: "demo:\(day):\(slot)",
                              title: title, artist: artist, source: .audius,
                              date: stamped, seconds: Double(180 + (day * 37 + slot * 53) % 240))
                )
            }
        }
        events = seeded.sorted { $0.date < $1.date }
        store.write(events)
    }
    #endif

    /// Keeps the log bounded in both age and size — an unbounded JSON file that
    /// is rewritten on every track would eventually cost real launch time.
    private func prune(now: Date) {
        let before = events.count
        if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now) {
            events.removeAll { $0.date < cutoff }
        }
        if events.count > Self.maxEvents {
            events = Array(events.suffix(Self.maxEvents))
        }
        if events.count != before { store.write(events) }
    }
}
