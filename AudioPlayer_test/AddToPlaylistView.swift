//
//  AddToPlaylistView.swift
//  AudioPlayer_test
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
                    VStack(alignment: .leading, spacing: 18) {
                        trackHeader
                        createRow
                        if !playlistStore.playlists.isEmpty {
                            Text("YOUR PLAYLISTS")
                                .font(.system(size: 11, weight: .bold)).tracking(1)
                                .foregroundColor(Theme.textTertiary)
                            VStack(spacing: 8) {
                                ForEach(playlistStore.playlists) { playlist in
                                    playlistRow(playlist)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var trackHeader: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(song: song, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(song.artist).font(.caption).foregroundColor(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var createRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundColor(Theme.accentSoft)
            TextField("New playlist name", text: $newName)
                .foregroundColor(.white)
                .submitLabel(.done)
                .onSubmit(createAndAdd)
            Button("Create", action: createAndAdd)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textTertiary : Theme.accentSoft)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glass(cornerRadius: 14)
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
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "music.note.list").font(.system(size: 16)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(playlist.subtitle).font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundColor(added ? Color(hex: 0x38EF7D) : Theme.textSecondary)
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
