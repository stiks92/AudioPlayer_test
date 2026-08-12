//
//  ListeningJourney.swift
//  Sonava
//
//  Stage 2 of the Backroom: the listening biography — imported history from
//  the services a person is leaving, stitched to the library they own.
//
//  The assassin's two conditions shaped everything here. First: day-zero
//  import must be instant, so the primary path is the ListenBrainz public
//  API (a username, no OAuth, no key — probed live before this file was
//  written) and the Spotify GDPR archive is the *second* step, arriving up
//  to 30 days later. Second: no servers of ours — everything parses and
//  aggregates on device.
//
//  Storage is aggregated, not raw: two hundred thousand listen events is a
//  fun number to brag about and a terrible thing to keep in JSON. What the
//  product actually reads is per-track: first heard, last heard, play
//  count, listening time, and a per-year histogram. That is a ~1 MB ledger
//  for a serious library, and it answers every question Liner Notes asks.
//

import Foundation

/// One track's aggregated life with the listener.
struct JourneyTrack: Codable, Equatable, Sendable {
    var artist: String
    var title: String
    /// Unix seconds of the earliest and latest known listens.
    var firstListen: TimeInterval
    var lastListen: TimeInterval
    var plays: Int
    var milliseconds: Int
    /// Year ("2014") → plays that year. String keys keep Codable plain.
    var yearCounts: [String: Int]
}

/// The whole imported biography, keyed by a normalised artist|title pair —
/// the same normaliser the playlist importer trusts, so a 2011 rip and a
/// 2024 remaster edition of the same song land on the same entry.
struct Journey: Codable, Equatable, Sendable {
    var tracks: [String: JourneyTrack] = [:]
    var importedSources: [String] = []

    var totalPlays: Int { tracks.values.reduce(0) { $0 + $1.plays } }
    var earliest: TimeInterval? { tracks.values.map(\.firstListen).min() }

    static func key(artist: String, title: String) -> String {
        PlaylistImport.normalise(artist) + "|" + PlaylistImport.normalise(title)
    }
}

/// One listen event on its way into the aggregate.
struct ListenEvent: Equatable, Sendable {
    var timestamp: TimeInterval
    var artist: String
    var title: String
    var milliseconds: Int?
}

enum ListeningJourney {

    /// Spotify counts a play at 30 s; shorter is a skip, and importing skips
    /// would inflate every number the biography shows.
    static let minimumMilliseconds = 30_000

    // MARK: - Aggregation

    static func merge(_ events: [ListenEvent], into journey: inout Journey, source: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        for event in events {
            if let ms = event.milliseconds, ms < minimumMilliseconds { continue }
            guard !event.artist.isEmpty, !event.title.isEmpty, event.timestamp > 0 else { continue }
            let key = Journey.key(artist: event.artist, title: event.title)
            guard !key.hasPrefix("|"), !key.hasSuffix("|") else { continue }

            let year = String(calendar.component(.year,
                from: Date(timeIntervalSince1970: event.timestamp)))
            if var track = journey.tracks[key] {
                track.firstListen = min(track.firstListen, event.timestamp)
                track.lastListen = max(track.lastListen, event.timestamp)
                track.plays += 1
                track.milliseconds += event.milliseconds ?? 0
                track.yearCounts[year, default: 0] += 1
                journey.tracks[key] = track
            } else {
                journey.tracks[key] = JourneyTrack(
                    artist: event.artist, title: event.title,
                    firstListen: event.timestamp, lastListen: event.timestamp,
                    plays: 1, milliseconds: event.milliseconds ?? 0,
                    yearCounts: [year: 1])
            }
        }
        if !journey.importedSources.contains(source) {
            journey.importedSources.append(source)
        }
    }

    // MARK: - Spotify GDPR export

    /// Both generations of the export: the extended history
    /// (`Streaming_History_Audio_*.json` / `endsong_*.json`, snake_case,
    /// ISO timestamps) and the year-window one (`StreamingHistory*.json`,
    /// camelCase, minute timestamps). People arrive with whichever Spotify
    /// gave them.
    static func parseSpotifyExport(_ data: Data) -> [ListenEvent] {
        struct Extended: Decodable {
            let ts: String
            let ms_played: Int?
            let master_metadata_track_name: String?
            let master_metadata_album_artist_name: String?
        }
        struct Legacy: Decodable {
            let endTime: String
            let artistName: String
            let trackName: String
            let msPlayed: Int?
        }

        let isoFull = ISO8601DateFormatter()
        if let rows = try? JSONDecoder().decode([Extended].self, from: data) {
            return rows.compactMap { row in
                guard let title = row.master_metadata_track_name,
                      let artist = row.master_metadata_album_artist_name,
                      let date = isoFull.date(from: row.ts) else { return nil }
                return ListenEvent(timestamp: date.timeIntervalSince1970,
                                   artist: artist, title: title,
                                   milliseconds: row.ms_played)
            }
        }

        let minute = DateFormatter()
        minute.dateFormat = "yyyy-MM-dd HH:mm"
        minute.timeZone = TimeZone(identifier: "UTC")
        minute.locale = Locale(identifier: "en_US_POSIX")
        if let rows = try? JSONDecoder().decode([Legacy].self, from: data) {
            return rows.compactMap { row in
                guard let date = minute.date(from: row.endTime) else { return nil }
                return ListenEvent(timestamp: date.timeIntervalSince1970,
                                   artist: row.artistName, title: row.trackName,
                                   milliseconds: row.msPlayed)
            }
        }
        return []
    }

    // MARK: - ListenBrainz

    /// One page of the public listens API — also the exact shape of the
    /// site's full-export file, so one decoder serves both paths.
    struct ListenBrainzPage: Decodable {
        struct Payload: Decodable {
            struct Listen: Decodable {
                struct Metadata: Decodable {
                    let artist_name: String?
                    let track_name: String?
                }
                let listened_at: TimeInterval?
                let track_metadata: Metadata?
            }
            let listens: [Listen]
        }
        let payload: Payload
    }

    static func events(fromListenBrainz listens: [ListenBrainzPage.Payload.Listen]) -> [ListenEvent] {
        listens.compactMap { listen in
            guard let at = listen.listened_at,
                  let artist = listen.track_metadata?.artist_name,
                  let title = listen.track_metadata?.track_name else { return nil }
            return ListenEvent(timestamp: at, artist: artist, title: title, milliseconds: nil)
        }
    }

    static func parseListenBrainzExport(_ data: Data) -> [ListenEvent] {
        if let page = try? JSONDecoder().decode(ListenBrainzPage.self, from: data) {
            return events(fromListenBrainz: page.payload.listens)
        }
        // The export file is sometimes a bare array of listens.
        if let listens = try? JSONDecoder().decode([ListenBrainzPage.Payload.Listen].self, from: data) {
            return events(fromListenBrainz: listens)
        }
        return []
    }

    /// Pages backwards through a user's public listens. No key, no OAuth —
    /// the day-zero funnel must not start with a 30-day wait. Capped: ten
    /// thousand most recent listens is a biography, not a hostage situation;
    /// the full archive arrives via the export file.
    static func fetchListenBrainz(username: String,
                                  cap: Int = 10_000,
                                  session: URLSession = .shared,
                                  progress: @escaping @Sendable (Int) -> Void) async throws -> [ListenEvent] {
        var collected: [ListenEvent] = []
        var maxTS: Int?
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username

        while collected.count < cap {
            var components = URLComponents(string: "https://api.listenbrainz.org/1/user/\(encoded)/listens")!
            var items = [URLQueryItem(name: "count", value: "100")]
            if let maxTS { items.append(URLQueryItem(name: "max_ts", value: String(maxTS))) }
            components.queryItems = items
            var request = URLRequest(url: components.url!)
            request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { break }
            if http.statusCode == 404 { throw JourneyImportError.userNotFound }
            guard 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }

            let page = try JSONDecoder().decode(ListenBrainzPage.self, from: data)
            let events = events(fromListenBrainz: page.payload.listens)
            guard !events.isEmpty else { break }
            collected.append(contentsOf: events)
            progress(collected.count)
            maxTS = Int(events.map(\.timestamp).min() ?? 0) - 1
            if page.payload.listens.count < 100 { break }
        }
        return collected
    }
}

enum JourneyImportError: Error {
    case userNotFound
}

/// The persisted biography, with the resilience every store here has.
@MainActor
final class JourneyStore: ObservableObject {

    @Published private(set) var journey: Journey {
        didSet { file.write(journey) }
    }

    private let file: JSONFileStore<Journey>

    init(filename: String = "journey.json") {
        file = JSONFileStore(filename, default: Journey())
        journey = file.read()
    }

    func add(events: [ListenEvent], source: String) {
        var updated = journey
        ListeningJourney.merge(events, into: &updated, source: source)
        journey = updated
    }

    func entry(for song: Song) -> JourneyTrack? {
        journey.tracks[Journey.key(artist: song.artist, title: song.title)]
    }

    func clear() {
        journey = Journey()
    }

    /// One year's story, computed for the Recap screen and its share card.
    struct Recap: Equatable {
        var year: String
        var plays: Int
        var topArtists: [(name: String, plays: Int)]
        var topTracks: [(artist: String, title: String, plays: Int)]
        /// Artists whose very first listen in the whole biography falls in
        /// this year — the year's discoveries, not merely its rotation.
        var discoveries: [String]
        /// The oldest companion still in this year's rotation: the artist
        /// with the earliest first listen who was also played this year.
        var oldestCompanion: (name: String, since: String)?
        var previousYearPlays: Int?

        static func == (a: Recap, b: Recap) -> Bool {
            a.year == b.year && a.plays == b.plays
        }
    }

    /// Builds the recap for a year, or nil if that year holds no listening.
    func recap(year: String) -> Recap? {
        var plays = 0
        var artistPlays: [String: Int] = [:]
        var trackRows: [(artist: String, title: String, plays: Int)] = []
        var artistFirstEver: [String: TimeInterval] = [:]
        var artistPlayedThisYear = Set<String>()
        var previous = 0
        let previousYear = (Int(year) ?? 0) - 1

        for track in journey.tracks.values {
            let inYear = track.yearCounts[year] ?? 0
            previous += track.yearCounts[String(previousYear)] ?? 0
            let known = artistFirstEver[track.artist]
            if known == nil || track.firstListen < known! {
                artistFirstEver[track.artist] = track.firstListen
            }
            guard inYear > 0 else { continue }
            plays += inYear
            artistPlays[track.artist, default: 0] += inYear
            artistPlayedThisYear.insert(track.artist)
            trackRows.append((track.artist, track.title, inYear))
        }
        guard plays > 0 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let discoveries = artistPlayedThisYear.filter { artist in
            guard let first = artistFirstEver[artist] else { return false }
            return String(calendar.component(.year, from: Date(timeIntervalSince1970: first))) == year
        }.sorted { (artistPlays[$0] ?? 0) > (artistPlays[$1] ?? 0) }

        let companion = artistPlayedThisYear
            .compactMap { name in artistFirstEver[name].map { (name, $0) } }
            .min { $0.1 < $1.1 }
            .map { (name: $0.0,
                    since: String(calendar.component(.year, from: Date(timeIntervalSince1970: $0.1)))) }

        return Recap(
            year: year,
            plays: plays,
            topArtists: artistPlays.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) },
            topTracks: trackRows.sorted { $0.plays > $1.plays }.prefix(5).map { $0 },
            discoveries: Array(discoveries.prefix(5)),
            oldestCompanion: (companion?.since == year) ? nil : companion,
            previousYearPlays: previous > 0 ? previous : nil)
    }

    /// The year the Recap button should open: the current year if it holds
    /// listening, else the latest year that does.
    func recapYear(now: Date = .now) -> String? {
        let current = String(Calendar.current.component(.year, from: now))
        if recap(year: current) != nil { return current }
        return timeline().first?.year
    }

    /// Years with listening, newest first, each with its top artists.
    func timeline(topPerYear: Int = 3) -> [(year: String, plays: Int, topArtists: [(name: String, plays: Int)])] {
        var perYear: [String: (plays: Int, artists: [String: Int])] = [:]
        for track in journey.tracks.values {
            for (year, count) in track.yearCounts {
                var bucket = perYear[year] ?? (0, [:])
                bucket.plays += count
                bucket.artists[track.artist, default: 0] += count
                perYear[year] = bucket
            }
        }
        return perYear
            .sorted { $0.key > $1.key }
            .map { year, bucket in
                (year, bucket.plays,
                 bucket.artists.sorted { $0.value > $1.value }.prefix(topPerYear)
                    .map { ($0.key, $0.value) })
            }
    }
}
