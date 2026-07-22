//
//  SongRow.swift
//  Sonava
//
//  A reusable list row for a single track.
//

import SwiftUI

/// Small rounded artwork with the track's gradient as a fallback glow.
struct ArtworkThumbnail: View {
    let song: Song
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12
    var showBadge: Bool = false

    var body: some View {
        ArtworkImage(song: song, glyphSize: size * 0.34)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                if showBadge {
                    SourceBadge(source: song.source).padding(4)
                }
            }
            .shadow(color: song.gradient.first?.opacity(0.4) ?? .clear, radius: 8, y: 4)
    }
}

struct SongRow: View {
    let song: Song
    var index: Int? = nil
    var showBadge: Bool = false

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    private var isCurrent: Bool { audio.currentSong == song }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkThumbnail(song: song, showBadge: showBadge)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(isCurrent ? Theme.accentSoft : Theme.textPrimary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                NowPlayingBars(isAnimating: audio.isPlaying)
            } else if library.isFavorite(song) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.destructive)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                audio.playNext(song)
            } label: { Label("Play Next", systemImage: "text.insert") }
            Button {
                audio.addToQueue(song)
            } label: { Label("Add to Queue", systemImage: "text.append") }
            Button {
                let seed = song
                Task {
                    let queue = await StationService.station(for: seed)
                    audio.play(seed, in: queue)
                }
            } label: { Label("Start Station", systemImage: "dot.radiowaves.left.and.right") }
            Divider()
            Button {
                library.toggleFavorite(song)
            } label: {
                Label(library.isFavorite(song) ? "Remove from Favorites" : "Favorite",
                      systemImage: library.isFavorite(song) ? "heart.slash" : "heart")
            }
        }
    }
}
