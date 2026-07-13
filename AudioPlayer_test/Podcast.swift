//
//  Podcast.swift
//  AudioPlayer_test
//
//  A podcast show. Episodes are represented as universal `Song` values
//  (source `.podcast`) so they play through the same engine and UI.
//

import SwiftUI

struct Podcast: Identifiable, Equatable {
    let id: String          // feed URL string (stable)
    let title: String
    let author: String
    let artworkURL: URL?
    let feedURL: URL
    let gradientHex: [UInt]

    var gradient: [Color] { gradientHex.colors }

    init(title: String, author: String, artworkURL: URL?, feedURL: URL) {
        self.id = feedURL.absoluteString
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.feedURL = feedURL
        self.gradientHex = Palette.hex(forSeed: feedURL.absoluteString)
    }

    static func == (lhs: Podcast, rhs: Podcast) -> Bool { lhs.id == rhs.id }
}
