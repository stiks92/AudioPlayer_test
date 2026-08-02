//
//  DownloadStore.swift
//  Sonava
//
//  Offline downloads — a Sonava Pro feature. Saves full-length, rights-clean
//  tracks (Audius CC, the user's own server) to disk so they play with no
//  network. 30-second previews and live radio are never downloadable.
//
//  Downloaded audio lives in Documents/Downloads and is resolved ahead of the
//  stream URL at playback, so a saved track also runs through the local
//  AVAudioEngine graph — and therefore gets the equalizer too.
//

import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {

    /// Progress/state per track id, so rows can show a spinner or a check.
    enum DownloadState: Equatable {
        case none
        case downloading(Double)   // 0...1
        case downloaded
        case failed
    }

    /// The saved tracks, newest first — the "Downloaded" library section.
    @Published private(set) var downloads: [Song] = []
    @Published private(set) var states: [String: DownloadState] = [:]

    private let index = JSONFileStore<[Song]>("downloads.json", default: [])
    private var tasks: [String: Task<Void, Never>] = [:]

    nonisolated static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        // Keep only entries whose file is still present.
        downloads = index.read().filter { song in
            FileManager.default.fileExists(atPath: Self.fileURL(for: song).path)
        }
        for song in downloads { states[song.id] = .downloaded }
        index.write(downloads)
    }

    // MARK: - Queries

    /// The ids the listener chose to keep offline. A backup carries these
    /// rather than the audio: the files are re-fetchable, the *choice* is not.
    var downloadedIDs: [String] { downloads.map(\.id) }

    func isDownloaded(_ song: Song) -> Bool {
        states[song.id] == .downloaded
    }

    func state(for song: Song) -> DownloadState {
        states[song.id] ?? .none
    }

    /// A local file URL for a saved track, or nil — playback prefers this over
    /// the stream so downloaded tracks work offline.
    func localURL(for song: Song) -> URL? {
        guard isDownloaded(song) else { return nil }
        let url = Self.fileURL(for: song)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download / remove

    /// Downloads a track. Silently ignores anything not downloadable or already
    /// saved. `isPro` gating happens at the call site.
    func download(_ song: Song) {
        guard song.isDownloadable, let source = song.streamURL else { return }
        guard state(for: song) == .none || state(for: song) == .failed else { return }

        states[song.id] = .downloading(0)
        tasks[song.id] = Task { await run(song, from: source) }
    }

    func remove(_ song: Song) {
        tasks[song.id]?.cancel()
        tasks[song.id] = nil
        try? FileManager.default.removeItem(at: Self.fileURL(for: song))
        downloads.removeAll { $0.id == song.id }
        states[song.id] = nil
        index.write(downloads)
    }

    func removeAll() {
        for song in downloads { remove(song) }
    }

    private func run(_ song: Song, from source: URL) async {
        let destination = Self.fileURL(for: song)
        do {
            let (temp, response) = try await URLSession.shared.download(from: source)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)

            // Persist the track pointed at its offline copy so it survives a
            // relaunch even if the streaming id later stops resolving.
            states[song.id] = .downloaded
            if !downloads.contains(where: { $0.id == song.id }) {
                downloads.insert(song, at: 0)
            }
            index.write(downloads)
            Haptics.success()
        } catch is CancellationError {
            states[song.id] = nil
        } catch {
            states[song.id] = .failed
        }
        tasks[song.id] = nil
    }

    // MARK: - Paths

    /// Deterministic filename from the track id, so it round-trips across
    /// launches. The id can contain "/" (e.g. a URL-ish id), so hash it.
    private nonisolated static func fileURL(for song: Song) -> URL {
        let safe = String(song.id.unicodeScalars.map { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0))) ? Character($0) : "_" })
        let ext = song.fileExtension.isEmpty ? "mp3" : song.fileExtension
        return directory.appendingPathComponent("\(safe).\(ext)")
    }
}
