//
//  Playlist.swift
//  Sonava
//
//  A curated collection of songs.
//

import SwiftUI

struct Playlist: Identifiable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String
    var systemImage: String
    var gradient: [Color]
    var songIDs: [String]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        systemImage: String,
        gradient: [Color],
        songIDs: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.gradient = gradient
        self.songIDs = songIDs
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
}
