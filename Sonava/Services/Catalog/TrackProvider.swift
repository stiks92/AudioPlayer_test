//
//  TrackProvider.swift
//  Sonava
//
//  The `MusicSource` abstraction (Phase 1: direct-stream providers) plus a
//  tiny async networking helper shared by all providers.
//

import Foundation

/// A remote catalogue that yields universal `Song` values.
protocol TrackProvider {
    var id: String { get }
    var displayName: String { get }

    /// A "what's hot" shelf for the browse experience.
    func trending() async throws -> [Song]
    /// Free-text search.
    func search(_ query: String) async throws -> [Song]
}

/// Minimal JSON-over-HTTPS helper with sane timeouts and a User-Agent.
enum Net {
    static let userAgent = "Sonava/1.0 (iOS music aggregator)"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20   // hard ceiling so requests never hang
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func getJSON<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Percent-encodes a query component for safe URL building.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
