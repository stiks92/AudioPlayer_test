//
//  MusicLibrary.swift
//  Sonava
//
//  The listener's own library: files they imported, tracks they favourited
//  and what they played recently.
//
//  Favourites and recents store whole `Song` snapshots rather than ids, so a
//  track from any source — streaming, radio, server, podcast — survives a
//  relaunch even though only local files exist on disk.
//

import SwiftUI
import Combine

@MainActor
final class MusicLibrary: ObservableObject {

    @Published private(set) var favorites: [Song] = []
    @Published private(set) var recents: [Song] = []

    /// Files the user imported. Owned by `LocalFileStore`; surfaced here so
    /// screens have a single place to ask about "my library".
    var songs: [Song] { localFiles.songs }

    let localFiles: LocalFileStore

    private let favoritesStore = JSONFileStore<[Song]>("favorites.json", default: [])
    private let recentsStore = JSONFileStore<[Song]>("recents.json", default: [])
    private static let maxRecents = 20

    private var cancellables = Set<AnyCancellable>()

    init(localFiles: LocalFileStore = LocalFileStore()) {
        self.localFiles = localFiles
        favorites = favoritesStore.read()
        recents = recentsStore.read()

        // `songs` is a passthrough to another object, so SwiftUI would not see
        // an import as a change to *this* one. Forward the notification.
        localFiles.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Lookups

    func song(withID id: String) -> Song? {
        songs.first { $0.id == id }
    }

    var favoriteSongs: [Song] { favorites }
    var recentSongs: [Song] { recents }

    /// On-device model of the listener's taste, from favourites + recents.
    var tasteProfile: TasteProfile {
        TasteProfile.build(favorites: favorites, recents: recents)
    }

    /// Everything the listener already has — so recommendations don't suggest
    /// tracks back at them.
    var knownTrackIDs: Set<String> {
        Set(favorites.map(\.id) + recents.map(\.id) + songs.map(\.id))
    }

    /// Searches the user's own files. Remote catalogues are searched by their
    /// own services; `SearchView` merges the results.
    func search(_ query: String) -> [Song] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return songs.filter {
            $0.title.lowercased().contains(needle)
                || $0.artist.lowercased().contains(needle)
                || $0.album.lowercased().contains(needle)
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
        favoritesStore.write(favorites)
    }

    // MARK: - Recents

    func markPlayed(_ song: Song) {
        recents.removeAll { $0.id == song.id }
        recents.insert(song, at: 0)
        if recents.count > Self.maxRecents {
            recents = Array(recents.prefix(Self.maxRecents))
        }
        recentsStore.write(recents)
    }

    // MARK: - Importing

    @discardableResult
    func importFiles(at urls: [URL]) async -> [Song] {
        await localFiles.importFiles(at: urls)
    }

    func remove(_ song: Song) {
        localFiles.remove(song)
        favorites.removeAll { $0.id == song.id }
        recents.removeAll { $0.id == song.id }
        favoritesStore.write(favorites)
        recentsStore.write(recents)
    }
}
