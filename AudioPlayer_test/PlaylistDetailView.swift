//
//  PlaylistDetailView.swift
//  AudioPlayer_test
//
//  A playlist header with a stretchy gradient hero and the track list.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    private var songs: [Song] { library.songs(in: playlist) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    hero
                    actions
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { _, song in
                            Button {
                                audio.play(song, in: songs)
                            } label: {
                                SongRow(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .foregroundColor(.white)
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        ZStack {
            LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: playlist.systemImage)
                .font(.system(size: 76, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 12)
        }
        .frame(height: 260)
        .overlay(
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
        )
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.title)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                Text(playlist.subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(20)
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button {
                if let first = songs.first {
                    if audio.isShuffling { audio.toggleShuffle() }
                    audio.play(first, in: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))

            Button {
                guard !songs.isEmpty else { return }
                if !audio.isShuffling { audio.toggleShuffle() }
                audio.play(songs.randomElement()!, in: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glass(cornerRadius: 30)
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
        }
        .padding(.horizontal, 20)
    }
}
