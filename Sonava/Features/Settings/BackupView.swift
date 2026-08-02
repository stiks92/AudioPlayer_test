//
//  BackupView.swift
//  Sonava
//
//  "Move to a new iPhone" — the screen that makes a library survive a phone.
//
//  Written as an errand rather than a feature: the listener is standing there
//  with two phones, and the screen's whole job is to tell them what to do on
//  each one. Everything else — versions, counts, schema — stays out of the
//  way until something goes wrong, at which point it says exactly what.
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss

    @State private var exported: URL?
    @State private var showImporter = false
    @State private var outcome: LibraryBackup.Outcome?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        intro
                        exportSection
                        importSection
                        if let outcome { result(outcome) }
                    }
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Move to a new iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .sheet(item: Binding(get: { exported.map(ExportedFile.init) },
                                 set: { if $0 == nil { exported = nil } })) { file in
                ShareSheet(items: [file.url])
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json, .data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if let backup = LibraryBackup.read(from: url) {
                        outcome = backup.restore(library: library,
                                                 playlists: playlistStore,
                                                 servers: serverStore,
                                                 effects: audio.effects)
                        Haptics.success()
                    } else {
                        failure = String(localized: "That file isn't a Sonava backup, or it was made by a newer version.")
                    }
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

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Your playlists, favourites, servers and sound settings travel in one file. Save it somewhere you'll find it — Files, iCloud Drive, a message to yourself.")
                .font(.system(.subheadline))
                .foregroundColor(Theme.textSecondary)
            Text("Your audio files don't travel in the backup — they're yours and they're large. Bring them across the way you brought them in, and this file will find them again.")
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "On this iPhone")
            Button {
                let backup = LibraryBackup.snapshot(library: library,
                                                    playlists: playlistStore,
                                                    servers: serverStore,
                                                    effects: audio.effects,
                                                    downloads: audio.downloads)
                if let url = backup.writeToFile() {
                    Haptics.impact()
                    exported = url
                } else {
                    failure = String(localized: "The backup couldn't be written. Check you have free space.")
                }
            } label: {
                Text("Save a backup")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityIdentifier("backup.export")

            summaryLine
        }
    }

    /// What is actually in the file, counted — so "save a backup" isn't a
    /// promise the listener has to take on faith.
    private var summaryLine: some View {
        let files = library.songs.filter { $0.source == .local }.count
        return Text("\(playlistStore.playlists.count) playlists · \(library.favorites.count) favourites · \(serverStore.servers.count) servers · \(files) imported files" as LocalizedStringKey)
            .font(.system(.footnote).monospacedDigit())
            .foregroundColor(Theme.textTertiary)
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "On the new iPhone")
            Text("Install Sonava, bring your audio files over, then open the backup file here.")
                .font(.system(.footnote))
                .foregroundColor(Theme.textSecondary)
            Button {
                showImporter = true
            } label: {
                HStack(spacing: Space.s) {
                    SonavaIcon(glyph: .restore, size: 18, tint: Theme.accentSoft)
                    Text("Restore from a backup")
                        .font(.system(.subheadline).weight(.semibold))
                        .foregroundColor(Theme.accentSoft)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: Space.hitTarget)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.97))
            .accessibilityIdentifier("backup.import")

            Text("Restoring adds to what's already here — it never replaces or deletes.")
                .font(.system(.caption2))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private func result(_ outcome: LibraryBackup.Outcome) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "Restored")
            if outcome.isEmpty && outcome.missingFiles.isEmpty {
                Text("Everything in that backup was already here.")
                    .font(.system(.subheadline))
                    .foregroundColor(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    line("\(outcome.playlistsAdded) playlists")
                    line("\(outcome.favoritesAdded) favourites")
                    line("\(outcome.serversAdded) servers restored")
                    if outcome.serversAdded > 0 {
                        Text("Servers need their password entered again — passwords stay in the Keychain and never travel in a file.")
                            .font(.system(.caption2))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }

            // The honest part: what this phone is still missing.
            if !outcome.missingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(outcome.missingFiles.count) files aren't on this iPhone yet")
                        .font(.system(.subheadline).weight(.semibold))
                        .foregroundColor(Theme.warning)
                    ForEach(outcome.missingFiles.prefix(8), id: \.self) { name in
                        Text(name)
                            .font(.system(.caption2).monospaced())
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    if outcome.missingFiles.count > 8 {
                        Text("and \(outcome.missingFiles.count - 8) more")
                            .font(.system(.caption2))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Text("Import them and they'll rejoin your playlists automatically.")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.top, Space.s)
            }
        }
    }

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(.subheadline).monospacedDigit())
            .foregroundColor(Theme.textPrimary)
    }
}

/// `sheet(item:)` needs identity; a bare URL has none.
private struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}
