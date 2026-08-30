//
//  JamendoService.swift
//  Sonava
//
//  Jamendo — a quarter-million Creative Commons tracks with full-length
//  streaming through a free, self-serve API key. The key is the owner's
//  (devportal.jamendo.com, no review queue); until one is pasted into
//  `ServiceKeysStore` under `jamendo.clientID`, the service simply isn't
//  constructed and the hub card says why.
//
//  Docs: https://developer.jamendo.com/v3.0/tracks
//

import Foundation

struct JamendoService: TrackProvider {

    let clientID: String

    let id = "jamendo"
    let displayName = "Jamendo"

    /// The `ServiceKeysStore` key the owner's client id lives under.
    static let clientIDKey = "jamendo.clientID"

    // MARK: TrackProvider

    func trending() async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.trending }
        #endif
        let url = URL(string: "https://api.jamendo.com/v3.0/tracks/?client_id=\(Net.encode(clientID))"
            + "&format=json&limit=30&order=popularity_week&audioformat=mp32")!
        let envelope = try await Net.getJSON(url, as: JamendoEnvelope.self)
        return try Self.songs(from: envelope)
    }

    func search(_ query: String) async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.searchResults }
        #endif
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "https://api.jamendo.com/v3.0/tracks/?client_id=\(Net.encode(clientID))"
            + "&format=json&limit=30&search=\(Net.encode(trimmed))&audioformat=mp32")!
        let envelope = try await Net.getJSON(url, as: JamendoEnvelope.self)
        return try Self.songs(from: envelope)
    }

    // MARK: - Mapping (static so tests reach it without the network)

    static func songs(fromJSON data: Data) throws -> [Song] {
        try songs(from: JSONDecoder().decode(JamendoEnvelope.self, from: data))
    }

    static func songs(from envelope: JamendoEnvelope) throws -> [Song] {
        // Jamendo answers HTTP 200 even when refusing — the truth is in the
        // headers block ("suspended", "rate limit"), so an error there must
        // surface as an error, not as an empty shelf.
        if let headers = envelope.headers, headers.status == "failed" {
            throw URLError(.badServerResponse)
        }
        return envelope.results.compactMap(song)
    }

    private static func song(_ track: JamendoTrack) -> Song? {
        guard let audio = track.audio, !audio.isEmpty, let stream = URL(string: audio) else { return nil }
        return Song(
            id: "jamendo:\(track.id)",
            title: track.name,
            artist: track.artistName ?? "Unknown artist",
            album: track.albumName ?? "Jamendo",
            source: .jamendo,
            artworkURL: (track.albumImage ?? track.image).flatMap(URL.init(string:)),
            streamURL: stream,
            gradientHex: Palette.hex(forSeed: "jamendo:\(track.id)"),
            durationSeconds: track.duration.map(Double.init)
        )
    }
}

// MARK: - DTOs

struct JamendoEnvelope: Decodable {
    let headers: JamendoHeaders?
    let results: [JamendoTrack]

    enum CodingKeys: String, CodingKey { case headers, results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headers = try? c.decode(JamendoHeaders.self, forKey: .headers)
        results = (try? c.decode([JamendoTrack].self, forKey: .results)) ?? []
    }
}

struct JamendoHeaders: Decodable {
    let status: String?
    let code: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status, code
        case errorMessage = "error_message"
    }
}

struct JamendoTrack: Decodable {
    let id: String
    let name: String
    let duration: Int?
    let artistName: String?
    let albumName: String?
    let albumImage: String?
    let image: String?
    let audio: String?

    enum CodingKeys: String, CodingKey {
        case id, name, duration, image, audio
        case artistName = "artist_name"
        case albumName = "album_name"
        case albumImage = "album_image"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Jamendo's ids and durations have shipped as both numbers and
        // strings across API revisions; take either.
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        if let number = try? c.decode(Int.self, forKey: .duration) {
            duration = number
        } else {
            duration = (try? c.decode(String.self, forKey: .duration)).flatMap { Int($0) }
        }
        artistName = try? c.decode(String.self, forKey: .artistName)
        albumName = try? c.decode(String.self, forKey: .albumName)
        albumImage = try? c.decode(String.self, forKey: .albumImage)
        image = try? c.decode(String.self, forKey: .image)
        audio = try? c.decode(String.self, forKey: .audio)
    }
}
