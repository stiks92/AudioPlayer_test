//
//  LibraryView.swift
//  Sonava
//
//  The user's library: playlists, all songs, and favourites, behind a
//  custom animated segmented control.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore

    enum Tab: String, CaseIterable {
        case playlists, songs, favorites

        var title: LocalizedStringKey {
            switch self {
            case .playlists: return "Playlists"
            case .songs: return "Songs"
            case .favorites: return "Favorites"
            }
        }
    }

    @State private var tab: Tab = .playlists
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @Namespace private var seg

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your Library")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundColor(Theme.textPrimary)

                        segmentedControl

                        switch tab {
                        case .playlists: playlistsSection
                        case .songs:     songsSection
                        case .favorites: favoritesSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .alert("New playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { playlistStore.create(name) }
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { item in
                let selected = tab == item
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selected ? Theme.background : Theme.textSecondary)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if selected {
                                Capsule()
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "seg", in: seg)
                            }
                        }
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { tab = item }
                    }
            }
        }
        .padding(5)
        .glass(cornerRadius: 30)
    }

    private var playlistsSection: some View {
        LazyVStack(spacing: 12) {
            Button {
                showNewPlaylist = true
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.accentSoft))
                    Text("New Playlist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            ForEach(playlistStore.playlists) { playlist in
                NavigationLink {
                    UserPlaylistDetailView(playlistID: playlist.id)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: "music.note.list").foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text(playlist.subtitle)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            ForEach(library.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: playlist.systemImage).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text(playlist.subtitle)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var songsSection: some View {
        LazyVStack(spacing: 2) {
            ForEach(library.songs) { song in
                Button {
                    audio.play(song, in: library.songs)
                } label: {
                    SongRow(song: song)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if library.favoriteSongs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 46))
                    .foregroundColor(Theme.textTertiary)
                Text("No favourites yet")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)
                Text("Tap the heart on any track to save it here.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(library.favoriteSongs) { song in
                    Button {
                        audio.play(song, in: library.favoriteSongs)
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
