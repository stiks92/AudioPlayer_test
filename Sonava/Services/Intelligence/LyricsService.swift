//
//  LyricsService.swift
//  Sonava
//
//  Synced (karaoke) lyrics from LRCLIB — a free, open lyrics database.
//  https://lrclib.net/docs
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

    private let session = URLSession(configuration: .default)

    /// Returns lyrics for a track, or `nil` if none are available.
    func fetch(artist: String, title: String, album: String?, duration: Double?) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration)))) }
        components.queryItems = items
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }

        let dto = try JSONDecoder().decode(LrcLibResponse.self, from: data)
        let synced = dto.syncedLyrics.map(Self.parseLRC) ?? []
        let lyrics = Lyrics(synced: synced, plain: dto.plainLyrics)
        return lyrics.isEmpty ? nil : lyrics
    }

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

private struct LrcLibResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?
}
