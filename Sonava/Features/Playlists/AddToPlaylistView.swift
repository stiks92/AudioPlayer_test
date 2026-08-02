//
//  AddToPlaylistView.swift
//  Sonava
//
//  Add any track (from any source) to one or more user playlists.
//

import SwiftUI

struct AddToPlaylistView: View {
    let song: Song

    @EnvironmentObject private var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        trackHeader
                        createRow
                        if !playlistStore.playlists.isEmpty {
                            Text("YOUR PLAYLISTS")
                                .font(.system(.caption2).weight(.bold)).tracking(1)
                                .foregroundColor(Theme.textTertiary)
                            VStack(spacing: 8) {
                                ForEach(playlistStore.playlists) { playlist in
                                    playlistRow(playlist)
                                }
                            }
                        }
                    }
                    .padding(Space.screenMargin)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
        }
        .preferredColorScheme(.dark)
    }

    private var trackHeader: some View {
        HStack(spacing: Space.m) {
            ArtworkThumbnail(song: song, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(.subheadline).weight(.semibold)).lineLimit(1)
                Text(song.artist).font(.caption).foregroundColor(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var createRow: some View {
        HStack(spacing: Space.m) {
            SonavaIcon(glyph: .plus, size: 20, tint: Theme.accentSoft)
            TextField("New playlist name", text: $newName)
                .foregroundColor(.white)
                .submitLabel(.done)
                .onSubmit(createAndAdd)
            Button("Create", action: createAndAdd)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textTertiary : Theme.accentSoft)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .card(cornerRadius: Radius.control)
    }

    private func playlistRow(_ playlist: UserPlaylist) -> some View {
        let added = playlistStore.contains(song, in: playlist.id)
        return Button {
            if added {
                playlistStore.removeTrack(song, from: playlist.id)
            } else {
                playlistStore.addTrack(song, to: playlist.id)
            }
        } label: {
            HStack(spacing: Space.l) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(SonavaIcon(glyph: .note, size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(.subheadline).weight(.semibold)).lineLimit(1)
                    Text(playlist.subtitle).font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer()
                ZStack {
                    if added {
                        AnimatedIcon(glyph: .checkmark, mode: .toggle(true),
                                     size: 22, tint: Theme.positive)
                    } else {
                        SonavaIcon(glyph: .plus, size: 20, tint: Theme.textSecondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let playlist = playlistStore.create(name)
        playlistStore.addTrack(song, to: playlist.id)
        newName = ""
    }
}
