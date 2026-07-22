//
//  RootView.swift
//  AudioPlayer_test
//
//  Hosts the tab scenes, the docked mini player and the expanding
//  Now Playing overlay.
//

import SwiftUI

struct RootView: View {
    @StateObject private var audio = AudioManager.shared
    @StateObject private var library = MusicLibrary()
    @StateObject private var proStore = ProStore()
    @StateObject private var serverStore = ServerStore()
    @StateObject private var playlistStore = PlaylistStore()

    @AppStorage("hasOnboarded.v1") private var hasOnboarded = false
    @State private var selection: AppTab = .home
    @State private var showNowPlaying = false
    /// Tabs that have been opened at least once — kept alive so switching
    /// back is instant (no reload flicker).
    @State private var visited: Set<AppTab> = [.home]

    private let playerSpring = Animation.spring(response: 0.45, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            VStack(spacing: 8) {
                if audio.currentSong != nil && !showNowPlaying {
                    MiniPlayerView {
                        withAnimation(playerSpring) { showNowPlaying = true }
                    }
                    .transition(.opacity)
                }
                AppTabBar(selection: $selection)
            }

            if showNowPlaying {
                NowPlayingView {
                    withAnimation(playerSpring) { showNowPlaying = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .environmentObject(audio)
        .environmentObject(audio.clock)
        .environmentObject(library)
        .environmentObject(proStore)
        .environmentObject(serverStore)
        .environmentObject(playlistStore)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            OnboardingView { hasOnboarded = true }
        }
        .onChange(of: audio.currentSong) { song in
            if let song { library.markPlayed(song) }
        }
        .onChange(of: selection) { newValue in
            visited.insert(newValue)
            Haptics.selection()
        }
        .task {
            audio.restoreLastSession()
        }
    }

    /// All visited tabs stay in the hierarchy; only the selected one is shown.
    private var tabContent: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if visited.contains(tab) {
                    view(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                }
            }
        }
    }

    @ViewBuilder
    private func view(for tab: AppTab) -> some View {
        switch tab {
        case .home:     HomeView()
        case .search:   SearchView()
        case .radio:    RadioView()
        case .podcasts: PodcastsView()
        case .library:  LibraryView()
        }
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable {
    case home, search, radio, podcasts, library

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .radio: return "Radio"
        case .podcasts: return "Podcasts"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .radio: return "dot.radiowaves.left.and.right"
        case .podcasts: return "mic.fill"
        case .library: return "square.stack.fill"
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var indicator

    var body: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent.opacity(0.25))
                                    .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                                    .frame(width: 54, height: 32)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(selected ? Theme.accentSoft : Theme.textSecondary)
                        }
                        .frame(height: 32)
                        Text(L(tab.title))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(selected ? Theme.accentSoft : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Theme.background.opacity(0.5)))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }
}
