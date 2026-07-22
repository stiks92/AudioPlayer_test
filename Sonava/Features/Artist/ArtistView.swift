//
//  ArtistView.swift
//  AudioPlayer_test
//
//  "More from this artist" — pulls the artist's music across sources into
//  one screen. Adds depth and a reason to keep exploring.
//

import SwiftUI

struct ArtistView: View {
    let artistName: String
    let gradient: [Color]

    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var feed = SongFeed()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        content
                    }
                    .padding(.bottom, 120)
                }
            }
            .foregroundColor(.white)
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
            .task {
                if feed.state == .idle {
                    await feed.load { await Self.tracks(for: artistName) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                Text(String(artistName.prefix(1)).uppercased())
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            .shadow(color: gradient.first?.opacity(0.5) ?? .clear, radius: 20, y: 10)

            Text(artistName)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)

            if feed.state == .loaded, let first = feed.songs.first {
                HStack(spacing: 16) {
                    Button {
                        if audio.isShuffling { audio.toggleShuffle() }
                        audio.play(first, in: feed.songs)
                    } label: {
                        Label(L("Play"), systemImage: "play.fill")
                            .font(.headline).foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))

                    Button {
                        if !audio.isShuffling { audio.toggleShuffle() }
                        audio.play(feed.songs.randomElement() ?? first, in: feed.songs)
                    } label: {
                        Label(L("Shuffle"), systemImage: "shuffle")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .glass(cornerRadius: 30)
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            ProgressView().tint(Theme.accentSoft).padding(.top, 40)
        case .failed:
            Text(L("Couldn't reach Audius. Check your connection."))
                .font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .empty:
            Text(L("No results")).font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .loaded:
            LazyVStack(spacing: 2) {
                ForEach(feed.songs) { song in
                    Button { audio.play(song, in: feed.songs) } label: {
                        SongRow(song: song, showBadge: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Merge the artist's music across sources (full tracks first).
    static func tracks(for artist: String) async -> [Song] {
        async let audius = AudiusService.shared.search(artist)
        async let deezer = DeezerService.shared.search(artist)
        async let apple = iTunesService.shared.searchMusic(artist)

        var seen = Set<String>()
        var result: [Song] = []
        let groups = [((try? await audius) ?? []),
                      ((try? await deezer) ?? []),
                      ((try? await apple) ?? [])]
        for group in groups {
            for song in group where !seen.contains(song.id) {
                seen.insert(song.id)
                result.append(song)
            }
        }
        return result
    }
}
