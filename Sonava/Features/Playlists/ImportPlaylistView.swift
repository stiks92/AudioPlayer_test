//
//  ImportPlaylistView.swift
//  Sonava
//
//  Bringing a playlist in from somewhere else.
//
//  The screen's whole argument is in what it shows *after*: the tracks it
//  found, and — named, in full — the ones it could not. A migration that
//  silently drops a fifth of a playlist is the complaint the Russian review
//  corpus is full of, and the only way to not be that is to say so.
//
//  Two ways in, because people arrive with different things in hand: a file
//  they exported (CSV from Exportify or TuneMyMusic, an M3U from a desktop
//  player) or a list they pasted out of a chat.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportPlaylistView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var serverStore: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var pasted = ""
    @State private var name = ""
    @State private var showFileImporter = false
    @State private var isMatching = false
    @State private var outcome: PlaylistImport.Outcome?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        if let outcome {
                            result(outcome)
                        } else {
                            intro
                            fileSection
                            pasteSection
                        }
                    }
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Import a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    readFile(url)
                case .failure(let error):
                    failure = error.localizedDescription
                }
            }
            .alert("Couldn't read that file",
                   isPresented: Binding(get: { failure != nil },
                                        set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Before

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Bring a playlist from anywhere — a file you exported, or a list you copied.")
                .font(.system(.subheadline))
                .foregroundColor(Theme.textSecondary)
            Text("Sonava searches your files, your server and its streaming sources for each track, and tells you exactly which ones it couldn't find.")
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "From a file")
            Text("CSV from Exportify or TuneMyMusic, or an M3U from a desktop player.")
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
            Button { showFileImporter = true } label: {
                HStack(spacing: Space.s) {
                    SonavaIcon(glyph: .download, size: 18, tint: Theme.accentSoft)
                    Text("Choose a file")
                }
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .accessibilityIdentifier("import.file")
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "From a list")
            Text("One track per line, as “Artist — Title”.")
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
            TextEditor(text: $pasted)
                .scrollContentBackground(.hidden)
                .frame(height: 160)
                .foregroundColor(.white)
                .font(.system(.footnote, design: .monospaced))
                .padding(Space.s)
                .card(cornerRadius: Radius.control)

            TextField("", text: $name,
                      prompt: Text("Playlist name").foregroundColor(Theme.textTertiary))
                .foregroundColor(.white)
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .card(cornerRadius: Radius.control)

            Button {
                Task { await match(PlaylistImport.parse(pasted, name: playlistName)) }
            } label: {
                HStack {
                    if isMatching {
                        AnimatedIcon(glyph: .loading, mode: .loop(true),
                                     size: 20, tint: Theme.background)
                    }
                    Text(isMatching ? "Searching…" : "Import")
                }
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMatching)
            .accessibilityIdentifier("import.paste")
        }
    }

    private var playlistName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "Imported playlist") : trimmed
    }

    // MARK: - After

    private func result(_ outcome: PlaylistImport.Outcome) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(outcome.matched.count) of \(outcome.total) found")
                    .font(.system(.title2).weight(.light))
                    .foregroundColor(Theme.textPrimary)
                if outcome.matched.isEmpty {
                    Text("Nothing in that list matched anything Sonava can reach.")
                        .font(.system(.subheadline))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if !outcome.matched.isEmpty {
                Button {
                    playlistStore.importShared(
                        UserPlaylist(name: playlistName, tracks: outcome.matched))
                    Haptics.success()
                    dismiss()
                } label: {
                    Text("Save as “\(playlistName)”")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .accessibilityIdentifier("import.save")

                VStack(spacing: 0) {
                    ForEach(outcome.matched.prefix(30)) { song in
                        SongRow(song: song)
                    }
                }
            }

            // The honest half. Named in full and in the order they were
            // listed, because "12 tracks couldn't be found" is not something
            // a person can act on and a list of twelve names is.
            if !outcome.missing.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Department(title: "Not found")
                    Text("These aren't in your library, on your server, or in any source Sonava searches. Import the files and they'll join automatically.")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                    ForEach(Array(outcome.missing.enumerated()), id: \.offset) { _, track in
                        HStack(spacing: Space.s) {
                            SonavaIcon(glyph: .close, size: 11, tint: Theme.warning)
                            Text(track.artist.isEmpty ? track.title
                                                      : "\(track.artist) — \(track.title)")
                                .font(.system(.footnote))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Button("Start over") {
                self.outcome = nil
                pasted = ""
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    // MARK: - Work

    private func readFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1251) else {
            failure = String(localized: "That file isn't text Sonava can read.")
            return
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = (url.lastPathComponent as NSString).deletingPathExtension
        }
        Task { await match(PlaylistImport.parse(text, name: playlistName)) }
    }

    /// Looks every parsed line up, in the order that costs least: what the
    /// listener already owns first, then their server, then the streaming
    /// catalogues. A track found locally never touches the network.
    private func match(_ parsed: PlaylistImport.ParseResult) async {
        isMatching = true
        defer { isMatching = false }

        var result = PlaylistImport.Outcome()
        let owned = library.songs
        let service = serverStore.service

        for track in parsed.tracks {
            if let local = owned.first(where: { PlaylistImport.matches($0, track) }) {
                result.matched.append(local)
                continue
            }
            if let service,
               let hits = try? await service.search(track.query),
               let hit = hits.first(where: { PlaylistImport.matches($0, track) }) {
                result.matched.append(hit)
                continue
            }
            if let hits = try? await AudiusService.shared.search(track.query),
               let hit = hits.first(where: { PlaylistImport.matches($0, track) }) {
                result.matched.append(hit)
                continue
            }
            result.missing.append(track)
        }
        outcome = result
    }
}

private extension String.Encoding {
    /// Playlists exported on a Russian Windows box are still written in
    /// CP1251 often enough to be worth the one-line fallback — otherwise the
    /// whole file reads as nothing.
    static let windowsCP1251 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)))
}
