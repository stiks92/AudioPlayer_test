//
//  MusicLibrary.swift
//  AudioPlayer_test
//
//  Owns the bundled catalogue + curated playlists plus lightweight
//  user state (favorites + recently played) persisted to UserDefaults.
//  Tracks are keyed by their stable `id` so the same store works for
//  local and (later) remote tracks.
//

import SwiftUI
import Combine

@MainActor
final class MusicLibrary: ObservableObject {

    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var recentIDs: [String] = []

    private let favoritesKey = "favorite.ids.v2"
    private let recentsKey = "recent.ids.v2"
    private let maxRecents = 12

    init() {
        songs = MusicLibrary.makeCatalogue()
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentIDs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        playlists = makePlaylists()
    }

    // MARK: - Lookups

    func song(withID id: String) -> Song? {
        songs.first { $0.id == id }
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { id in songs.first { $0.id == id } }
    }

    var favoriteSongs: [Song] {
        songs.filter { favoriteIDs.contains($0.id) }
    }

    var recentSongs: [Song] {
        recentIDs.compactMap { id in songs.first { $0.id == id } }
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
        favoriteIDs.contains(song.id)
    }

    func toggleFavorite(_ song: Song) {
        if favoriteIDs.contains(song.id) {
            favoriteIDs.remove(song.id)
        } else {
            favoriteIDs.insert(song.id)
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    // MARK: - Recents

    func markPlayed(_ song: Song) {
        recentIDs.removeAll { $0 == song.id }
        recentIDs.insert(song.id, at: 0)
        if recentIDs.count > maxRecents {
            recentIDs = Array(recentIDs.prefix(maxRecents))
        }
        UserDefaults.standard.set(recentIDs, forKey: recentsKey)
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
                gradient: Palette.gradient(for: index)
            )
        }
    }
}
