//
//  LibraryView.swift
//  Sonava
//
//  The user's library: playlists, all songs, and favourites, behind a
//  custom animated segmented control.
//

import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showImporter = false
    @State private var importError: String?
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
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await library.importFiles(at: urls) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
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

        }
    }

    @ViewBuilder
    private var songsSection: some View {
        if library.songs.isEmpty {
            emptyLibrary
        } else {
            LazyVStack(spacing: 2) {
                importButton
                ForEach(library.songs) { song in
                    Button {
                        audio.play(song, in: library.songs)
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            library.remove(song)
                        } label: {
                            Label("Remove from library", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var importButton: some View {
        Button {
            Haptics.impact()
            showImporter = true
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.accentSoft)
                    )
                Text("Import from Files")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.importButton)
    }

    /// Sonava bundles no music of its own, so an empty Songs tab is the normal
    /// first-run state — it has to explain itself and offer the way forward.
    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 46))
                .foregroundColor(Theme.textTertiary)
            Text("No files yet")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text("Import your own audio from Files or iCloud Drive. It stays on your device and plays offline.")
                .font(.subheadline)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                Haptics.impact()
                showImporter = true
            } label: {
                Text("Import from Files")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            .accessibilityIdentifier(AccessibilityID.importButton)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
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
