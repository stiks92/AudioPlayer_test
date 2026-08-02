//
//  PodcastsView.swift
//  Sonava
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

    /// iTunes search takes the English term; the chip label translates.
    private let genres: [FilterChip<String>] = [
        "Technology", "News", "Comedy", "True Crime", "Business",
        "Science", "Health", "Sports", "History", "Education"
    ].map(FilterChip.init)

    private let columns = [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible(), spacing: Space.l)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.screenMargin) {
                        Text("Podcasts")
                            .font(.sonavaMasthead)
                            .foregroundColor(Theme.textPrimary)
                        searchField
                        if query.isEmpty { genreChips }
                        content
                    }
                    .padding(.horizontal, Space.screenMargin)
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
        HStack(spacing: Space.m) {
            Button {
                guard !query.isEmpty else { return }
                query = ""
            } label: {
                AnimatedIcon(glyph: .searchToX, mode: .toggle(!query.isEmpty),
                             size: 20, tint: Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty)
            TextField("", text: $query,
                      prompt: Text("Search podcasts")
                        .foregroundColor(Theme.textSecondary))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .card(cornerRadius: Radius.card)
    }

    private var genreChips: some View {
        FilterChipRow(chips: genres, selection: $selectedGenre) { genre in
            Task { await feed.load { try await iTunesService.shared.podcasts(genre: genre) } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            VStack(spacing: Space.l) {
                ProgressView().tint(Theme.accentSoft)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
        case .failed:
            Button {
                Task { await feed.load { try await iTunesService.shared.podcasts(genre: selectedGenre) } }
            } label: {
                message(.radio, "Couldn't load podcasts.\nTap to retry.")
            }
            .buttonStyle(.plain)
        case .empty:
            message(.search, "No podcasts found.")
        case .loaded:
            LazyVGrid(columns: columns, spacing: Space.screenMargin) {
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

    private func message(_ icon: SonavaIcon.Glyph, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: Space.m) {
            SonavaIcon(glyph: icon, size: 42, tint: Theme.textTertiary)
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
                    SonavaIcon(glyph: .podcasts, size: 30, tint: .white.opacity(0.85))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(podcast.title)
                .font(.system(.footnote).weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Text(podcast.author)
                .font(.system(.caption))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
