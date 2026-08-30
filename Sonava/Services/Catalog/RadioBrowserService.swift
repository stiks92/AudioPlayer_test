//
//  RadioBrowserService.swift
//  Sonava
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

    // Round-robin DNS across all mirrors for reliability.
    private let host = "https://all.api.radio-browser.info"

    // MARK: TrackProvider

    /// Most-voted stations worldwide.
    func trending() async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.stations }
        #endif
        let url = URL(string: "\(host)/json/stations/topvote/60?hidebroken=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    func search(_ query: String) async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.stations }
        #endif
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = URL(string: "\(host)/json/stations/search?name=\(Net.encode(trimmed))&limit=60&hidebroken=true&order=votes&reverse=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    /// Stations filtered by a tag/genre (e.g. "jazz", "lofi", "news").
    func stations(tag: String) async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.stations }
        #endif
        let url = URL(string: "\(host)/json/stations/bytag/\(Net.encode(tag))?limit=60&hidebroken=true&order=votes&reverse=true")!
        let stations = try await Net.getJSON(url, as: [RadioStation].self)
        return stations.compactMap(map)
    }

    // MARK: - Mapping

    /// Internal, not private: the mapping is a contract worth pinning in a
    /// test — quality fields must ride through when the directory reports
    /// them and stay absent when it doesn't.
    func map(_ station: RadioStation) -> Song? {
        let streamString = station.urlResolved ?? station.url
        guard let streamString, let stream = URL(string: streamString) else { return nil }
        let subtitle = [station.country, station.tags?.replacingOccurrences(of: ",", with: " · ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first ?? "Live radio"
        // What the directory truthfully knows about the transmission. Radio
        // Browser sends bitrate 0 and codec "UNKNOWN" when a station never
        // told it — both become absent, never a guess. The codec travels as
        // the file extension because that is where `qualityParts` reads a
        // format from, and a station has no path extension to read.
        let codec = station.codec?.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownCodec = (codec?.isEmpty == false && codec?.uppercased() != "UNKNOWN")
            ? codec : nil
        let bitrate = (station.bitrate ?? 0) > 0 ? station.bitrate : nil
        return Song(
            id: "radio:\(station.stationuuid)",
            title: station.name.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: subtitle,
            album: "Radio",
            source: .radio,
            fileExtension: knownCodec?.lowercased() ?? "",
            artworkURL: station.favicon.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            streamURL: stream,
            isLive: true,
            gradientHex: Palette.hex(forSeed: station.stationuuid),
            bitRate: bitrate
        )
    }
}

// MARK: - DTOs

struct RadioStation: Decodable {
    let stationuuid: String
    let name: String
    let url: String?
    let urlResolved: String?
    let favicon: String?
    let country: String?
    let tags: String?
    /// kbit/s as the station registered it; 0 means "never said".
    let bitrate: Int?
    /// "MP3" / "AAC+" / "UNKNOWN" — the transmission codec, when reported.
    let codec: String?

    enum CodingKeys: String, CodingKey {
        case stationuuid, name, url, favicon, country, tags, bitrate, codec
        case urlResolved = "url_resolved"
    }
}
