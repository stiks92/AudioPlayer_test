//
//  ServerBrowseView.swift
//  Sonava
//
//  The listener's own server, browsable — a shelf of records rather than a
//  search box.
//
//  Until now a connected server could only be *searched*: type something and
//  get tracks. Somebody who ripped 36,000 files did not organise them so they
//  could type the name of a record they already own. Navidrome shipped its
//  five most-requested features in 2025 and clients have not caught up; the
//  browse tree is the part that was missing here.
//
//  Everything on this screen is fetched, so every state is real: loading says
//  loading, an unreachable server says so and offers a retry, and an empty
//  library says it is empty rather than showing a spinner forever.
//

import SwiftUI

struct ServerBrowseView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var audio: AudioManager

    enum Shelf: String, CaseIterable {
        case albums, artists, playlists

        var title: LocalizedStringKey {
            switch self {
            case .albums: return "Albums"
            case .artists: return "Artists"
            case .playlists: return "Playlists"
            }
        }

        var emptyMessage: LocalizedStringKey {
            switch self {
            case .albums: return "The server has no albums yet."
            case .artists: return "The server has no artists yet."
            case .playlists: return "The server has no playlists yet."
            }
        }
    }

    @State private var shelf: Shelf = .albums
    @State private var albums: [Album] = []
    @State private var artists: [ServerArtist] = []
    @State private var playlists: [ServerPlaylist] = []
    @State private var isLoading = false
    @State private var failed = false
    @Namespace private var zoom

    var body: some View {
        Group {
            if serverStore.service == nil {
                notConnected
            } else {
                content
            }
        }
        .task(id: shelf) { await load() }
    }

    // MARK: - States

    private var notConnected: some View {
        VStack(spacing: Space.l) {
            SonavaIcon(glyph: .server, size: 52, tint: Theme.textTertiary)
            Text("No server connected")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text("Connect a Jellyfin, Navidrome, Airsonic or Subsonic server in Settings and your whole library appears here.")
                .font(.subheadline)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
        }
        .frame(maxWidth: .infinity)
        .centredEmptyState()
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SegmentedControl(
                segments: Shelf.allCases.map {
                    .init(value: $0, title: $0.title, identifier: "server.shelf.\($0.rawValue)")
                },
                selection: $shelf)

            if isLoading && currentIsEmpty {
                loadingState
            } else if failed {
                failedState
            } else if currentIsEmpty {
                emptyState
            } else {
                switch shelf {
                case .albums: albumGrid
                case .artists: artistRows
                case .playlists: playlistRows
                }
            }
        }
    }

    private var currentIsEmpty: Bool {
        switch shelf {
        case .albums: return albums.isEmpty
        case .artists: return artists.isEmpty
        case .playlists: return playlists.isEmpty
        }
    }

    private var loadingState: some View {
        HStack(spacing: Space.m) {
            AnimatedIcon(glyph: .loading, mode: .loop(true), size: 20, tint: Theme.accentSoft)
            Text("Reading your library…")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var failedState: some View {
        VStack(spacing: Space.m) {
            SonavaIcon(glyph: .server, size: 42, tint: Theme.textTertiary)
            Text("Couldn't reach \(serverStore.host ?? "the server").")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load(force: true) } }
                .buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private var emptyState: some View {
        // A sentence per shelf rather than one with the shelf's name dropped
        // into it: `shelf.rawValue` is an English identifier, and
        // interpolating it would have shipped "the server reports no albums"
        // inside an otherwise Russian screen.
        Text(shelf.emptyMessage)
            .font(.subheadline)
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
    }

    // MARK: - Shelves

    private var albumGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                            GridItem(.flexible(), spacing: Space.m)],
                  alignment: .leading, spacing: Space.xl) {
            ForEach(albums) { album in
                NavigationLink {
                    ServerAlbumView(album: album)
                        .navigationTransition(.zoom(sourceID: album.id, in: zoom))
                } label: {
                    VStack(alignment: .leading, spacing: Space.s) {
                        RemoteSleeve(url: album.artworkURL)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        Text(album.title)
                            .font(.sonavaRowTitle)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Text(album.year.map { "\(album.artist) · \($0)" } ?? album.artist)
                            .font(.sonavaRowMeta)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: album.id, in: zoom)
            }
        }
    }

    private var artistRows: some View {
        LazyVStack(spacing: Space.m) {
            ForEach(artists) { artist in
                NavigationLink {
                    ServerArtistView(artist: artist)
                } label: {
                    HStack(spacing: Space.l) {
                        RemoteSleeve(url: artist.artworkURL)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name)
                                .font(.sonavaRowTitle)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text("\(artist.albumCount) albums")
                                .font(.sonavaRowMeta)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        SonavaIcon(glyph: .chevronRight, size: 13, tint: Theme.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var playlistRows: some View {
        LazyVStack(spacing: Space.m) {
            ForEach(playlists) { playlist in
                Button {
                    Task { await play(playlist) }
                } label: {
                    HStack(spacing: Space.l) {
                        RemoteSleeve(url: playlist.artworkURL)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.sonavaRowTitle)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text(playlist.subtitle)
                                .font(.sonavaRowMeta)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        SonavaIcon(glyph: .play, size: 15, tint: Theme.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Loading

    private func load(force: Bool = false) async {
        guard let service = serverStore.service else { return }
        if !force && !currentIsEmpty { return }
        isLoading = true
        failed = false
        defer { isLoading = false }

        do {
            switch shelf {
            case .albums:    albums = try await service.albums(type: "newest", count: 60)
            case .artists:   artists = try await service.artists()
            case .playlists: playlists = try await service.playlists()
            }
        } catch {
            failed = true
        }
    }

    private func play(_ playlist: ServerPlaylist) async {
        guard let service = serverStore.service,
              let tracks = try? await service.playlistTracks(id: playlist.id),
              let first = tracks.first else { return }
        audio.play(first, in: tracks)
    }
}

// MARK: - Server album

struct ServerAlbumView: View {
    let album: Album

    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var audio: AudioManager

    @State private var tracks: [Song] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    RemoteSleeve(url: album.artworkURL)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(.system(.title2).weight(.light))
                            .foregroundColor(Theme.textPrimary)
                        Text(album.year.map { "\(album.artist) · \($0)" } ?? album.artist)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }

                    if isLoading && tracks.isEmpty {
                        AnimatedIcon(glyph: .loading, mode: .loop(true), size: 20,
                                     tint: Theme.accentSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Space.xl)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(tracks) { track in
                                Button {
                                    audio.play(track, in: tracks)
                                } label: {
                                    SongRow(song: track)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, 140)
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            guard let service = serverStore.service, let id = album.serverID else {
                tracks = album.songs
                return
            }
            tracks = (try? await service.albumTracks(id: id)) ?? album.songs
        }
    }
}

// MARK: - Server artist

struct ServerArtistView: View {
    let artist: ServerArtist

    @EnvironmentObject private var serverStore: ServerStore
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @Namespace private var zoom

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                    GridItem(.flexible(), spacing: Space.m)],
                          alignment: .leading, spacing: Space.xl) {
                    ForEach(albums) { album in
                        NavigationLink {
                            ServerAlbumView(album: album)
                                .navigationTransition(.zoom(sourceID: album.id, in: zoom))
                        } label: {
                            VStack(alignment: .leading, spacing: Space.s) {
                                RemoteSleeve(url: album.artworkURL)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                Text(album.title)
                                    .font(.sonavaRowTitle)
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                if let year = album.year {
                                    Text(String(year))
                                        .font(.sonavaRowMeta)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: album.id, in: zoom)
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, 140)

                if isLoading && albums.isEmpty {
                    AnimatedIcon(glyph: .loading, mode: .loop(true), size: 20, tint: Theme.accentSoft)
                        .padding(.top, Space.xxl)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            guard let service = serverStore.service else { return }
            albums = (try? await service.artistAlbums(id: artist.id)) ?? []
        }
    }
}

// MARK: - Artwork

/// A server cover. Its own view because these URLs are authenticated and
/// arrive one per row — `AsyncImage` with a plain black fallback beats the
/// track-gradient placeholder here, which would imply a colour the record
/// does not have.
private struct RemoteSleeve: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
        .clipped()
    }
}
