//
//  Shuffle.swift
//  Sonava
//
//  Shuffle that sounds shuffled.
//
//  `Array.shuffled()` is a correct Fisher-Yates permutation and it is what
//  every player in the review corpus is complaining about: "рандомайзер по
//  сути не работает, скачет по одним и тем же" appears in fourteen RU
//  reviews and five US ones. Both things are true — uniform randomness
//  clusters, and a listener who hears the same four songs across two
//  sessions has no way to know a fair coin did it.
//
//  So this is a *deliberately unfair* shuffle, in the direction people mean
//  when they say the word: tracks heard recently sink toward the back. The
//  order is still random; what changes is which random order you get. Apple
//  Music, Spotify and Poweramp all do a version of this, and Marvis collects
//  explicit praise for it.
//
//  Pure and static so it can be tested without a player: given the same
//  inputs and generator, it returns the same order.
//

import Foundation

enum Shuffle {

    /// How far back "recently heard" reaches. Twenty-five is roughly an
    /// evening's listening — long enough that a repeat feels wrong, short
    /// enough that a 40-track library doesn't collapse into a fixed order.
    static let memory = 25

    /// Shuffles `songs`, sinking anything in `recent` toward the end.
    ///
    /// Both halves are independently shuffled, so a listener who has heard
    /// *everything* still gets a fresh order rather than the same demoted
    /// sequence every time — the failure mode a naive "sort by last played"
    /// would introduce.
    static func ordered(_ songs: [Song], recent: [Song],
                        using generator: inout some RandomNumberGenerator) -> [Song] {
        let heard = Set(recent.prefix(memory).map(\.id))
        guard !heard.isEmpty else { return songs.shuffled(using: &generator) }

        var fresh: [Song] = []
        var stale: [Song] = []
        for song in songs {
            if heard.contains(song.id) { stale.append(song) } else { fresh.append(song) }
        }
        return fresh.shuffled(using: &generator) + stale.shuffled(using: &generator)
    }

    /// The everyday entry point, using the system generator.
    static func ordered(_ songs: [Song], recent: [Song]) -> [Song] {
        var generator = SystemRandomNumberGenerator()
        return ordered(songs, recent: recent, using: &generator)
    }
}
