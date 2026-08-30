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
    @ObservedObject private var appleMusic = AppleMusicService.shared
    @ObservedObject private var serviceKeys = ServiceKeysStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pasted = ""
    @State private var name = ""
    @State private var youtubeLink = ""
    @State private var showFileImporter = false
    @State private var showServiceKeys = false
    @State private var isMatching = false
    @State private var outcome: PlaylistImport.Outcome?
    @State private var failure: String?
    /// The hub's engine room, shared with every other import path. Built
    /// lazily so it snapshots the doors the listener actually has open, and
    /// rebuilt (after invalidate) when a connection changes underneath it.
    @State private var resolver: TrackResolver?

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
                            linkSection
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
            .sheet(isPresented: $showServiceKeys) {
                ServiceKeysView()
            }
        }
        .preferredColorScheme(.dark)
        // A door changed (server connected, Apple Music authorized): earlier
        // resolutions may now be beatable, so the resolver expires and the
        // next import snapshots fresh doors.
        .onChange(of: serverStore.isConnected) { _, _ in rebuildResolver() }
        .onChange(of: appleMusic.availability) { _, _ in rebuildResolver() }
    }

    private func rebuildResolver() {
        resolver?.invalidate()
        resolver = nil
    }

    private func currentResolver() -> TrackResolver {
        if let resolver { return resolver }
        let built = TrackResolver.live(library: library, serverStore: serverStore)
        resolver = built
        return built
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

    /// YouTube by link — composition only. The Data API reads the playlist's
    /// titles (that much their terms allow); the audio never comes from
    /// YouTube — every row is matched into the listener's own sources like
    /// any other import.
    @ViewBuilder
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "From a YouTube link")
            if serviceKeys.key(YouTubePlaylistImporter.apiKeyKey) != nil {
                Text("Paste a playlist link. Sonava reads the titles and finds each track in your own sources — no audio comes from YouTube.")
                    .font(.system(.footnote))
                    .foregroundColor(Theme.textTertiary)
                TextField("", text: $youtubeLink,
                          prompt: Text("youtube.com/playlist?list=…").foregroundColor(Theme.textTertiary))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    .card(cornerRadius: Radius.control)
                Button {
                    Task { await importFromLink() }
                } label: {
                    Text(isMatching ? "Searching…" : "Read the playlist")
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .disabled(youtubeLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMatching)
                .accessibilityIdentifier("import.youtube")
            } else {
                // No key — the honest sentence and the door to the screen
                // where the owner can change that. Never a button that 403s.
                Text("Needs the owner's YouTube API key — add it once and playlist links import here.")
                    .font(.system(.footnote))
                    .foregroundColor(Theme.textTertiary)
                Button { showServiceKeys = true } label: {
                    HStack(spacing: Space.s) {
                        SonavaIcon(glyph: .chevronRight, size: 14, tint: Theme.accentSoft)
                        Text("Service keys")
                    }
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .accessibilityIdentifier("import.youtubeKeys")
            }
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
                if outcome.matched.isEmpty && outcome.previews.isEmpty {
                    Text("Nothing in that list matched anything Sonava can reach.")
                        .font(.system(.subheadline))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if !outcome.matched.isEmpty || !outcome.previews.isEmpty {
                Button {
                    playlistStore.importShared(
                        UserPlaylist(name: playlistName,
                                     tracks: outcome.matched + outcome.previews))
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

            // The middle column of the ledger: rows where only a 30-second
            // preview exists anywhere the listener can reach. Saved with
            // their PREVIEW badge, never dressed up as full matches.
            if !outcome.previews.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Department(title: "Previews only")
                    Text("For these, only a 30-second preview exists in your sources. They save with a PREVIEW badge.")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                    VStack(spacing: 0) {
                        ForEach(outcome.previews.prefix(30)) { song in
                            SongRow(song: song, showBadge: true)
                        }
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
                youtubeLink = ""
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

    /// Every parsed line goes through the shared TrackResolver — the same
    /// door order every import path speaks: files → server → the listener's
    /// Apple Music subscription → Audius → previews (labelled as previews).
    /// The old hand-rolled chain here skipped Apple Music entirely, which
    /// meant a subscriber's import pretended their subscription didn't exist.
    private func match(_ parsed: PlaylistImport.ParseResult,
                       origin: TrackOrigin = .pastedText) async {
        isMatching = true
        defer { isMatching = false }

        let foreign = PlaylistImport.foreignTracks(parsed.tracks, origin: origin)
        let results = await currentResolver().resolveAll(foreign)
        outcome = PlaylistImport.outcome(from: results)
    }

    /// Reads the YouTube playlist's titles (names only — see `linkSection`)
    /// and sends them through the same matcher as every other list.
    private func importFromLink() async {
        guard let key = serviceKeys.key(YouTubePlaylistImporter.apiKeyKey) else { return }
        guard let playlistID = YouTubePlaylistImporter.playlistID(from: youtubeLink) else {
            failure = String(localized: "That doesn't look like a YouTube playlist link.")
            return
        }
        isMatching = true
        do {
            let tracks = try await YouTubePlaylistImporter(apiKey: key).tracks(playlistID: playlistID)
            isMatching = false
            guard !tracks.isEmpty else {
                failure = String(localized: "That playlist has no readable tracks — it may be private.")
                return
            }
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = String(localized: "YouTube playlist")
            }
            await match(PlaylistImport.ParseResult(name: playlistName, tracks: tracks),
                        origin: .youtubeLink)
        } catch {
            isMatching = false
            failure = String(localized: "Couldn't read that playlist — check the link and the key.")
        }
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
