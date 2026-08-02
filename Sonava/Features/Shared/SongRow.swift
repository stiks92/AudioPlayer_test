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
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                if showBadge {
                    SourceBadge(source: song.source).padding(Space.s)
                }
            }
    }
}

struct SongRow: View {
    let song: Song
    var index: Int? = nil
    var showBadge: Bool = false

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var proStore: ProStore

    private var isCurrent: Bool { audio.currentSong == song }
    private var downloadState: DownloadStore.DownloadState { audio.downloads.state(for: song) }

    var body: some View {
        HStack(spacing: Space.l) {
            ArtworkThumbnail(song: song, showBadge: showBadge)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundColor(isCurrent ? Theme.accentSoft : Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Space.s) {
                    // `Theme.live` was defined and used nowhere, so a station
                    // row looked exactly like a file in the library — nothing
                    // on the Radio tab said "this is a live stream".
                    if song.isLive { LiveDot() }
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            downloadIndicator

            if isCurrent {
                // A living pulse from the animation pack, not drawn bars —
                // and it genuinely stills when playback pauses.
                AnimatedIcon(glyph: .activity, mode: .loop(audio.isPlaying),
                             size: 20, tint: Theme.accentSoft)
            } else if library.isFavorite(song) {
                SonavaIcon(glyph: .heart, size: 14, tint: Theme.destructive)
            }

            // The anchor's right column: the track's length, quiet and
            // tabular. Absent when unknown rather than invented.
            if !isCurrent, let duration = song.durationText {
                Text(duration)
                    .font(.system(.footnote).monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
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
            downloadButton
        }
    }

    // MARK: - Offline downloads (Pro)

    @ViewBuilder
    private var downloadButton: some View {
        if song.isDownloadable {
            switch downloadState {
            case .downloaded:
                Button(role: .destructive) {
                    audio.downloads.remove(song)
                } label: { Label("Remove download", systemImage: "trash") }
            case .downloading:
                Button {} label: { Label("Downloading…", systemImage: "arrow.down.circle") }
                    .disabled(true)
            case .none, .failed:
                Button {
                    if proStore.isPro {
                        audio.downloads.download(song)
                    } else {
                        proStore.presentPaywall()
                    }
                } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
        }
    }

    @ViewBuilder
    private var downloadIndicator: some View {
        switch downloadState {
        case .downloaded:
            SonavaIcon(glyph: .download, size: 13, tint: Theme.positive)
        case .downloading:
            // The pack's arrow-into-tray, looping while the bytes move.
            AnimatedIcon(glyph: .download, mode: .loop(true),
                         size: 16, tint: Theme.accentSoft)
        case .none, .failed:
            EmptyView()
        }
    }
}

// MARK: - Live indicator

/// A slow pulse on a live stream. Reduce Motion gets a steady dot rather than
/// nothing: the state still has to be legible, it just stops moving.
private struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 7, height: 7)
            .opacity(pulsing ? 0.35 : 1)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { if !reduceMotion { pulsing = true } }
            .accessibilityLabel(Text("Live"))
    }
}
