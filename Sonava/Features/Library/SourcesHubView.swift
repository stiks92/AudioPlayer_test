//
//  SourcesHubView.swift
//  Sonava
//
//  The hub: every way music enters the app, on one screen, sorted by the
//  honesty of the promise. Section 01 plays *here*; section 02 is a remote
//  for someone else's app; section 03 moves data in. A service the owner
//  hasn't configured yet shows dimmed with a plain sentence — never a
//  button that would 403 in a reviewer's hands (the consilium's App Review
//  judge was specific about that).
//
//  No Pro locks anywhere on this screen: Spotify/SoundCloud/Deezer terms
//  all forbid paywalling their content, so connecting sources is free by
//  design, not by generosity.
//

import SwiftUI

/// Self-serve dashboard keys the owner pastes once (TIDAL client id,
/// YouTube API key…). A missing key is a card state, not a crash.
@MainActor
final class ServiceKeysStore: ObservableObject {
    static let shared = ServiceKeysStore()

    @Published private(set) var keys: [String: String] {
        didSet { file.write(keys) }
    }
    private let file: JSONFileStore<[String: String]>

    init(filename: String = "service-keys.json") {
        file = JSONFileStore(filename, default: [:])
        keys = file.read()
    }

    func key(_ name: String) -> String? {
        let value = keys[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    func set(_ name: String, to value: String) {
        keys[name] = value
    }
}

struct SourcesHubView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var cloudStore: CloudStore
    @EnvironmentObject private var proStore: ProStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var audio: AudioManager
    @ObservedObject private var appleMusic = AppleMusicService.shared
    @ObservedObject private var serviceKeys = ServiceKeysStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showConnectServer = false
    @State private var showConnectCloud = false
    @State private var showImportFiles = false
    @State private var showImportPlaylist = false
    @State private var showHistoryImport = false
    @State private var showServiceKeys = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        section("Plays here", ordinal: 1) {
                            filesCard
                            cloudCard
                            serverCard
                            appleMusicCard
                            archiveCard
                            jamendoCard
                            tidalCard
                            soundcloudCard
                        }
                        #if DEBUG
                        // Spotify's development mode caps at five whitelisted
                        // users forever — an owner feature, invisible in the
                        // App Store build so no reviewer ever meets a 403.
                        section("Remote control", ordinal: 2) {
                            spotifyCard
                        }
                        #endif
                        // Release has no section 02, and a visible 01/03
                        // numbering would read as a bug and out the cut —
                        // so the ordinal is computed, not hard-wired.
                        section("Moving in", ordinal: movingInOrdinal) {
                            importCard
                            historyCard
                            youtubeCard
                            yandexCard
                        }
                    }
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .sheet(isPresented: $showConnectServer) {
                ConnectServerView().environmentObject(serverStore).environmentObject(proStore)
            }
            .sheet(isPresented: $showConnectCloud) {
                ConnectCloudView().environmentObject(cloudStore).environmentObject(proStore)
            }
            .sheet(isPresented: $showImportPlaylist) {
                ImportPlaylistView()
                    .environmentObject(library).environmentObject(playlistStore)
                    .environmentObject(serverStore).environmentObject(audio)
            }
            .sheet(isPresented: $showHistoryImport) {
                ImportHistoryView().environmentObject(journeyStore).environmentObject(library)
            }
            .sheet(isPresented: $showServiceKeys) {
                ServiceKeysView()
            }
            .fileImporter(isPresented: $showImportFiles,
                          allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importFiles(at: urls) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var movingInOrdinal: Int {
        #if DEBUG
        3
        #else
        2
        #endif
    }

    private func section(_ title: LocalizedStringKey, ordinal: Int,
                         @ViewBuilder cards: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Text(verbatim: String(format: "%02d", ordinal))
                    .font(.sonavaOrdinal).foregroundColor(Theme.accentSoft)
                Department(title: title)
            }
            cards()
        }
    }

    // MARK: - 01 Plays here

    private var filesCard: some View {
        SourceCard(glyph: .download, title: "Your files",
                   fact: String(localized: "\(library.songs.count) tracks"),
                   state: .connected) { showImportFiles = true }
    }

    private var cloudCard: some View {
        SourceCard(glyph: .wave, title: "Cloud drives",
                   fact: cloudStore.drives.isEmpty
                       ? String(localized: "Yandex.Disk, Mail.ru, any WebDAV")
                       : cloudStore.drives.map(\.label).joined(separator: " · "),
                   state: cloudStore.drives.isEmpty ? .disconnected : .connected) {
            showConnectCloud = true
        }
    }

    private var serverCard: some View {
        // Named in full because each name is a community that searches for
        // it: all three speak Subsonic, all three already work.
        SourceCard(glyph: .server, title: "Self-hosted server",
                   fact: serverStore.isConnected
                       ? (serverStore.servers.first?.host ?? "")
                       : String(localized: "Navidrome · Funkwhale · Airsonic — any Subsonic server"),
                   state: serverStore.isConnected ? .connected : .disconnected) {
            showConnectServer = true
        }
    }

    private var archiveCard: some View {
        // Keyless and legal by the collections' own terms — nothing to
        // connect, so the card just states what is already true.
        SourceCard(glyph: .wave, title: "Internet Archive",
                   fact: String(localized: "Live concerts, netlabels, 78s — full tracks, no key"),
                   state: .connected, action: nil)
    }

    private var jamendoCard: some View {
        SourceCard(glyph: .note, title: "Jamendo",
                   fact: serviceKeys.key(JamendoService.clientIDKey) != nil
                       ? String(localized: "Creative Commons catalogue — full tracks")
                       : String(localized: "Owner setup · free key · devportal.jamendo.com"),
                   state: serviceKeys.key(JamendoService.clientIDKey) != nil ? .connected : .ownerKey) {
            showServiceKeys = true
        }
    }

    private var appleMusicCard: some View {
        let state: SourceCard.State
        let fact: String
        switch appleMusic.availability {
        case .ready:
            state = .connected; fact = String(localized: "Full catalogue, your subscription")
        case .noSubscription:
            state = .attention; fact = String(localized: "Signed in — no active subscription")
        case .notConfigured:
            state = .ownerKey; fact = String(localized: "MusicKit switch in App Store Connect · ~5 min")
        case .notConnected:
            state = .disconnected; fact = String(localized: "100 million tracks with your subscription")
        }
        return SourceCard(glyph: .note, title: "Apple Music", fact: fact, state: state) {
            Task { await AppleMusicService.shared.connect() }
        }
    }

    private var tidalCard: some View {
        // The honest 2026 status: TIDAL hands out self-serve keys but never
        // opened production access — third-party apps get 30-second previews
        // and a guidelines ban on mixing TIDAL into other audio. The key is
        // still worth saving for a preview integration later.
        SourceCard(glyph: .wave, title: "TIDAL",
                   fact: serviceKeys.key("tidal.clientID") != nil
                       ? String(localized: "Key saved — waiting for TIDAL to open full playback")
                       : String(localized: "Third-party apps get 30-second previews for now"),
                   state: .ownerKey) {
            showServiceKeys = true
        }
    }

    private var soundcloudCard: some View {
        // Self-serve since May 2026 — behind a paid Artist Pro subscription
        // on the owner's account, which is the sentence the card says.
        SourceCard(glyph: .scrobble, title: "SoundCloud",
                   fact: String(localized: "Owner setup · needs a SoundCloud Artist Pro subscription"),
                   state: .ownerKey, action: nil)
    }

    // MARK: - 02 Remote control (owner build only)

    #if DEBUG
    private var spotifyCard: some View {
        SourceCard(glyph: .shuffle, title: "Spotify",
                   fact: String(localized: "Plays through the Spotify app · owner circle of five"),
                   state: serviceKeys.key("spotify.clientID") != nil ? .disconnected : .ownerKey,
                   action: nil)
    }
    #endif

    // MARK: - 03 Moving in

    private var importCard: some View {
        SourceCard(glyph: .download, title: "From a file or pasted text",
                   fact: String(localized: "Spotify, Yandex, CSV, M3U — matched to your sources"),
                   state: .importOnly) { showImportPlaylist = true }
    }

    private var historyCard: some View {
        SourceCard(glyph: .restore, title: "Listening history",
                   fact: journeyStore.journey.tracks.isEmpty
                       ? String(localized: "ListenBrainz · Spotify archive")
                       : String(localized: "\(journeyStore.journey.totalPlays) plays"),
                   state: .importOnly) { showHistoryImport = true }
    }

    @ViewBuilder
    private var youtubeCard: some View {
        // With a key the link import genuinely works (titles only — playback
        // stays on YouTube, as their policies demand). Without one, the card
        // leads to the keys screen instead of pretending.
        if serviceKeys.key(YouTubePlaylistImporter.apiKeyKey) != nil {
            SourceCard(glyph: .chevronRight, title: "YouTube playlists",
                       fact: String(localized: "Paste a playlist link — titles matched to your sources"),
                       state: .importOnly) { showImportPlaylist = true }
        } else {
            SourceCard(glyph: .chevronRight, title: "YouTube playlists",
                       fact: String(localized: "Owner setup · Google Cloud key · ~10 min"),
                       state: .ownerKey) { showServiceKeys = true }
        }
    }

    private var yandexCard: some View {
        // The honest Yandex story, stated instead of faked: no public API
        // exists; playlists come in as pasted text, files through Disk.
        SourceCard(glyph: .download, title: "Yandex Music",
                   fact: String(localized: "Playlists by pasted text · files via Yandex.Disk"),
                   state: .importOnly) { showImportPlaylist = true }
    }
}

/// One source, one card: monochrome glyph, grotesque title, mono fact line,
/// and the button-ladder rung its state earns.
struct SourceCard: View {
    enum State {
        case connected      // ivory check, quiet
        case disconnected   // outlined "Connect"
        case ownerKey       // dimmed 60%, mono sentence, no button
        case importOnly     // capsule badge "Import"
        case attention      // the one warm signal: amber dot + reconnect
    }

    let glyph: SonavaIcon.Glyph
    let title: LocalizedStringKey
    let fact: String
    let state: State
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.l) {
            SonavaIcon(glyph: glyph, size: 20, tint: Theme.textSecondary)
                .frame(width: Space.iconColumn, height: Space.iconColumn)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s) {
                    Text(title).font(.system(.subheadline).weight(.semibold))
                    if case .attention = state {
                        Circle().fill(Theme.accentWarm).frame(width: 6, height: 6)
                    }
                }
                Text(verbatim: fact)
                    .font(.sonavaFact)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
        .opacity(state.dimmed ? 0.6 : 1)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .connected:
            Text(verbatim: "✓")
                .font(.sonavaFact)
                .foregroundColor(Theme.accentSoft)
        case .disconnected:
            if let action {
                Button(action: action) {
                    Text("Connect").lineLimit(1).fixedSize()
                }
                .buttonStyle(SecondaryCapsuleButtonStyle(expands: false))
            }
        case .ownerKey:
            // A key-entry door when there is one: opening a form is honest
            // in anyone's hands — unlike a connect button that would 403.
            if let action {
                Button("Add key", action: action)
                    .buttonStyle(QuietButtonStyle())
            }
        case .importOnly:
            if let action {
                Button(action: action) {
                    Text("Import").lineLimit(1).fixedSize()
                }
                .buttonStyle(SecondaryCapsuleButtonStyle(expands: false))
            }
        case .attention:
            if let action {
                Button("Reconnect", action: action)
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

private extension SourceCard.State {
    var dimmed: Bool { if case .ownerKey = self { return true } else { return false } }
}
