//
//  AudiusService.swift
//  AudioPlayer_test
//
//  Audius — an open, decentralized music catalogue that allows full-track
//  streaming with no user auth. This is the core free/legal source.
//
//  Docs: https://audius.org/en/developers  (host discovery + /v1 endpoints)
//

import Foundation
import SwiftUI

final class AudiusService: TrackProvider {

    static let shared = AudiusService()

    let id = "audius"
    let displayName = "Audius"

    private let appName = "Aurora"
    private var cachedHost: String?

    // MARK: TrackProvider

    func trending() async throws -> [Song] {
        let host = try await host()
        let url = URL(string: "\(host)/v1/tracks/trending?app_name=\(appName)")!
        let response = try await Net.getJSON(url, as: AudiusTracksResponse.self)
        return response.data.compactMap { map($0, host: host) }
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let host = try await host()
        let url = URL(string: "\(host)/v1/tracks/search?query=\(Net.encode(trimmed))&app_name=\(appName)")!
        let response = try await Net.getJSON(url, as: AudiusTracksResponse.self)
        return response.data.compactMap { map($0, host: host) }
    }

    // MARK: - Host discovery

    /// Audius is served by many discovery nodes; pick one and cache it.
    private func host() async throws -> String {
        if let cachedHost { return cachedHost }
        let url = URL(string: "https://api.audius.co")!
        let response = try await Net.getJSON(url, as: AudiusHostsResponse.self)
        guard let host = response.data.randomElement(), !host.isEmpty else {
            throw URLError(.cannotFindHost)
        }
        cachedHost = host
        return host
    }

    // MARK: - Mapping

    private func map(_ track: AudiusTrack, host: String) -> Song? {
        guard !track.isStreamGated else { return nil }
        let stream = URL(string: "\(host)/v1/tracks/\(track.id)/stream?app_name=\(appName)")
        guard let stream else { return nil }
        let art = track.artwork?.large ?? track.artwork?.medium
        return Song(
            id: "audius:\(track.id)",
            title: track.title,
            artist: track.user.name,
            album: "Audius",
            source: .audius,
            artworkName: "Cover",
            artworkURL: art.flatMap(URL.init(string:)),
            streamURL: stream,
            gradientHex: Palette.hex(forSeed: track.id)
        )
    }
}

// MARK: - DTOs

private struct AudiusHostsResponse: Decodable {
    let data: [String]
}

private struct AudiusTracksResponse: Decodable {
    let data: [AudiusTrack]
}

private struct AudiusTrack: Decodable {
    let id: String
    let title: String
    let user: AudiusUser
    let artwork: AudiusArtwork?
    let isStreamGated: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, user, artwork
        case isStreamGated = "is_stream_gated"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        user = try c.decode(AudiusUser.self, forKey: .user)
        artwork = try? c.decode(AudiusArtwork.self, forKey: .artwork)
        isStreamGated = (try? c.decode(Bool.self, forKey: .isStreamGated)) ?? false
    }
}

private struct AudiusUser: Decodable {
    let name: String
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown artist"
    }
    enum CodingKeys: String, CodingKey { case name }
}

private struct AudiusArtwork: Decodable {
    let medium: String?
    let large: String?
    enum CodingKeys: String, CodingKey {
        case medium = "480x480"
        case large = "1000x1000"
    }
}
