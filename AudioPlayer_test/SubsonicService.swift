//
//  SubsonicService.swift
//  AudioPlayer_test
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

struct SubsonicService {
    let baseURL: URL
    let username: String
    let password: String

    private let clientName = "Aurora"
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

    private func map(_ song: SubsonicSong) -> Song {
        Song(
            id: "subsonic:\(song.id)",
            title: song.title ?? "Untitled",
            artist: song.artist ?? "Unknown artist",
            album: song.album ?? "Library",
            source: .subsonic,
            artworkURL: coverArtURL(id: song.coverArt),
            streamURL: streamURL(id: song.id),
            gradientHex: Palette.hex(forSeed: song.id)
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

private struct SongList: Decodable {
    let song: [SubsonicSong]?
}

private struct SubsonicSong: Decodable {
    let id: String
    let title: String?
    let artist: String?
    let album: String?
    let coverArt: String?
}
