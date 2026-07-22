//
//  UserPlaylistDetailView.swift
//  Sonava
//
//  Detail for a user-created playlist: play, shuffle, reorder-free editing,
//  rename and delete. Reads live from the store via id so edits reflect
//  immediately.
//

import SwiftUI

struct UserPlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss

    @State private var showRename = false
    @State private var renameText = ""

    private var playlist: UserPlaylist? { playlistStore.playlist(playlistID) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let playlist {
                ScrollView {
                    VStack(spacing: 20) {
                        hero(playlist)
                        if playlist.tracks.isEmpty {
                            emptyState
                        } else {
                            actions(playlist)
                            trackList(playlist)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .foregroundColor(.white)
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        renameText = playlist?.name ?? ""
                        showRename = true
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        playlistStore.delete(playlistID)
                        dismiss()
                    } label: { Label("Delete playlist", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundColor(.white)
                }
            }
        }
        .alert("Rename playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") { playlistStore.rename(playlistID, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func hero(_ playlist: UserPlaylist) -> some View {
        ZStack {
            LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note.list")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(height: 220)
        .overlay(LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom))
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.system(.title, design: .rounded).weight(.heavy)).lineLimit(2)
                Text(playlist.subtitle).font(.subheadline).foregroundColor(Theme.textSecondary)
            }
            .padding(20)
        }
    }

    private func actions(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 16) {
            Button {
                if let first = playlist.tracks.first {
                    if audio.isShuffling { audio.toggleShuffle() }
                    audio.play(first, in: playlist.tracks)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline).foregroundColor(Theme.background)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))

            Button {
                guard let random = playlist.tracks.randomElement() else { return }
                if !audio.isShuffling { audio.toggleShuffle() }
                audio.play(random, in: playlist.tracks)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .glass(cornerRadius: 30)
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
        }
        .padding(.horizontal, 20)
    }

    private func trackList(_ playlist: UserPlaylist) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(playlist.tracks) { song in
                Button {
                    audio.play(song, in: playlist.tracks)
                } label: {
                    SongRow(song: song, showBadge: true)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        playlistStore.removeTrack(song, from: playlistID)
                    } label: { Label("Remove from playlist", systemImage: "minus.circle") }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 46)).foregroundColor(Theme.textTertiary)
            Text("This playlist is empty")
                .font(.headline).foregroundColor(Theme.textSecondary)
            Text("Add tracks from the player or any track's menu.")
                .font(.subheadline).foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 30)
    }
}
