//
//  MondayMix.swift
//  Sonava
//
//  The weekly ritual around the taste shelf.
//
//  "Made for you" used to regenerate whenever the app felt like it — every
//  cold launch refetched, so the shelf was different at breakfast and at
//  lunch. A shelf that never settles can't be looked forward to. The growth
//  scan's retention read is the Discover Weekly pattern: pin the mix for the
//  week, give the ritual a name, and mark the refresh with one notification
//  on Monday morning — the single cheapest D7-return anchor a solo developer
//  can build, because the feature it announces already exists.
//
//  The mix itself still comes from the on-device taste profile; this file
//  only owns the calendar: what week it is, whether the stored mix is still
//  this week's, and the one repeating notification.
//

import Foundation
import UserNotifications

enum MondayMix {

    // MARK: - The week

    /// ISO-8601 year and week ("2026-W33"): stable for seven days, rolls on
    /// Monday — which is the entire behaviour of the feature, in one string.
    /// The zone is the listener's: their mix turns over on *their* Monday
    /// morning, not UTC's. Injectable because a test on a Moscow machine and
    /// the same test on CI must disagree about nothing.
    static func weekStamp(for date: Date = .now, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    // MARK: - The pinned mix

    struct Snapshot: Codable, Sendable {
        var week: String
        /// The taste seed the mix was built from. A new favourite artist is
        /// allowed to break the week's pin: the shelf claims to be made for
        /// you, and "you" changed.
        var seed: [String]
        var songs: [Song]
    }

    struct Store {
        private let file: JSONFileStore<Snapshot?>

        /// Injectable filename so parallel tests don't share a mix.
        init(filename: String = "monday-mix.json") {
            file = JSONFileStore(filename, default: nil)
        }

        /// This week's pinned songs, if the pin is still valid for this week
        /// and this taste.
        func songs(week: String, seed: [String]) -> [Song]? {
            guard let snapshot = file.read(),
                  snapshot.week == week,
                  snapshot.seed == seed,
                  !snapshot.songs.isEmpty else { return nil }
            return snapshot.songs
        }

        func pin(_ songs: [Song], week: String, seed: [String]) {
            file.write(Snapshot(week: week, seed: seed, songs: songs))
        }
    }

    // MARK: - The reminder

    static let reminderIdentifier = "monday.mix.reminder"
    static let reminderDefaultsKey = "mondaymix.reminder.v1"

    /// Monday, 09:00 local — after the alarm, before the commute.
    static func reminderDateComponents() -> DateComponents {
        var components = DateComponents()
        components.weekday = 2
        components.hour = 9
        return components
    }

    /// Turns the weekly notification on or off. Returns whether it is on —
    /// false when the user declined the permission prompt, so the toggle can
    /// fall back honestly instead of showing an "on" that will never fire.
    @discardableResult
    static func setReminder(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
            UserDefaults.standard.set(false, forKey: reminderDefaultsKey)
            return false
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: reminderDefaultsKey)
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your Monday Mix is ready")
        content.body = String(localized: "A fresh week of music, picked from what you love.")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderDateComponents(), repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
        UserDefaults.standard.set(true, forKey: reminderDefaultsKey)
        return true
    }
}
