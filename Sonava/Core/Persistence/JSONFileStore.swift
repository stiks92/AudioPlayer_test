//
//  JSONFileStore.swift
//  Sonava
//
//  One place that knows how the app puts Codable values on disk. Favourites,
//  recents and playlists each used to carry their own copy of this, with
//  slightly different error handling.
//

import Foundation

/// A typed, atomically-written JSON file in Application Support.
///
/// Reads never throw: a missing or corrupt file yields the default value, which
/// is the right behaviour for caches of user state — losing a favourites list is
/// bad, refusing to launch because of it is worse.
struct JSONFileStore<Value: Codable & Sendable>: Sendable {

    private let filename: String
    private let defaultValue: Value

    init(_ filename: String, default defaultValue: Value) {
        self.filename = filename
        self.defaultValue = defaultValue
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    var url: URL { Self.directory.appendingPathComponent(filename) }

    func read() -> Value {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Value.self, from: data)
        else { return defaultValue }
        return value
    }

    func write(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
