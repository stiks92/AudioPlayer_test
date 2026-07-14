//
//  PodcastsView.swift
//  AudioPlayer_test
//
//  Browse & search podcasts (keyless, via iTunes Search).
//

import SwiftUI

@MainActor
final class PodcastFeed: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, empty, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var podcasts: [Podcast] = []

    func load(_ fetch: @escaping () async throws -> [Podcast]) async {
        state = .loading
        do {
            let result = try await fetch()
            podcasts = result
            state = result.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // Superseded by a newer request.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Superseded.
        } catch {
            podcasts = []
            state = .failed
        }
    }
}

struct PodcastsView: View {
    @EnvironmentObject private var audio: AudioManager

    @StateObject private var feed = PodcastFeed()
    @State private var query = ""
    @State private var selectedGenre = "Technology"

    private let genres = ["Technology", "News", "Comedy", "True Crime", "Business",
                          "Science", "Health", "Sports", "History", "Education"]

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L("Podcasts"))
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundColor(Theme.textPrimary)
                        searchField
                        if query.isEmpty { genreChips }
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 2 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if Task.isCancelled { return }
                    await feed.load { try await iTunesService.shared.searchPodcasts(trimmed) }
                } else if feed.state == .idle {
                    await feed.load { try await iTunesService.shared.podcasts(genre: selectedGenre) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.textSecondary)
            TextField(L("Search podcasts"), text: $query)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glass(cornerRadius: 16)
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    let isSelected = selectedGenre == genre
                    Text(L(genre))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.background : Theme.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.08)))
                        .onTapGesture {
                            selectedGenre = genre
                            Haptics.selection()
                            Task { await feed.load { try await iTunesService.shared.podcasts(genre: genre) } }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView().tint(Theme.accentSoft)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
        case .failed:
            Button {
                Task { await feed.load { try await iTunesService.shared.podcasts(genre: selectedGenre) } }
            } label: {
                message("wifi.slash", "Couldn't load podcasts.\nTap to retry.")
            }
            .buttonStyle(.plain)
        case .empty:
            message("magnifyingglass", "No podcasts found.")
        case .loaded:
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(feed.podcasts) { podcast in
                    NavigationLink {
                        PodcastDetailView(podcast: podcast)
                    } label: {
                        PodcastCard(podcast: podcast)
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.97))
                }
            }
        }
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundColor(Theme.textTertiary)
            Text(text).font(.subheadline).foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 50)
    }
}

struct PodcastCard: View {
    let podcast: Podcast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: podcast.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    LinearGradient(colors: podcast.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "mic.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.85))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(podcast.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Text(podcast.author)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
