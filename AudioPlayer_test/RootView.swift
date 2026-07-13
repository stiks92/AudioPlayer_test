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

    @State private var selection: AppTab = .home
    @State private var showNowPlaying = false
    @Namespace private var playerNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if audio.currentSong != nil && !showNowPlaying {
                            MiniPlayerView(namespace: playerNamespace) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                    showNowPlaying = true
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        AppTabBar(selection: $selection)
                    }
                    .padding(.top, 6)
                }

            if showNowPlaying {
                NowPlayingView(namespace: playerNamespace) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                        showNowPlaying = false
                    }
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .environmentObject(audio)
        .environmentObject(library)
        .preferredColorScheme(.dark)
        .onChange(of: audio.currentSong) { song in
            if let song { library.markPlayed(song) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:    HomeView()
        case .search:  SearchView()
        case .radio:   RadioView()
        case .library: LibraryView()
        }
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable {
    case home, search, radio, library

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .radio: return "Radio"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .radio: return "dot.radiowaves.left.and.right"
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
                        Text(tab.title)
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
