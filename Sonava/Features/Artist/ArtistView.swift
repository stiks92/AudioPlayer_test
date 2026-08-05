//
//  ArtistView.swift
//  Sonava
//
//  "More from this artist" — pulls the artist's music across sources into
//  one screen. Adds depth and a reason to keep exploring.
//

import SwiftUI

struct ArtistView: View {
    let artistName: String
    let gradient: [Color]

    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var feed = SongFeed()

    /// The colours the header glows with: taken from the artist's own top
    /// sleeve once it has loaded, so the screen is lit by their record rather
    /// than by a palette we assigned them.
    @State private var sleeve: [Color] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                // The same ground every other screen stands on: the record's
                // colour at the top, dissolving into black.
                LinearGradient(stops: [
                    .init(color: (sleeve.first ?? gradient.first ?? Theme.accent).opacity(0.5), location: 0),
                    .init(color: .black, location: 0.55)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(Motion.fade, value: sleeve)
                ScrollView {
                    VStack(spacing: Space.screenMargin) {
                        header
                        content
                    }
                    .padding(.bottom, 120)
                }
            }
            .foregroundColor(.white)
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .task {
                if feed.state == .idle {
                    await feed.load { await Self.tracks(for: artistName) }
                }
                // Light the screen from their own record.
                if let cover = feed.songs.first(where: { $0.artworkURL != nil })?.artworkURL,
                   let hex = await ArtworkPalette.load(from: cover) {
                    sleeve = hex.colors
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: Space.l) {
            // Their records, not a coloured circle with their initial in it.
            //
            // The old header drew a gradient disc and set the first letter of
            // the name at 60pt inside it — a procedural avatar, which is the
            // one thing this app is not allowed to put on screen. An artist's
            // picture is their sleeves, and by the time this header renders we
            // have three of them.
            sleeveStack

            Text(artistName)
                .font(.system(.title2).weight(.regular))
                .multilineTextAlignment(.center)

            if feed.state == .loaded, let first = feed.songs.first {
                HStack(spacing: Space.l) {
                    Button {
                        if audio.isShuffling { audio.toggleShuffle() }
                        audio.play(first, in: feed.songs)
                    } label: {
                        HStack(spacing: Space.s) {
                            SonavaIcon(glyph: .play, size: 15, tint: Theme.background)
                            Text("Play")
                        }
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle())

                    Button {
                        if !audio.isShuffling { audio.toggleShuffle() }
                        audio.play(feed.songs.randomElement() ?? first, in: feed.songs)
                    } label: {
                        HStack(spacing: Space.s) {
                            SonavaIcon(glyph: .shuffle, size: 15, tint: Theme.accentSoft)
                            Text("Shuffle")
                        }
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                }
                .padding(.horizontal, Space.screenMargin)
            }
        }
        .padding(.top, Space.m)
    }

    /// Three sleeves fanned like records half-pulled from a shelf. Falls back
    /// to whatever exists: two covers, one, or — before anything has loaded —
    /// nothing at all, which is honest and briefly empty rather than a
    /// placeholder pretending to be a portrait.
    private var sleeveStack: some View {
        let covers = feed.songs.filter { $0.artworkURL != nil }.prefix(3)
        return ZStack {
            ForEach(Array(covers.enumerated()), id: \.element.id) { index, song in
                let offset = CGFloat(index - (covers.count - 1) / 2)
                ArtworkImage(song: song, glyphSize: 28)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                    .rotationEffect(.degrees(Double(offset) * 7))
                    .offset(x: offset * 46)
                    .zIndex(offset == 0 ? 1 : 0)
            }
        }
        .frame(height: 150)
        .animation(Motion.expressive, value: covers.count)
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            AnimatedIcon(glyph: .loading, mode: .loop(true), size: 22, tint: Theme.accentSoft)
                .padding(.top, 40)
        case .failed:
            Text("Couldn't reach Audius. Check your connection.")
                .font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .empty:
            Text("No results").font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .loaded:
            LazyVStack(spacing: 2) {
                ForEach(feed.songs) { song in
                    Button { audio.play(song, in: feed.songs) } label: {
                        SongRow(song: song, showBadge: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.screenMargin)
        }
    }

    /// Merge the artist's music across sources (full tracks first).
    static func tracks(for artist: String) async -> [Song] {
        async let audius = AudiusService.shared.search(artist)
        async let deezer = DeezerService.shared.search(artist)
        async let apple = iTunesService.shared.searchMusic(artist)

        var seen = Set<String>()
        var result: [Song] = []
        let groups = [((try? await audius) ?? []),
                      ((try? await deezer) ?? []),
                      ((try? await apple) ?? [])]
        for group in groups {
            for song in group where !seen.contains(song.id) {
                seen.insert(song.id)
                result.append(song)
            }
        }
        return result
    }
}
