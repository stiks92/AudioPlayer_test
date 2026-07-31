//
//  AlbumView.swift
//  Sonava
//
//  One record, held the way a person holds it: sleeve first, then the back of
//  the jacket — a numbered side listing in the label's own voices. The sleeve
//  bleeds to the trim like the player's does; it is the second and last object
//  in the app allowed to touch the screen edge.
//

import SwiftUI

struct AlbumView: View {
    let album: Album

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sleeve
                    jacket
                        .padding(.horizontal, Space.screenMargin)
                }
                .padding(.bottom, 140)
            }
            .ignoresSafeArea(edges: .top)
        }
        .foregroundColor(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// The cover, edge to edge, square.
    private var sleeve: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = album.artwork {
                ArtworkImage(song: cover, glyphSize: 72)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            // The title sits on the sleeve the way it does on a printed
            // jacket — over a scrim deep enough that any artwork carries it.
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.sonavaTitle)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.sonavaAttribution)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(Space.screenMargin)
        }
    }

    /// The back of the jacket: one action, then the side listing.
    private var jacket: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    if let first = album.songs.first {
                        audio.play(first, in: album.songs)
                        Haptics.impact(.medium)
                    }
                } label: {
                    HStack(spacing: Space.s) {
                        SonavaIcon(glyph: .play, size: 14, tint: Theme.background)
                        Text("Play the record")
                    }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .frame(maxWidth: 220)
            }
            .padding(.top, Space.l)

            Department(title: "Side listing",
                       fact: "\(album.trackCount) \(String(localized: "TRACKS"))")
                .padding(.top, Space.m)

            ForEach(Array(album.songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    audio.play(song, in: album.songs)
                } label: {
                    HStack(alignment: .center, spacing: Space.m) {
                        Text(String(format: "%02d", index + 1))
                            .font(.sonavaOrdinal)
                            .foregroundColor(currentID == song.id
                                             ? Theme.accentSoft : Theme.textTertiary)
                            .frame(width: Rail.ordinal, alignment: .trailing)
                        Text(song.title)
                            .font(.sonavaName)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        if currentID == song.id {
                            // The one playing gets the app's own mark, small,
                            // in the accent — a needle on the groove.
                            SonavaIcon(glyph: .stats, size: 13, tint: Theme.accentSoft)
                        } else {
                            Text(song.fileExtension.uppercased())
                                .font(.sonavaStamp)
                                .tracking(1.2)
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .frame(minHeight: Space.hitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < album.songs.count - 1 { RowRule(inset: Rail.text) }
            }
        }
    }

    private var currentID: String? { audio.currentSong?.id }
}
