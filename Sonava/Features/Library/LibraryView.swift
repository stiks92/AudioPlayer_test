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
        case albums, playlists, songs, downloads, favorites

        var title: LocalizedStringKey {
            switch self {
            case .albums: return "Albums"
            case .playlists: return "Playlists"
            case .songs: return "Songs"
            case .downloads: return "Offline"
            case .favorites: return "Favorites"
            }
        }
    }

    // Albums lead. The app had no album at all until this release — nothing
    // ever grouped `Song.album` — and for somebody who ripped their collection,
    // the record is the unit of memory, not the track.
    @State private var tab: Tab = .albums
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showImporter = false
    @State private var importError: String?
    @Namespace private var seg
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.screenMargin) {
                        Text("Your Library")
                            .font(.sonavaMasthead)
                            .foregroundColor(Theme.textPrimary)

                        segmentedControl

                        switch tab {
                        case .albums:    albumsSection
                        case .playlists: playlistsSection
                        case .songs:     songsSection
                        case .downloads: downloadsSection
                        case .favorites: favoritesSection
                        }
                    }
                    .padding(.horizontal, Space.screenMargin)
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
        SegmentedControl(
            segments: Tab.allCases.map {
                .init(value: $0, title: $0.title,
                      identifier: "\(AccessibilityID.librarySegment).\($0.rawValue)")
            },
            selection: $tab
        )
    }

    @ViewBuilder
    private var playlistsSection: some View {
        // Playlists is the landing tab, so a first-run user meets this screen
        // before any other. It was the one tab of four with no zero state:
        // a single "New Playlist" row and then half a screen of black.
        if playlistStore.playlists.isEmpty {
            emptyPlaylists
        } else {
            playlistRows
        }
    }

    private var emptyPlaylists: some View {
        VStack(spacing: Space.l) {
            SonavaIcon(glyph: .library, size: 52, tint: Theme.textTertiary)
            Text("No playlists yet")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text("Group tracks from any source into a playlist — your files, your server, radio, anything you’ve found.")
                .font(.subheadline)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
            Button {
                Haptics.impact()
                showNewPlaylist = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.xl)
                    // Height rather than vertical padding: at `Space.m` this
                    // measured 42pt, under Apple's 44 minimum, on the one
                    // control an empty Library offers.
                    .frame(minHeight: Space.hitTarget)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
        }
        .frame(maxWidth: .infinity)
        .centredEmptyState()
    }

    private var playlistRows: some View {
        LazyVStack(spacing: Space.m) {
            Button {
                showNewPlaylist = true
            } label: {
                HStack(spacing: Space.l) {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "plus").font(.system(.title2).weight(.semibold)).foregroundColor(Theme.accentSoft))
                    Text("New Playlist")
                        .font(.system(.callout).weight(.semibold))
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
                    HStack(spacing: Space.l) {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                            .overlay(SonavaIcon(glyph: .library, size: 24))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.system(.callout).weight(.semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text(playlist.subtitle)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote).weight(.semibold))
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
                            // Deleting the file out from under the player would
                            // leave the mini player advertising a track that no
                            // longer exists.
                            if audio.currentSong == song { audio.stop() }
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
            HStack(spacing: Space.l) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(.body).weight(.semibold))
                            .foregroundColor(Theme.accentSoft)
                    )
                Text("Import from Files")
                    .font(.system(.callout).weight(.semibold))
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
        VStack(spacing: Space.l) {
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
                .padding(.horizontal, Space.xl)
            Button {
                Haptics.impact()
                showImporter = true
            } label: {
                Text("Import from Files")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.m)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            .accessibilityIdentifier(AccessibilityID.importButton)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .centredEmptyState()
    }

    @ViewBuilder
    private var downloadsSection: some View {
        let downloads = audio.downloads.downloads
        if downloads.isEmpty {
            VStack(spacing: Space.m) {
                SonavaIcon(glyph: .download, size: 46)
                    .font(.system(size: 46))
                    .foregroundColor(Theme.textTertiary)
                Text("Nothing downloaded yet")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)
                Text("Download full tracks from Audius or your server to play them offline. Look for the download action on any track.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }
            .frame(maxWidth: .infinity)
            .centredEmptyState()
        } else {
            LazyVStack(spacing: 2) {
                ForEach(downloads) { song in
                    Button {
                        audio.play(song, in: downloads)
                    } label: {
                        SongRow(song: song, showBadge: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if library.favoriteSongs.isEmpty {
            VStack(spacing: Space.m) {
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
            .centredEmptyState()
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

// MARK: - Albums (the record wall)

extension LibraryView {
    /// A wall of sleeves, two across, edge to edge of the content column.
    ///
    /// The unit is the record. Tapping one plays it from the top in its own
    /// order, which is the single thing a person who owns albums does most and
    /// the app could not do at all before `Album.group` existed.
    @ViewBuilder
    var albumsSection: some View {
        let albums = library.albums
        if albums.isEmpty {
            emptyAlbums
        } else {
            let columns = [GridItem(.flexible(), spacing: Space.m),
                           GridItem(.flexible(), spacing: Space.m)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                ForEach(albums) { album in
                    NavigationLink {
                        // The record opens out of its own sleeve — the system
                        // zoom morph, which is the Wolt move done natively:
                        // the tile is the source, the screen grows from it and
                        // shrinks back into it on the way out.
                        AlbumView(album: album)
                            .navigationTransition(.zoom(sourceID: album.id, in: zoom))
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            ZStack {
                                if let cover = album.artwork {
                                    ArtworkImage(song: cover, glyphSize: 34)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            Text(album.title)
                                .font(.sonavaName)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text("\(album.artist) · \(album.trackCount)")
                                .font(.sonavaStamp)
                                .tracking(0.8)
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: album.id, in: zoom)
                }
            }
        }
    }

    /// The empty wall states what fills it, in the same voice as the rest of
    /// the app — not a centred glyph with a pill button.
    var emptyAlbums: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "No records yet")
            Text("Import files with album tags, or connect your server — anything with a real album title and one artist becomes a record here.")
                .font(.sonavaByline)
                .foregroundColor(Theme.textSecondary)
            Button {
                showImporter = true
            } label: {
                Text("Import music")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .padding(.top, Space.s)
        }
    }
}
