//
//  LyricsService.swift
//  Sonava
//
//  Synced (karaoke) lyrics from LRCLIB — a free, open lyrics database.
//  https://lrclib.net/docs
//
//  Two behaviours beyond the obvious fetch, both from the growth scan's
//  quick-win list:
//
//  * `/api/get` wants exact tags, and real libraries don't have exact tags —
//    "Halcyon Drift (feat. Iri) - Radio Edit" misses lyrics that exist under
//    the plain title. On a miss we retry through `/api/search` with the
//    noise trimmed, then pick the candidate whose duration agrees.
//
//  * Every hit is cached on disk, so lyrics work where the marquee Pro
//    feature works: offline. `DownloadStore` warms this cache the moment a
//    track finishes downloading; a plane is exactly where "was the karaoke
//    line there a second ago" stops being answerable by the network.
//

import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double      // seconds
    let text: String
}

struct Lyrics: Equatable {
    let synced: [LyricLine]
    let plain: String?
    var isSynced: Bool { !synced.isEmpty }
    var isEmpty: Bool { synced.isEmpty && (plain?.isEmpty ?? true) }
}

final class LyricsService: Sendable {
    static let shared = LyricsService()

    private let session: URLSession
    private let cacheDirectory: URL

    /// Injectable for tests: a throwaway cache directory, and any session.
    init(session: URLSession = URLSession(configuration: .default),
         cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lyrics", isDirectory: true)
    }

    /// Returns lyrics for a track, or `nil` if none are available.
    /// Order: disk cache, exact `/api/get`, `/api/search` with cleaned tags.
    func fetch(artist: String, title: String, album: String?, duration: Double?) async throws -> Lyrics? {
        if let cached = cachedRaw(artist: artist, title: title) {
            return lyrics(from: cached)
        }
        if let raw = try await exact(artist: artist, title: title, album: album, duration: duration) {
            store(raw, artist: artist, title: title)
            return lyrics(from: raw)
        }
        if let raw = try await search(artist: artist, title: title, duration: duration) {
            store(raw, artist: artist, title: title)
            return lyrics(from: raw)
        }
        return nil
    }

    /// Warms the cache without anyone looking at the result — called when a
    /// download completes, so offline tracks have offline lyrics.
    func prefetch(artist: String, title: String, album: String?, duration: Double?) async {
        guard cachedRaw(artist: artist, title: title) == nil else { return }
        _ = try? await fetch(artist: artist, title: title, album: album, duration: duration)
    }

    // MARK: - Endpoints

    private func exact(artist: String, title: String, album: String?, duration: Double?) async throws -> RawLyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration)))) }
        components.queryItems = items
        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(for: request(url))
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }

        let dto = try JSONDecoder().decode(LrcLibResponse.self, from: data)
        let raw = RawLyrics(synced: dto.syncedLyrics, plain: dto.plainLyrics)
        return raw.isEmpty ? nil : raw
    }

    private func search(artist: String, title: String, duration: Double?) async throws -> RawLyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: Self.searchQuery(title)),
            URLQueryItem(name: "artist_name", value: Self.searchQuery(artist))
        ]
        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(for: request(url))
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
        let candidates = (try? JSONDecoder().decode([LrcLibResponse].self, from: data)) ?? []
        guard let best = Self.bestMatch(from: candidates, duration: duration) else { return nil }
        return RawLyrics(synced: best.syncedLyrics, plain: best.plainLyrics)
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Matching

    /// Trims the tag noise that makes `/api/get` miss — "(feat. …)",
    /// "- Radio Edit", "[Remastered 2011]" — while keeping the words and
    /// spaces a *search* endpoint needs. Deliberately not
    /// `PlaylistImport.normalise`, which strips spaces for identity
    /// comparison and would turn a query into one unsearchable word.
    static func searchQuery(_ text: String) -> String {
        var value = text
        for opener in ["(", "[", " - ", " – ", " feat.", " ft."] {
            if let range = value.range(of: opener, options: .caseInsensitive) {
                value = String(value[..<range.lowerBound])
            }
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? text.trimmingCharacters(in: .whitespaces) : trimmed
    }

    /// The candidate whose duration agrees with the track wins; synced beats
    /// plain; otherwise first non-empty. LRCLIB search returns loose matches,
    /// and a 7-minute album cut's lyrics on a 3-minute radio edit would scroll
    /// off into nowhere by the second chorus.
    static func bestMatch(from candidates: [LrcLibResponse], duration: Double?) -> LrcLibResponse? {
        let usable = candidates.filter {
            !($0.syncedLyrics ?? "").isEmpty || !($0.plainLyrics ?? "").isEmpty
        }
        guard !usable.isEmpty else { return nil }
        if let duration, duration > 0 {
            let agreeing = usable.filter { abs(($0.duration ?? -100) - duration) <= 4 }
            if let synced = agreeing.first(where: { !($0.syncedLyrics ?? "").isEmpty }) { return synced }
            if let any = agreeing.first { return any }
        }
        return usable.first { !($0.syncedLyrics ?? "").isEmpty } ?? usable.first
    }

    // MARK: - Disk cache

    struct RawLyrics: Codable, Equatable {
        let synced: String?
        let plain: String?
        var isEmpty: Bool { (synced ?? "").isEmpty && (plain ?? "").isEmpty }
    }

    private func lyrics(from raw: RawLyrics) -> Lyrics? {
        let result = Lyrics(synced: raw.synced.map(Self.parseLRC) ?? [], plain: raw.plain)
        return result.isEmpty ? nil : result
    }

    func cachedRaw(artist: String, title: String) -> RawLyrics? {
        guard let data = try? Data(contentsOf: cacheFile(artist: artist, title: title)) else { return nil }
        return try? JSONDecoder().decode(RawLyrics.self, from: data)
    }

    func store(_ raw: RawLyrics, artist: String, title: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: cacheFile(artist: artist, title: title), options: .atomic)
    }

    private func cacheFile(artist: String, title: String) -> URL {
        // FNV-1a over the case-folded pair: stable across launches, unlike
        // `hashValue`, which is salted per process.
        let key = "\(artist.lowercased())|\(title.lowercased())"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return cacheDirectory.appendingPathComponent("\(hash).json")
    }

    // MARK: - LRC parsing

    /// Parses an `.lrc` string into timestamped lines.
    static func parseLRC(_ raw: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let tagPattern = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")

        for rawLine in raw.components(separatedBy: .newlines) {
            guard let regex = tagPattern else { break }
            let ns = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            let text = regex.stringByReplacingMatches(
                in: rawLine, range: NSRange(location: 0, length: ns.length), withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)

            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let fracString = ns.substring(with: match.range(at: 3))
                    fraction = (Double(fracString) ?? 0) / pow(10, Double(fracString.count))
                }
                let time = minutes * 60 + seconds + fraction
                if !text.isEmpty {
                    result.append(LyricLine(time: time, text: text))
                }
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}

struct LrcLibResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?
    var duration: Double?
}
