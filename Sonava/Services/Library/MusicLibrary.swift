//
//  MusicLibrary.swift
//  Sonava
//
//  Owns the bundled catalogue + curated playlists plus the user's favorites
//  and recently-played. Favorites/recents store full `Song` snapshots (JSON
//  on disk) so tracks from any source — streaming, radio, server, podcast —
//  survive relaunches, not just bundled songs.
//

import SwiftUI
import Combine

@MainActor
final class MusicLibrary: ObservableObject {

    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favorites: [Song] = []
    @Published private(set) var recents: [Song] = []

    private let favoritesFile = "favorites.json"
    private let recentsFile = "recents.json"
    private let maxRecents = 20

    init() {
        songs = MusicLibrary.makeCatalogue()
        favorites = MusicLibrary.load(favoritesFile)
        recents = MusicLibrary.load(recentsFile)
        playlists = makePlaylists()
    }

    // MARK: - Lookups

    func song(withID id: String) -> Song? {
        songs.first { $0.id == id }
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { id in songs.first { $0.id == id } }
    }

    var favoriteSongs: [Song] { favorites }
    var recentSongs: [Song] { recents }

    func search(_ query: String) -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return songs.filter {
            $0.title.lowercased().contains(trimmed) ||
            $0.artist.lowercased().contains(trimmed) ||
            $0.album.lowercased().contains(trimmed)
        }
    }

    // MARK: - Favorites

    func isFavorite(_ song: Song) -> Bool {
        favorites.contains { $0.id == song.id }
    }

    func toggleFavorite(_ song: Song) {
        if let index = favorites.firstIndex(where: { $0.id == song.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(song, at: 0)
        }
        MusicLibrary.save(favorites, to: favoritesFile)
    }

    // MARK: - Recents

    func markPlayed(_ song: Song) {
        recents.removeAll { $0.id == song.id }
        recents.insert(song, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        MusicLibrary.save(recents, to: recentsFile)
    }

    // MARK: - Persistence

    private static func fileURL(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func load(_ name: String) -> [Song] {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url),
              let songs = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return songs
    }

    private static func save(_ songs: [Song], to name: String) {
        guard let url = fileURL(name), let data = try? JSONEncoder().encode(songs) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Playlists (curated / derived)

    private func makePlaylists() -> [Playlist] {
        guard !songs.isEmpty else { return [] }
        let all = songs.map(\.id)
        return [
            Playlist(
                title: "Joker — Original Score",
                subtitle: "\(songs.count) songs · Hildur Guðnadóttir",
                systemImage: "theatermasks.fill",
                gradient: [Color(hex: 0x8E2DE2), Theme.accentDeep],
                songIDs: all
            ),
            Playlist(
                title: "Late Night Focus",
                subtitle: "Cinematic & calm",
                systemImage: "moon.stars.fill",
                gradient: [Color(hex: 0x0F2027), Color(hex: 0x2C5364)],
                songIDs: Array(all.prefix(8))
            ),
            Playlist(
                title: "Dramatic Peaks",
                subtitle: "Big, bold moments",
                systemImage: "flame.fill",
                gradient: [Color(hex: 0xFF512F), Color(hex: 0xDD2476)],
                songIDs: Array(all.suffix(7))
            ),
            Playlist(
                title: "On Repeat",
                subtitle: "Your most-played",
                systemImage: "arrow.triangle.2.circlepath",
                gradient: [Color(hex: 0x11998E), Theme.positive],
                songIDs: Array(all.shuffled().prefix(6))
            )
        ]
    }

    // MARK: - Catalogue

    private static func makeCatalogue() -> [Song] {
        let titles = [
            "Hoyt's Office", "Defeated Clown", "Following Sophie",
            "Penny in the Hospital", "Young Penny", "Meeting Bruce Wayne",
            "Hiding in the Fridge", "A Bad Comedian", "Arthur Comes to Sophie",
            "Looking for Answers", "Penny Taken to the Hospital", "Subway",
            "Bathroom Dance", "Learning How to Act Normal", "Confession",
            "Escape from the Train", "Call Me Joker"
        ]

        return titles.enumerated().map { index, title in
            let file = "song\(index + 1)"
            return Song(
                id: "local:\(file)",
                title: title,
                artist: "Hildur Guðnadóttir",
                album: "Joker",
                source: .local,
                fileName: file,
                gradientHex: Palette.hex(for: index)
            )
        }
    }
}
