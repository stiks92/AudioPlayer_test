//
//  iTunesService.swift
//  Sonava
//
//  Podcast discovery via the free, keyless iTunes Search API.
//  https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/
//

import Foundation

final class iTunesService: Sendable {
    static let shared = iTunesService()

    /// Search podcasts by free text.
    func searchPodcasts(_ query: String) async throws -> [Podcast] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "https://itunes.apple.com/search?media=podcast&limit=40&term=\(Net.encode(trimmed))")!
        let response = try await Net.getJSON(url, as: ITunesResponse.self)
        return response.results.compactMap(map)
    }

    /// Podcasts within a genre/term (used by the browse chips).
    func podcasts(genre term: String) async throws -> [Podcast] {
        try await searchPodcasts(term)
    }

    /// Mainstream music as 30-second Apple previews (keyless, legal).
    func searchMusic(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=30&term=\(Net.encode(trimmed))")!
        let response = try await Net.getJSON(url, as: ITunesMusicResponse.self)
        return response.results.compactMap(mapTrack)
    }

    private func mapTrack(_ track: ITunesTrack) -> Song? {
        guard let preview = track.previewUrl, let stream = URL(string: preview) else { return nil }
        let art = (track.artworkUrl100 ?? "").replacingOccurrences(of: "100x100", with: "400x400")
        return Song(
            id: "itunes:\(track.trackId)",
            title: track.trackName ?? "Untitled",
            artist: track.artistName ?? "Unknown artist",
            album: track.collectionName ?? "Apple Music",
            source: .itunes,
            artworkURL: URL(string: art),
            streamURL: stream,
            gradientHex: Palette.hex(forSeed: "\(track.trackId)")
        )
    }

    private func map(_ result: ITunesPodcast) -> Podcast? {
        guard let feed = result.feedUrl, let feedURL = URL(string: feed) else { return nil }
        let artwork = result.artworkUrl600 ?? result.artworkUrl100
        return Podcast(
            title: result.collectionName ?? result.trackName ?? "Podcast",
            author: result.artistName ?? "",
            artworkURL: artwork.flatMap(URL.init(string:)),
            feedURL: feedURL
        )
    }
}

// MARK: - DTOs

private struct ITunesResponse: Decodable {
    let results: [ITunesPodcast]
}

private struct ITunesPodcast: Decodable {
    let collectionName: String?
    let trackName: String?
    let artistName: String?
    let feedUrl: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
}

private struct ITunesMusicResponse: Decodable {
    let results: [ITunesTrack]
}

private struct ITunesTrack: Decodable {
    let trackId: Int
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
    let previewUrl: String?
}
