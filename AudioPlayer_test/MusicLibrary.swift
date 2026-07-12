//
//  MusicLibrary.swift
//  AudioPlayer_test
//
//  Owns the catalogue of songs and playlists plus lightweight
//  user state (favorites + recently played) persisted to UserDefaults.
//

import SwiftUI
import Combine

@MainActor
final class MusicLibrary: ObservableObject {

    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favoriteFiles: Set<String> = []
    @Published private(set) var recentFiles: [String] = []

    private let favoritesKey = "favorite.files.v1"
    private let recentsKey = "recent.files.v1"
    private let maxRecents = 12

    init() {
        songs = MusicLibrary.makeCatalogue()
        favoriteFiles = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentFiles = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        playlists = makePlaylists()
    }

    // MARK: - Lookups

    func song(withID id: UUID) -> Song? {
        songs.first { $0.id == id }
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { id in songs.first { $0.id == id } }
    }

    var favoriteSongs: [Song] {
        songs.filter { favoriteFiles.contains($0.fileName) }
    }

    var recentSongs: [Song] {
        recentFiles.compactMap { file in songs.first { $0.fileName == file } }
    }

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
        favoriteFiles.contains(song.fileName)
    }

    func toggleFavorite(_ song: Song) {
        if favoriteFiles.contains(song.fileName) {
            favoriteFiles.remove(song.fileName)
        } else {
            favoriteFiles.insert(song.fileName)
        }
        UserDefaults.standard.set(Array(favoriteFiles), forKey: favoritesKey)
    }

    // MARK: - Recents

    func markPlayed(_ song: Song) {
        recentFiles.removeAll { $0 == song.fileName }
        recentFiles.insert(song.fileName, at: 0)
        if recentFiles.count > maxRecents {
            recentFiles = Array(recentFiles.prefix(maxRecents))
        }
        UserDefaults.standard.set(recentFiles, forKey: recentsKey)
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
                gradient: [Color(hex: 0x8E2DE2), Color(hex: 0x4A00E0)],
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
                gradient: [Color(hex: 0x11998E), Color(hex: 0x38EF7D)],
                songIDs: Array(all.shuffled().prefix(6))
            )
        ]
    }

    // MARK: - Catalogue

    private static func makeCatalogue() -> [Song] {
        let gradients: [[Color]] = [
            [Color(hex: 0x7C5CFF), Color(hex: 0x3A1C71)],
            [Color(hex: 0xFF6FD8), Color(hex: 0x3813C2)],
            [Color(hex: 0x11998E), Color(hex: 0x38EF7D)],
            [Color(hex: 0xF7971E), Color(hex: 0xFFD200)],
            [Color(hex: 0xFC466B), Color(hex: 0x3F5EFB)],
            [Color(hex: 0x00C6FF), Color(hex: 0x0072FF)],
            [Color(hex: 0xFF512F), Color(hex: 0xDD2476)],
            [Color(hex: 0x8E2DE2), Color(hex: 0x4A00E0)],
            [Color(hex: 0xF953C6), Color(hex: 0xB91D73)],
            [Color(hex: 0x43CEA2), Color(hex: 0x185A9D)],
            [Color(hex: 0xFF9966), Color(hex: 0xFF5E62)],
            [Color(hex: 0x36D1DC), Color(hex: 0x5B86E5)],
            [Color(hex: 0xC33764), Color(hex: 0x1D2671)],
            [Color(hex: 0xFDC830), Color(hex: 0xF37335)],
            [Color(hex: 0x1FA2FF), Color(hex: 0x12D8FA)],
            [Color(hex: 0xEC008C), Color(hex: 0xFC6767)],
            [Color(hex: 0x654EA3), Color(hex: 0xEAAFC8)]
        ]

        let titles = [
            "Hoyt's Office", "Defeated Clown", "Following Sophie",
            "Penny in the Hospital", "Young Penny", "Meeting Bruce Wayne",
            "Hiding in the Fridge", "A Bad Comedian", "Arthur Comes to Sophie",
            "Looking for Answers", "Penny Taken to the Hospital", "Subway",
            "Bathroom Dance", "Learning How to Act Normal", "Confession",
            "Escape from the Train", "Call Me Joker"
        ]

        return titles.enumerated().map { index, title in
            Song(
                title: title,
                artist: "Hildur Guðnadóttir",
                album: "Joker",
                fileName: "song\(index + 1)",
                gradient: gradients[index % gradients.count]
            )
        }
    }
}
