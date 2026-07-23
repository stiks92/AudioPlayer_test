//
//  PlaylistStore.swift
//  Sonava
//
//  User-created, cross-source playlists. Because tracks can come from any
//  source (local, Audius, radio, server, podcast), full `Song` snapshots are
//  persisted (JSON on disk) rather than just ids.
//

import SwiftUI
import Combine

struct UserPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tracks: [Song]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, tracks: [Song] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdAt = createdAt
    }

    var gradientHex: [UInt] { tracks.first?.gradientHex ?? Palette.hex(forSeed: name) }
    var gradient: [Color] { gradientHex.colors }
    var subtitle: String { tracks.isEmpty ? "Empty" : "\(tracks.count) track\(tracks.count == 1 ? "" : "s")" }
}

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [UserPlaylist] = []

    private let fileName = "user_playlists.json"

    init() {
        load()
    }

    // MARK: - Mutations

    @discardableResult
    func create(_ name: String) -> UserPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let playlist = UserPlaylist(name: trimmed.isEmpty ? "New Playlist" : trimmed)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name.trimmingCharacters(in: .whitespaces)
        persist()
    }

    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
    }

    func addTrack(_ song: Song, to id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[index].tracks.contains(song) else { return }
        playlists[index].tracks.append(song)
        persist()
        Haptics.success()
    }

    func removeTrack(_ song: Song, from id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].tracks.removeAll { $0 == song }
        persist()
    }

    func contains(_ song: Song, in id: UUID) -> Bool {
        playlists.first(where: { $0.id == id })?.tracks.contains(song) ?? false
    }

    func playlist(_ id: UUID) -> UserPlaylist? {
        playlists.first { $0.id == id }
    }

    /// Adds a playlist that arrived via a shared link. Returns it so the caller
    /// can navigate to it. Re-importing the same link twice is idempotent —
    /// matched by name + track set rather than id (the id is always fresh).
    @discardableResult
    func importShared(_ playlist: UserPlaylist) -> UserPlaylist {
        if let existing = playlists.first(where: {
            $0.name == playlist.name && $0.tracks == playlist.tracks
        }) {
            return existing
        }
        playlists.insert(playlist, at: 0)
        persist()
        Haptics.success()
        return playlist
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlists = decoded
        }
    }

    private func persist() {
        guard let url = fileURL else { return }
        if let data = try? JSONEncoder().encode(playlists) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
