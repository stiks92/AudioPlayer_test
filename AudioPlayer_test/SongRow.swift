//
//  SongRow.swift
//  AudioPlayer_test
//
//  A reusable list row for a single track.
//

import SwiftUI

/// Small rounded artwork with the track's gradient as a fallback glow.
struct ArtworkThumbnail: View {
    let song: Song
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    var body: some View {
        Image(song.artworkName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: song.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: song.gradient.first?.opacity(0.4) ?? .clear, radius: 8, y: 4)
    }
}

struct SongRow: View {
    let song: Song
    var index: Int? = nil

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    private var isCurrent: Bool { audio.currentSong == song }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkThumbnail(song: song)

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
                    .foregroundColor(Color(hex: 0xFF3B6B))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
