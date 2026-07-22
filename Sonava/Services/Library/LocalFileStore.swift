//
//  LocalFileStore.swift
//  Sonava
//
//  The user's own audio files. Sonava ships no bundled catalogue — the
//  "local" source is whatever the listener imports from Files or iCloud
//  Drive.
//
//  Imported files are copied into the app's Documents/Media directory rather
//  than referenced in place. Security-scoped bookmarks would avoid the copy,
//  but they break the moment the original is moved, renamed or evicted from
//  iCloud — unacceptable for a library that must play offline years later.
//  Documents is also the folder iTunes/Finder file sharing exposes, so users
//  can manage the same files from a computer.
//

import Foundation
import AVFoundation
import CryptoKit
import UIKit

@MainActor
final class LocalFileStore: ObservableObject {

    @Published private(set) var songs: [Song] = []

    private let index = JSONFileStore<[Song]>("local-library.json", default: [])

    /// Where imported audio lives. Resolved from the file system only, so any
    /// context can ask — `Song.url` needs it off the main actor.
    nonisolated static var mediaDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let media = documents.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }

    init() {
        // Drop entries whose file vanished — a user can delete them through
        // Files behind our back, and a track that cannot play is worse than
        // one that is missing.
        songs = index.read().filter { song in
            guard let name = song.fileName else { return false }
            return FileManager.default.fileExists(atPath: Self.mediaDirectory.appendingPathComponent(name).path)
        }
        index.write(songs)
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return String(localized: "Couldn't read \(name).")
            }
        }
    }

    /// Copies the picked files in and reads their embedded metadata.
    /// Returns the songs that were added; already-imported files are skipped.
    @discardableResult
    func importFiles(at urls: [URL]) async -> [Song] {
        var added: [Song] = []

        for source in urls {
            // Files hands back a security-scoped URL; we only need it long
            // enough to hash and copy the bytes out.
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            // Identity is the file's content, not its name. Names are a poor
            // key in both directions: the same track can arrive twice under
            // different names, and two genuinely different recordings are
            // often both called "track01.mp3".
            guard let fingerprint = fingerprint(of: source) else { continue }
            let id = "local:\(fingerprint)"
            guard !songs.contains(where: { $0.id == id }),
                  !added.contains(where: { $0.id == id }),
                  let destination = copyIn(source)
            else { continue }

            added.append(await makeSong(for: destination, id: id))
        }

        guard !added.isEmpty else { return [] }
        songs.insert(contentsOf: added, at: 0)
        index.write(songs)
        return added
    }

    /// SHA-256 of the file, streamed so a long album rip never loads whole.
    private func fingerprint(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copies into Media, disambiguating names so two "track01.mp3" can coexist.
    private func copyIn(_ source: URL) -> URL? {
        let manager = FileManager.default
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension

        var candidate = Self.mediaDirectory.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = Self.mediaDirectory.appendingPathComponent("\(base) \(suffix).\(ext)")
            suffix += 1
        }

        do {
            try manager.copyItem(at: source, to: candidate)
            return candidate
        } catch {
            return nil
        }
    }

    // MARK: - Metadata

    private func makeSong(for url: URL, id: String) async -> Song {
        let asset = AVURLAsset(url: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        var title: String?
        var artist: String?
        var album: String?
        var artworkURL: URL?

        if let metadata = try? await asset.load(.commonMetadata) {
            title = await stringValue(metadata, key: .commonKeyTitle)
            artist = await stringValue(metadata, key: .commonKeyArtist)
            album = await stringValue(metadata, key: .commonKeyAlbumName)
            artworkURL = await extractArtwork(metadata, for: url)
        }

        let fileName = url.lastPathComponent
        return Song(
            id: id,
            title: title ?? fallbackTitle,
            artist: artist ?? String(localized: "Unknown artist"),
            album: album ?? String(localized: "My files"),
            source: .local,
            fileName: fileName,
            fileExtension: url.pathExtension,
            artworkURL: artworkURL,
            gradientHex: Palette.hex(forSeed: fileName)
        )
    }

    private func stringValue(_ items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.stringValue),
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return value
    }

    /// Embedded cover art is written next to the track so `AsyncImage` can load
    /// it by URL like any remote artwork, keeping `Song` free of image blobs.
    private func extractArtwork(_ items: [AVMetadataItem], for track: URL) async -> URL? {
        guard let item = items.first(where: { $0.commonKey == .commonKeyArtwork }),
              let data = try? await item.load(.dataValue),
              UIImage(data: data) != nil
        else { return nil }

        let destination = track.deletingPathExtension().appendingPathExtension("cover.jpg")
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: - Removal

    func remove(_ song: Song) {
        guard let name = song.fileName else { return }
        let file = Self.mediaDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)
        if let cover = song.artworkURL, cover.isFileURL {
            try? FileManager.default.removeItem(at: cover)
        }
        songs.removeAll { $0.id == song.id }
        index.write(songs)
    }
}
