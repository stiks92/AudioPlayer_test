//
//  DeezerService.swift
//  Sonava
//
//  Deezer — a huge mainstream catalogue. Its public search & chart endpoints
//  are keyless and return 30-second preview streams + high-res artwork.
//  Great for discovery and unified search.
//

import Foundation
import SwiftUI

final class DeezerService: TrackProvider {
    static let shared = DeezerService()

    let id = "deezer"
    let displayName = "Deezer"

    func trending() async throws -> [Song] {
        try await chartTracks()
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "https://api.deezer.com/search?q=\(Net.encode(trimmed))&limit=30")!
        let response = try await Net.getJSON(url, as: DeezerListResponse.self)
        return response.data.compactMap(map)
    }

    /// Global top tracks.
    func chartTracks() async throws -> [Song] {
        let url = URL(string: "https://api.deezer.com/chart/0/tracks?limit=30")!
        let response = try await Net.getJSON(url, as: DeezerListResponse.self)
        return response.data.compactMap(map)
    }

    /// Editorial / charting playlists for the browse experience.
    func chartPlaylists() async throws -> [RemotePlaylist] {
        let url = URL(string: "https://api.deezer.com/chart/0/playlists?limit=20")!
        let response = try await Net.getJSON(url, as: DeezerPlaylistList.self)
        return response.data.map { p in
            RemotePlaylist(
                id: "deezer-pl:\(p.id)",
                title: p.title,
                subtitle: String(localized: "\(p.nbTracks ?? 0) tracks"),
                artworkURL: (p.pictureBig ?? p.pictureMedium).flatMap(URL.init(string:)),
                gradientHex: Palette.hex(forSeed: "\(p.id)"),
                fetchID: String(p.id)
            )
        }
    }

    /// Tracks inside a Deezer playlist.
    func playlistTracks(_ id: String) async throws -> [Song] {
        let url = URL(string: "https://api.deezer.com/playlist/\(id)/tracks?limit=60")!
        let response = try await Net.getJSON(url, as: DeezerListResponse.self)
        return response.data.compactMap(map)
    }

    private func map(_ track: DeezerTrack) -> Song? {
        guard let preview = track.preview, !preview.isEmpty, let stream = URL(string: preview) else { return nil }
        let art = track.album?.coverBig ?? track.album?.coverMedium
        return Song(
            id: "deezer:\(track.id)",
            title: track.title,
            artist: track.artist?.name ?? "Unknown artist",
            album: track.album?.title ?? "Deezer",
            source: .deezer,
            artworkURL: art.flatMap(URL.init(string:)),
            streamURL: stream,
            gradientHex: Palette.hex(forSeed: "\(track.id)")
        )
    }
}

// MARK: - Curated playlist model

struct RemotePlaylist: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let gradientHex: [UInt]
    let fetchID: String            // provider-side id used to load tracks

    var gradient: [Color] { gradientHex.colors }
}

// MARK: - DTOs

private struct DeezerListResponse: Decodable {
    let data: [DeezerTrack]
}

private struct DeezerPlaylistList: Decodable {
    let data: [DeezerPlaylist]
}

private struct DeezerPlaylist: Decodable {
    let id: Int
    let title: String
    let nbTracks: Int?
    let pictureMedium: String?
    let pictureBig: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case nbTracks = "nb_tracks"
        case pictureMedium = "picture_medium"
        case pictureBig = "picture_big"
    }
}

private struct DeezerTrack: Decodable {
    let id: Int
    let title: String
    let preview: String?
    let artist: DeezerArtist?
    let album: DeezerAlbum?
}

private struct DeezerArtist: Decodable {
    let name: String?
}

private struct DeezerAlbum: Decodable {
    let title: String?
    let coverMedium: String?
    let coverBig: String?

    enum CodingKeys: String, CodingKey {
        case title
        case coverMedium = "cover_medium"
        case coverBig = "cover_big"
    }
}
