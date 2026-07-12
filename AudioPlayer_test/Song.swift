//
//  Song.swift
//  AudioPlayer_test
//
//  Core track model for the player.
//

import SwiftUI

/// A single playable track backed by a bundled audio file.
struct Song: Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let fileName: String
    let fileExtension: String
    let artworkName: String
    /// Two-stop gradient used to theme the artwork and the Now Playing scene.
    let gradient: [Color]

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        fileName: String,
        fileExtension: String = "mp3",
        artworkName: String = "Cover",
        gradient: [Color]
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.artworkName = artworkName
        self.gradient = gradient
    }

    /// Resolves the on-disk URL for the bundled resource.
    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    }

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
