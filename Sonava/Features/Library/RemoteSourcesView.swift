//
//  RemoteSourcesView.swift
//  Sonava
//
//  Everything the listener owns that isn't on the phone: their Subsonic
//  server and their cloud drive.
//
//  One shelf rather than two. They are the same idea from the listener's
//  side — "my music, kept somewhere else" — and splitting them cost the
//  Library tab bar a segment it could not spare: at seven, «Плейлисты» and
//  «Избранное» were truncating to ellipses.
//
//  The inner picker appears only when there is a choice to make. A listener
//  with a Navidrome and no cloud drive never sees a control that offers them
//  an empty screen.
//

import SwiftUI

struct RemoteSourcesView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var cloudStore: CloudStore

    enum Source: String, CaseIterable {
        case server, cloud

        var title: LocalizedStringKey {
            switch self {
            case .server: return "Server"
            case .cloud: return "Cloud drive"
            }
        }
    }

    @State private var source: Source = .server

    private var hasServer: Bool { serverStore.service != nil }
    private var hasCloud: Bool { !cloudStore.usableDrives.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if hasServer && hasCloud {
                SegmentedControl(
                    segments: Source.allCases.map {
                        .init(value: $0, title: $0.title, identifier: "sources.\($0.rawValue)")
                    },
                    selection: $source)
                shelf(for: source)
            } else if hasCloud {
                CloudBrowseView()
            } else {
                // Also the not-connected case: the server shelf's empty state
                // is the one that explains what a server is.
                ServerBrowseView()
            }
        }
        .onAppear {
            // Land on whichever one they actually have.
            if !hasServer && hasCloud { source = .cloud }
        }
    }

    @ViewBuilder
    private func shelf(for source: Source) -> some View {
        switch source {
        case .server: ServerBrowseView()
        case .cloud:  CloudBrowseView()
        }
    }
}
