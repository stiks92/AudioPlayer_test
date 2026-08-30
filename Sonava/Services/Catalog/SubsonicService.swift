//
//  SubsonicService.swift
//  Sonava
//
//  Client for the Subsonic API — the de-facto standard spoken by Navidrome,
//  Airsonic, Gonic and friends. Lets a user stream their own self-hosted
//  library. Uses salted token auth (never sends the raw password).
//
//  API: https://www.subsonic.org/pages/api.jsp
//

import Foundation
import SwiftUI
import CryptoKit

// `Sendable` is spelled here rather than inferred because the
// `MusicServerService` conformance (declared beside the protocol) requires
// it, and Swift insists a Sendable promise lives in the type's own file.
struct SubsonicService: Sendable {
    let baseURL: URL
    let username: String
    let password: String
    /// Namespaces track ids. Two servers can hand out the same internal id, so
    /// without this a track from one library could shadow a different track
    /// from another in favourites, downloads and merged search results.
    let libraryID: String

    private let clientName = "Sonava"
    private let apiVersion = "1.16.1"

    // MARK: - Requests

    func ping() async throws -> Bool {
        let body = try await get("ping", as: StatusBody.self)
        return body.status == "ok"
    }

    func randomSongs(count: Int = 40) async throws -> [Song] {
        let body = try await get("getRandomSongs", [URLQueryItem(name: "size", value: String(count))], as: RandomBody.self)
        return (body.randomSongs?.song ?? []).map(map)
    }

    func starred() async throws -> [Song] {
        let body = try await get("getStarred2", as: StarredBody.self)
        return (body.starred2?.song ?? []).map(map)
    }

    /// How many media files the server says it has indexed, or nil if it won't
    /// say.
    ///
    /// This is `getScanStatus`'s `count`, which the API defines as *scanned
    /// media files* — not albums, not artists, and not necessarily playable
    /// tracks. The UI labels it as files for that reason. Plenty of Subsonic
    /// implementations don't answer this call at all, so every failure maps to
    /// nil and the row then claims nothing rather than guessing a number.
    func scannedFileCount() async -> Int? {
        try? await get("getScanStatus", as: ScanStatusBody.self).scanStatus?.count
    }

    /// Albums, the way a record collection is actually navigated.
    ///
    /// `type` is the server's own ordering vocabulary: `newest`, `random`,
    /// `alphabeticalByName`, `frequent`, `recent`, `starred`. Without this the
    /// app could only ever show a server as a flat bag of random songs — no
    /// shelf, no "what did I add last month", and nothing for a CarPlay
    /// browse tree to be built from.
    func albums(type: String = "newest", count: Int = 60, offset: Int = 0) async throws -> [Album] {
        let body = try await get("getAlbumList2", [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "size", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset)),
        ], as: AlbumListBody.self)
        return (body.albumList2?.album ?? []).map(map)
    }

    /// One album with its tracks, in the order the record has them.
    func albumTracks(id: String) async throws -> [Song] {
        let body = try await get("getAlbum", [URLQueryItem(name: "id", value: id)],
                                 as: AlbumBody.self)
        return (body.album?.song ?? []).map(map)
    }

    /// Every artist the server indexes, flattened out of its A–Z buckets.
    func artists() async throws -> [ServerArtist] {
        let body = try await get("getArtists", as: ArtistsBody.self)
        return (body.artists?.index ?? []).flatMap { $0.artist ?? [] }.map {
            ServerArtist(id: $0.id, name: $0.name ?? "Unknown artist",
                         albumCount: $0.albumCount ?? 0,
                         artworkURL: coverArtURL(id: $0.coverArt))
        }
    }

    /// One artist's albums.
    func artistAlbums(id: String) async throws -> [Album] {
        let body = try await get("getArtist", [URLQueryItem(name: "id", value: id)],
                                 as: ArtistBody.self)
        return (body.artist?.album ?? []).map(map)
    }

    /// Playlists the listener made on the server itself — the ones every other
    /// client of theirs can see, which is the whole point of keeping them
    /// there rather than in one app.
    func playlists() async throws -> [ServerPlaylist] {
        let body = try await get("getPlaylists", as: PlaylistsBody.self)
        return (body.playlists?.playlist ?? []).map {
            ServerPlaylist(id: $0.id, name: $0.name ?? "Playlist",
                           songCount: $0.songCount ?? 0,
                           duration: $0.duration.map(Double.init),
                           artworkURL: coverArtURL(id: $0.coverArt))
        }
    }

    func playlistTracks(id: String) async throws -> [Song] {
        let body = try await get("getPlaylist", [URLQueryItem(name: "id", value: id)],
                                 as: PlaylistBody.self)
        return (body.playlist?.entry ?? []).map(map)
    }

    /// Marks a track as starred on the server, so the listener's favourites
    /// are the same set in every client they use.
    func star(id: String, starred: Bool) async throws {
        _ = try await get(starred ? "star" : "unstar",
                          [URLQueryItem(name: "id", value: id)], as: StatusBody.self)
    }

    /// Server-side lyrics, when the server has them.
    func lyrics(id: String) async throws -> String? {
        let body = try await get("getLyricsBySongId", [URLQueryItem(name: "id", value: id)],
                                 as: LyricsBody.self)
        let lines = body.lyricsList?.structuredLyrics?.first?.line ?? []
        let text = lines.compactMap(\.value).joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body = try await get("search3", [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "songCount", value: "50")
        ], as: SearchBody.self)
        return (body.searchResult3?.song ?? []).map(map)
    }

    // MARK: - URLs

    private func authItems() -> [URLQueryItem] {
        let salt = String(UUID().uuidString.prefix(8))
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json")
        ]
    }

    private func endpointURL(_ endpoint: String, _ extra: [URLQueryItem]) -> URL? {
        let full = baseURL.appendingPathComponent("rest").appendingPathComponent(endpoint)
        guard var comps = URLComponents(url: full, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = authItems() + extra
        return comps.url
    }

    func streamURL(id: String) -> URL? {
        endpointURL("stream", [URLQueryItem(name: "id", value: id)])
    }

    func coverArtURL(id: String?) -> URL? {
        guard let id else { return nil }
        return endpointURL("getCoverArt", [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "size", value: "512")
        ])
    }

    private func get<T: Decodable>(_ endpoint: String, _ extra: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        guard let url = endpointURL(endpoint, extra) else { throw URLError(.badURL) }
        let wrapper = try await Net.getJSON(url, as: SubsonicWrapper<T>.self)
        return wrapper.response
    }

    // MARK: - Mapping

    private func map(_ album: SubsonicAlbum) -> Album {
        Album(id: "subsonic:\(libraryID):\(album.id)",
              title: album.name ?? album.title ?? "Album",
              artist: album.artist ?? "Unknown artist",
              songs: (album.song ?? []).map(map),
              year: album.year,
              artworkURL: coverArtURL(id: album.coverArt),
              serverID: album.id,
              trackCountHint: album.songCount)
    }

    private func map(_ song: SubsonicSong) -> Song {
        Song(
            id: "subsonic:\(libraryID):\(song.id)",
            title: song.title ?? "Untitled",
            artist: song.artist ?? "Unknown artist",
            album: song.album ?? "Library",
            source: .subsonic,
            fileExtension: song.suffix ?? "",
            artworkURL: coverArtURL(id: song.coverArt),
            streamURL: streamURL(id: song.id),
            gradientHex: Palette.hex(forSeed: song.id),
            durationSeconds: song.duration.map(Double.init),
            trackNumber: song.track,
            year: song.year,
            bitRate: song.bitRate,
            // OpenSubsonic servers publish this; using it means the app never
            // has to analyse a file it can simply be told about.
            replayGain: song.replayGain?.trackGain,
            credits: song.artists?.map { TrackCredit(id: $0.id, name: $0.name) } ?? [],
            isStarredOnServer: song.starred != nil
        )
    }
}

// MARK: - DTOs

private struct SubsonicWrapper<T: Decodable>: Decodable {
    let response: T
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}

private struct StatusBody: Decodable { let status: String }

private struct RandomBody: Decodable {
    let status: String
    let randomSongs: SongList?
}

private struct StarredBody: Decodable {
    let status: String
    let starred2: SongList?
}

private struct SearchBody: Decodable {
    let status: String
    let searchResult3: SongList?
}

private struct ScanStatusBody: Decodable {
    let status: String
    let scanStatus: ScanStatus?
}

private struct ScanStatus: Decodable {
    let scanning: Bool?
    let count: Int?
}

private struct SongList: Decodable {
    let song: [SubsonicSong]?
}

private struct SubsonicSong: Decodable {
    let id: String
    let title: String?
    let artist: String?
    let album: String?
    let coverArt: String?
    let replayGain: SubsonicReplayGain?
    /// OpenSubsonic's multi-artist list. A track credited to three people has
    /// been collapsing into one comma-joined string, which is why tapping an
    /// artist on a collaboration went nowhere useful.
    let artists: [SubsonicArtistRef]?
    /// Present (as a timestamp) when the listener starred it on the server.
    let starred: String?
    // The API has been sending these on every track; the DTO was discarding
    // them, which is why no list row in the app could state a length, an
    // order, a year or a bit rate.
    let duration: Int?
    let track: Int?
    let year: Int?
    let bitRate: Int?
    let suffix: String?
}

#if DEBUG
extension SubsonicService {
    /// Decoding hooks for tests.
    ///
    /// The mapping from a server's JSON to the app's models is where a client
    /// like this actually breaks — a field renamed, a list nested one level
    /// deeper, a number arriving as a string. Exercising it against captured
    /// payloads is worth more than any amount of testing against a fake, so
    /// these expose the mapper without the network.
    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder()
            .decode(SubsonicWrapper<T>.self, from: Data(json.utf8)).response
    }

    func albumsForTesting(json: String) throws -> [Album] {
        (try decode(json, as: AlbumListBody.self).albumList2?.album ?? []).map(map)
    }

    func albumTracksForTesting(json: String) throws -> [Song] {
        (try decode(json, as: AlbumBody.self).album?.song ?? []).map(map)
    }

    func artistsForTesting(json: String) throws -> [ServerArtist] {
        (try decode(json, as: ArtistsBody.self).artists?.index ?? [])
            .flatMap { $0.artist ?? [] }
            .map { ServerArtist(id: $0.id, name: $0.name ?? "Unknown artist",
                                albumCount: $0.albumCount ?? 0,
                                artworkURL: coverArtURL(id: $0.coverArt)) }
    }

    func playlistsForTesting(json: String) throws -> [ServerPlaylist] {
        (try decode(json, as: PlaylistsBody.self).playlists?.playlist ?? [])
            .map { ServerPlaylist(id: $0.id, name: $0.name ?? "Playlist",
                                  songCount: $0.songCount ?? 0,
                                  duration: $0.duration.map(Double.init),
                                  artworkURL: coverArtURL(id: $0.coverArt)) }
    }
}
#endif

// MARK: - Browse DTOs

private struct AlbumListBody: Decodable {
    let albumList2: AlbumListContainer?
}

private struct AlbumListContainer: Decodable {
    let album: [SubsonicAlbum]?
}

private struct AlbumBody: Decodable {
    let album: SubsonicAlbum?
}

private struct SubsonicAlbum: Decodable {
    let id: String
    /// `getAlbumList2` sends `name`; `getAlbum` sends both. Taking either
    /// keeps one DTO for both calls.
    let name: String?
    let title: String?
    let artist: String?
    let coverArt: String?
    let songCount: Int?
    let year: Int?
    let song: [SubsonicSong]?
}

private struct ArtistsBody: Decodable {
    let artists: ArtistIndexContainer?
}

private struct ArtistIndexContainer: Decodable {
    /// The server groups artists under A, B, C… — a shape the app has no use
    /// for, so it is flattened at the boundary rather than carried inward.
    let index: [ArtistIndex]?
}

private struct ArtistIndex: Decodable {
    let artist: [SubsonicArtist]?
}

private struct SubsonicArtist: Decodable {
    let id: String
    let name: String?
    let albumCount: Int?
    let coverArt: String?
}

private struct ArtistBody: Decodable {
    let artist: ArtistDetail?
}

private struct ArtistDetail: Decodable {
    let album: [SubsonicAlbum]?
}

private struct PlaylistsBody: Decodable {
    let playlists: PlaylistContainer?
}

private struct PlaylistContainer: Decodable {
    let playlist: [SubsonicPlaylist]?
}

private struct SubsonicPlaylist: Decodable {
    let id: String
    let name: String?
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
}

private struct PlaylistBody: Decodable {
    let playlist: PlaylistDetail?
}

private struct PlaylistDetail: Decodable {
    let entry: [SubsonicSong]?
}

/// A credited artist. Only what the app needs: the server sends roles,
/// MusicBrainz ids and sort names that nothing here consumes.
struct SubsonicArtistRef: Decodable, Equatable, Sendable {
    let id: String
    let name: String
}

private struct SubsonicReplayGain: Decodable {
    let trackGain: Double?
    let albumGain: Double?
}

private struct LyricsBody: Decodable {
    let lyricsList: LyricsList?
}

private struct LyricsList: Decodable {
    let structuredLyrics: [StructuredLyrics]?
}

private struct StructuredLyrics: Decodable {
    let line: [SubsonicLyricLine]?
}

/// Named apart from the app's own `LyricLine`, which is a view model with an
/// id and a timestamp — two different things that both describe a line.
private struct SubsonicLyricLine: Decodable {
    let value: String?
}
