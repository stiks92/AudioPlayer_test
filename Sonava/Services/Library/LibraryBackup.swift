//
//  LibraryBackup.swift
//  Sonava
//
//  Export everything the listener built, and put it back on another phone.
//
//  ## Why this exists before any new feature
//
//  Two review corpora agree on one thing more strongly than on any feature
//  request: people abandon music apps that lose their libraries, and they
//  say so in one-star reviews for years afterwards. "поменяла телефон и
//  переустановила приложение заново — вся музыка пропала!" is a review of a
//  competitor, not of a bug report — the app worked exactly as designed, and
//  the design had no way to move.
//
//  Sonava's state is small and entirely user-authored: playlists they made,
//  favourites they marked, servers they connected, the equalizer curve they
//  dialled in, what they have listened to. None of it is recoverable from
//  anywhere else. A single JSON file the listener owns turns "I got a new
//  phone" from a catastrophe into a file transfer.
//
//  ## What travels and what cannot
//
//  Audio files do not: they are the listener's own imports, they can be
//  hundreds of gigabytes, and iOS already moves an app's Documents through
//  its own device-to-device transfer. What travels is *the structure* — and
//  the manifest names the missing files so the destination can tell the
//  listener exactly which imports to bring across rather than silently
//  showing an empty library.
//
//  Server passwords do not travel either: they live in the Keychain, and
//  putting them in a file the listener might email themselves would repeat
//  the mistake `PlaylistSharing` was just fixed for. The connection details
//  travel; the destination asks for the password once.
//

import Foundation

struct LibraryBackup: Codable, Sendable {

    /// Bumped when the shape changes in a way older builds can't read.
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let appVersion: String

    var playlists: [UserPlaylist]
    var favorites: [Song]
    var recents: [Song]
    /// Imported files, by name — so the destination can say which are missing
    /// rather than pretending the library is empty.
    var localFiles: [Song]
    /// Connections without their passwords, which stay in the Keychain.
    var servers: [ServerConnection]
    var equalizer: EqualizerSettings
    /// Downloads are re-downloadable by definition; only the intent travels.
    var downloadedIDs: [String]

    // MARK: - Build

    @MainActor
    static func snapshot(library: MusicLibrary,
                         playlists: PlaylistStore,
                         servers: ServerStore,
                         effects: AudioEffects,
                         downloads: DownloadStore) -> LibraryBackup {
        LibraryBackup(
            version: currentVersion,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            playlists: playlists.playlists,
            favorites: library.favorites,
            recents: Array(library.recents.prefix(100)),
            localFiles: library.songs.filter { $0.source == .local },
            servers: servers.servers,
            equalizer: effects.equalizer,
            downloadedIDs: downloads.downloadedIDs
        )
    }

    /// What a restore actually did, so the UI can report it honestly instead
    /// of claiming a clean import over a partial one.
    struct Outcome: Equatable, Sendable {
        var playlistsAdded = 0
        var favoritesAdded = 0
        var serversAdded = 0
        /// Files the backup knew about that aren't on this device — the list
        /// the listener needs in order to finish the move.
        var missingFiles: [String] = []
        var restoredEqualizer = false

        var isEmpty: Bool {
            playlistsAdded == 0 && favoritesAdded == 0 && serversAdded == 0
                && !restoredEqualizer
        }
    }

    // MARK: - Apply

    /// Merges a backup into this device. Merging, never replacing: a restore
    /// onto a phone that already has playlists must not delete them, because
    /// the listener who taps "restore" by mistake would otherwise lose the
    /// very thing this file exists to protect.
    @MainActor
    func restore(library: MusicLibrary,
                 playlists playlistStore: PlaylistStore,
                 servers serverStore: ServerStore,
                 effects: AudioEffects) -> Outcome {
        var outcome = Outcome()

        let existingPlaylists = Set(playlistStore.playlists.map { $0.name.lowercased() })
        for playlist in playlists where !existingPlaylists.contains(playlist.name.lowercased()) {
            playlistStore.importShared(playlist)
            outcome.playlistsAdded += 1
        }

        let known = Set(library.favorites.map(\.id))
        for song in favorites where !known.contains(song.id) {
            library.toggleFavorite(song)
            outcome.favoritesAdded += 1
        }

        let existingHosts = Set(serverStore.servers.compactMap { $0.url?.absoluteString })
        for server in servers where !existingHosts.contains(server.urlString) {
            serverStore.addRestored(server)
            outcome.serversAdded += 1
        }

        effects.replace(equalizer)
        outcome.restoredEqualizer = true

        // Which imported files this phone doesn't have. Names, because that is
        // what the listener will look for in their own file browser.
        let present = Set(library.songs.compactMap(\.fileName))
        outcome.missingFiles = localFiles
            .compactMap(\.fileName)
            .filter { !present.contains($0) }
            .sorted()

        return outcome
    }

    // MARK: - File

    static let fileExtension = "sonavabackup"

    /// Writes the backup to a file the listener can move anywhere. Returns the
    /// URL, or nil if it could not be written — reported through
    /// `StorageDiagnostics` like every other write in the app.
    func writeToFile() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sonava-\(stamp).\(Self.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            StorageDiagnostics.report(filename: url.lastPathComponent,
                                      message: (error as NSError).localizedDescription)
            return nil
        }
    }

    /// Reads a backup the listener picked, or nil if it isn't one of ours.
    static func read(from url: URL) -> LibraryBackup? {
        // A file coming from Files.app or iCloud is security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LibraryBackup.self, from: data) else { return nil }
        // A file from a future version may be missing fields we depend on;
        // refusing beats a half-restore that looks like success.
        guard backup.version <= currentVersion else { return nil }
        return backup
    }
}
