//
//  RadioBrowserService.swift
//  AudioPlayer_test
//
//  Radio Browser — a free, community-run directory of 40k+ internet radio
//  stations with direct stream URLs. Powers the Radio tab.
//
//  Docs: https://api.radio-browser.info
//

import Foundation
import SwiftUI

final class RadioBrowserService: TrackProvider {

    static let shared = RadioBrowserService()

    let id = "radio"
    let displayName = "Radio"

    // A stable mirror; the service also offers round-robin hosts.
    private let host = "https://de1.api.radio-browser.info"

    // MARK: TrackProvider

    /// Most-voted stations worldwide.
    func trending() async throws -> [Song] {
        let url = URL(string: "\(host)/json/stations/topvote/60?hidebroken=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "\(host)/json/stations/search?name=\(Net.encode(trimmed))&limit=60&hidebroken=true&order=votes&reverse=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    /// Stations filtered by a tag/genre (e.g. "jazz", "lofi", "news").
    func stations(tag: String) async throws -> [Song] {
        let url = URL(string: "\(host)/json/stations/bytag/\(Net.encode(tag))?limit=60&hidebroken=true&order=votes&reverse=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    // MARK: - Mapping

    private func map(_ station: RadioStation) -> Song? {
        let streamString = station.urlResolved ?? station.url
        guard let streamString, let stream = URL(string: streamString) else { return nil }
        let subtitle = [station.country, station.tags?.replacingOccurrences(of: ",", with: " · ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first ?? "Live radio"
        return Song(
            id: "radio:\(station.stationuuid)",
            title: station.name.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: subtitle,
            album: "Radio",
            source: .radio,
            artworkName: "Cover",
            artworkURL: station.favicon.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            streamURL: stream,
            isLive: true,
            gradientHex: Palette.hex(forSeed: station.stationuuid)
        )
    }
}

// MARK: - DTOs

private struct RadioStation: Decodable {
    let stationuuid: String
    let name: String
    let url: String?
    let urlResolved: String?
    let favicon: String?
    let country: String?
    let tags: String?

    enum CodingKeys: String, CodingKey {
        case stationuuid, name, url, favicon, country, tags
        case urlResolved = "url_resolved"
    }
}
