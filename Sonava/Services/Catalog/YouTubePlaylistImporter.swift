//
//  YouTubePlaylistImporter.swift
//  Sonava
//
//  A YouTube playlist link, read as a *list of names* — nothing more.
//
//  YouTube's developer policies forbid third-party audio playback outright
//  (background play, audio-only extraction, all of it), so this deliberately
//  never touches a stream: it asks the Data API v3 for the playlist's
//  titles, turns "Artist - Title (Official Video)" into the importer's
//  ParsedTrack, and hands the list to the same matching pipeline every other
//  import uses. The music the listener ends up playing comes from their own
//  sources, found honestly. Composition only — that is the legal line, and
//  this file stays on the right side of it.
//
//  Needs the owner's Google Cloud API key (`youtube.apiKey` in
//  ServiceKeysStore); without one the import screen points at the keys
//  screen instead of failing quietly.
//

import Foundation

struct YouTubePlaylistImporter: Sendable {

    let apiKey: String

    /// The `ServiceKeysStore` key the owner's API key lives under.
    static let apiKeyKey = "youtube.apiKey"

    /// Playlists longer than this are cut off honestly: four pages of fifty
    /// is already more than any human playlist migration needs at once.
    private static let maxPages = 4

    // MARK: - Link parsing

    /// Pulls the playlist id out of whatever the listener pasted:
    /// youtube.com/playlist?list=…, a watch?v=…&list=… link, music.youtube.com,
    /// youtu.be short links, or a bare "PL…" id from a chat.
    static func playlistID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isPlaylistID(trimmed) { return trimmed }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased() else { return nil }
        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        guard isYouTube else { return nil }
        guard let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
              isPlaylistID(list) else { return nil }
        return list
    }

    private static func isPlaylistID(_ value: String) -> Bool {
        guard value.count >= 10,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return false }
        // "RD…" mixes are session-generated radio — the Data API cannot read
        // them, so refusing here beats a confusing 404 later.
        return !value.hasPrefix("RD")
    }

    // MARK: - Fetch

    /// The playlist's rows as parse results — names only, ready for the
    /// resolver. Throws when the key is wrong or the playlist is private.
    func tracks(playlistID: String) async throws -> [PlaylistImport.ParsedTrack] {
        var tracks: [PlaylistImport.ParsedTrack] = []
        var pageToken: String?
        for _ in 0..<Self.maxPages {
            var address = "https://www.googleapis.com/youtube/v3/playlistItems"
                + "?part=snippet&maxResults=50"
                + "&playlistId=\(Net.encode(playlistID))&key=\(Net.encode(apiKey))"
            if let pageToken { address += "&pageToken=\(Net.encode(pageToken))" }
            let page = try await Net.getJSON(URL(string: address)!, as: YouTubePlaylistPage.self)
            tracks.append(contentsOf: Self.parsedTracks(from: page))
            guard let next = page.nextPageToken, !next.isEmpty else { break }
            pageToken = next
        }
        return tracks
    }

    // MARK: - Mapping (static so tests reach it without the network)

    static func parsedTracks(fromJSON data: Data) throws -> [PlaylistImport.ParsedTrack] {
        parsedTracks(from: try JSONDecoder().decode(YouTubePlaylistPage.self, from: data))
    }

    static func parsedTracks(from page: YouTubePlaylistPage) -> [PlaylistImport.ParsedTrack] {
        page.items.compactMap { item in
            guard let snippet = item.snippet, let title = snippet.title else { return nil }
            return parsedTrack(title: title, channel: snippet.videoOwnerChannelTitle)
        }
    }

    /// One video row → one importable track, or nil for the tombstones the
    /// API leaves where videos used to be.
    static func parsedTrack(title: String, channel: String?) -> PlaylistImport.ParsedTrack? {
        // Literal API values for removed rows, not user-facing strings.
        guard title != "Private video", title != "Deleted video" else { return nil }
        let cleaned = cleanTitle(title)
        guard !cleaned.isEmpty else { return nil }
        let track = PlaylistImport.split(cleaned)
        guard !track.artist.isEmpty else {
            // No dash in the title: on auto-generated music channels the
            // channel itself is "Artist - Topic", which is the best credit
            // there is.
            let owner = channel?
                .replacingOccurrences(of: " - Topic", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            return PlaylistImport.ParsedTrack(title: track.title, artist: owner, album: nil)
        }
        return track
    }

    /// Strips the video-title dressing — "(Official Video)", "[HD]",
    /// "(Lyrics)" — that would otherwise end up inside the search query.
    /// Brackets carrying real information ("(Acoustic)") survive.
    static func cleanTitle(_ raw: String) -> String {
        let noise = ["official", "video", "audio", "lyric", "lyrics", "visualizer",
                     "visualiser", "hd", "4k", "hq", "mv", "m/v", "full album",
                     "премьера", "клип", "видео"]
        var value = raw
        for pattern in [/\(([^()]*)\)/, /\[([^\[\]]*)\]/] {
            value = value.replacing(pattern) { match in
                let inner = String(match.output.1).lowercased()
                return noise.contains(where: { inner.contains($0) }) ? "" : String(match.output.0)
            }
        }
        return value
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - DTOs

/// One page of `playlistItems?part=snippet`, decoded down to the two fields
/// composition needs: the row's title and the video owner's channel.
struct YouTubePlaylistPage: Decodable {
    let nextPageToken: String?
    let items: [Item]

    struct Item: Decodable {
        let snippet: Snippet?
    }

    struct Snippet: Decodable {
        let title: String?
        let videoOwnerChannelTitle: String?
    }

    enum CodingKeys: String, CodingKey { case nextPageToken, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try? c.decode(String.self, forKey: .nextPageToken)
        items = (try? c.decode([Item].self, forKey: .items)) ?? []
    }
}
