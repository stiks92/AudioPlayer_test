//
//  ImportHistoryView.swift
//  Sonava
//
//  The day-zero door into the listening biography.
//
//  Order of paths mirrors the assassin's funnel condition: the instant one
//  first (a ListenBrainz username — public API, no key, works in the first
//  minute), the deep one second (the Spotify GDPR archive, which takes
//  Spotify up to 30 days to produce — the screen says so plainly instead
//  of letting the wait look like a bug).
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportHistoryView: View {
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var importedCount: Int?
    @State private var progressCount = 0
    @State private var isImporting = false
    @State private var failed = false
    @State private var showFilePicker = false
    @State private var showTimeline = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        if journeyStore.journey.tracks.isEmpty || importedCount != nil {
                            importer
                        }
                        if !journeyStore.journey.tracks.isEmpty {
                            summary
                        }
                    }
                    .padding(Space.screenMargin)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Listening history")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.json, .plainText, .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            .sheet(isPresented: $showTimeline) {
                JourneyTimelineView().environmentObject(journeyStore)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var importer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Bring your listening past with you — every year of it, stitched to the music you own.")
                .font(.system(.subheadline))
                .foregroundColor(Theme.textSecondary)

            VStack(alignment: .leading, spacing: Space.m) {
                Text("ListenBrainz — instant")
                    .font(.sonavaDepartment)
                    .foregroundColor(Theme.accentSoft)
                HStack(spacing: Space.m) {
                    TextField("username", text: $username)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(Space.m)
                        .card(cornerRadius: Radius.card)
                        .accessibilityIdentifier("history.username")
                    Button {
                        importListenBrainz()
                    } label: {
                        if isImporting {
                            Text("\(progressCount)")
                        } else {
                            Text("Import")
                        }
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle(expands: false))
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
                    .accessibilityIdentifier("history.import")
                }
            }

            VStack(alignment: .leading, spacing: Space.m) {
                Text("Spotify archive — the deep past")
                    .font(.sonavaDepartment)
                    .foregroundColor(Theme.accentSoft)
                Text("Request your extended streaming history at privacy.spotify.com — Spotify takes up to 30 days to prepare it. When the JSON files arrive, open them here.")
                    .font(.footnote)
                    .foregroundColor(Theme.textTertiary)
                Button("Open export files") { showFilePicker = true }
                    .buttonStyle(SecondaryCapsuleButtonStyle(expands: false))
            }

            if failed {
                Text("Couldn't import that — check the username or the files.")
                    .font(.footnote)
                    .foregroundColor(Theme.destructive)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let importedCount {
                Text("Added \(importedCount) listens.")
                    .font(.system(.subheadline).weight(.semibold))
            }
            let journey = journeyStore.journey
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(journey.totalPlays)")
                    .font(.sonavaFigure)
                Text("plays across \(journey.tracks.count) tracks")
                    .font(.sonavaFact)
                    .foregroundColor(Theme.textSecondary)
                if let earliest = journey.earliest {
                    Text("since \(Date(timeIntervalSince1970: earliest).formatted(.dateTime.year().month()))")
                        .font(.sonavaFact)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: Radius.card)

            Button {
                showTimeline = true
            } label: {
                Text("Open the timeline")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityIdentifier("history.timeline")

            ownershipBlock
        }
    }

    /// The bridge, stated as a number: how much of the listened life the
    /// listener already owns as files — and the most-played gaps, each one
    /// tap from the store where buying it funds the artist.
    @ViewBuilder
    private var ownershipBlock: some View {
        let ownership = journeyStore.ownership(library: library.songs)
        if ownership.totalPlays > 0 {
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: "Owned", fact: "")
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(Int((ownership.fraction * 100).rounded()))%")
                        .font(.sonavaFigure)
                    Text("of your listened history is in your files")
                        .font(.sonavaFact)
                        .foregroundColor(Theme.textSecondary)
                }
                if !ownership.topMissing.isEmpty {
                    Text("Most played, not yet owned")
                        .font(.sonavaDepartment)
                        .foregroundColor(Theme.accentSoft)
                        .padding(.top, Space.s)
                    ForEach(Array(ownership.topMissing.enumerated()), id: \.offset) { _, row in
                        Button {
                            let query = "\(row.artist) \(row.title)"
                                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "https://bandcamp.com/search?q=\(query)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: Space.m) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title).font(.sonavaRowTitle).lineLimit(1)
                                    Text(row.artist).font(.sonavaByline)
                                        .foregroundColor(Theme.textSecondary).lineLimit(1)
                                }
                                Spacer()
                                Text(verbatim: "\(row.plays)")
                                    .font(.sonavaFact).foregroundColor(Theme.textTertiary)
                                SonavaIcon(glyph: .chevronRight, size: 12, tint: Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Buying on Bandcamp pays the artist directly. Sonava earns nothing from these links.")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
    }

    private func importListenBrainz() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isImporting = true
        failed = false
        progressCount = 0
        Task {
            do {
                let events = try await ListeningJourney.fetchListenBrainz(username: name) { count in
                    Task { @MainActor in progressCount = count }
                }
                journeyStore.add(events: events, source: "listenbrainz:\(name)")
                importedCount = events.count
            } catch {
                failed = true
            }
            isImporting = false
        }
    }

    private func importFiles(_ urls: [URL]) {
        var total = 0
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            var events = ListeningJourney.parseSpotifyExport(data)
            if events.isEmpty { events = ListeningJourney.parseListenBrainzExport(data) }
            guard !events.isEmpty else { continue }
            journeyStore.add(events: events, source: "file:\(url.lastPathComponent)")
            total += events.count
        }
        importedCount = total
        failed = total == 0
    }
}

/// The biography, year by year — quiet record-shop typography, newest first.
struct JourneyTimelineView: View {
    @EnvironmentObject private var journeyStore: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var flyerURL: URL?

    /// The day-zero artifact: top-10 most-lived-with tracks as a flyer that
    /// plays for whoever receives it.
    private func buildFlyer() {
        let top = journeyStore.journey.tracks.values
            .sorted { $0.plays > $1.plays }
            .prefix(10)
        let entries = top.map { track in
            let year = Calendar.current.component(.year,
                from: Date(timeIntervalSince1970: track.firstListen))
            return FlyerEntry(
                artist: track.artist, title: track.title,
                note: String(localized: "with me since \(String(year))"))
        }
        flyerURL = FlyerBuilder.writeFile(
            entries: Array(entries),
            heading: String(localized: "Records I live with"),
            subtitle: String(localized: "A flyer from my Sonava library"),
            openHint: String(localized: "Open in a browser and tap a row to hear 30 seconds."),
            creditText: String(localized: "Previews courtesy of"))
    }

    @State private var recapYear: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        if let year = journeyStore.recapYear() {
                            Button {
                                recapYear = year
                            } label: {
                                HStack {
                                    Text("Your \(year) recap")
                                    Spacer()
                                    SonavaIcon(glyph: .chevronRight, size: 14, tint: Theme.accentSoft)
                                }
                            }
                            .buttonStyle(SecondaryCapsuleButtonStyle())
                            .accessibilityIdentifier("journey.recap")
                        }
                        ForEach(journeyStore.timeline(), id: \.year) { entry in
                            VStack(alignment: .leading, spacing: Space.m) {
                                Department(title: LocalizedStringKey(entry.year),
                                           fact: String(localized: "\(entry.plays) tracks").uppercased())
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(entry.topArtists.enumerated()), id: \.offset) { index, artist in
                                        HStack(spacing: Space.m) {
                                            Text(verbatim: String(format: "%02d", index + 1))
                                                .font(.sonavaOrdinal)
                                                .foregroundColor(Theme.accentSoft)
                                            Text(artist.name)
                                                .font(.sonavaRowTitle)
                                            Spacer()
                                            Text(verbatim: "\(artist.plays)")
                                                .font(.sonavaFact)
                                                .foregroundColor(Theme.textTertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Your years in music")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        buildFlyer()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(.body).weight(.medium))
                            .foregroundColor(Theme.accentSoft)
                    }
                    .identified("journey.flyer", label: "Share a flyer")
                }
            }
            .sheet(item: $flyerURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(item: $recapYear) { year in
                RecapView(year: year).environmentObject(journeyStore)
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
