//
//  CloudBrowseView.swift
//  Sonava
//
//  Walking a cloud drive's folders, and connecting one in the first place.
//
//  A file browser, not a library: the listener organised these folders
//  themselves and knows where things are, so the screen's job is to get out
//  of the way and let them walk. Tapping a track plays the folder as a queue,
//  which is what a folder of music is.
//

import SwiftUI

struct CloudBrowseView: View {
    @EnvironmentObject private var cloudStore: CloudStore
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var proStore: ProStore

    @State private var showConnect = false

    var body: some View {
        Group {
            if let drive = cloudStore.usableDrives.first {
                CloudFolderView(drive: drive, path: drive.rootPath)
            } else {
                notConnected
            }
        }
        .sheet(isPresented: $showConnect) {
            ConnectCloudView().environmentObject(cloudStore).environmentObject(proStore)
        }
    }

    private var notConnected: some View {
        VStack(spacing: Space.l) {
            SonavaIcon(glyph: .download, size: 52, tint: Theme.textTertiary)
            Text("No cloud drive connected")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text("Yandex.Disk, Mail.ru Cloud, Nextcloud or any NAS that speaks WebDAV. Your files stay yours — Sonava just plays them.")
                .font(.subheadline)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
            Button {
                Haptics.impact()
                showConnect = true
            } label: {
                Text("Connect a drive").padding(.horizontal, Space.xl)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(expands: false))
            .accessibilityIdentifier("cloud.connect")
        }
        .frame(maxWidth: .infinity)
        .centredEmptyState()
    }
}

// MARK: - One folder

struct CloudFolderView: View {
    let drive: CloudDrive
    let path: String

    @EnvironmentObject private var cloudStore: CloudStore
    @EnvironmentObject private var audio: AudioManager

    @State private var entries: [WebDAVService.Entry] = []
    @State private var isLoading = true
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if isLoading && entries.isEmpty {
                HStack(spacing: Space.m) {
                    AnimatedIcon(glyph: .loading, mode: .loop(true), size: 20, tint: Theme.accentSoft)
                    Text("Reading the folder…")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
            } else if let failure {
                VStack(spacing: Space.m) {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(QuietButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
            } else if entries.isEmpty {
                Text("This folder is empty.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
            } else {
                rows
            }
        }
        .task { await load() }
    }

    private var tracks: [Song] {
        guard let service = cloudStore.service(for: drive) else { return [] }
        return entries.compactMap { service.song(from: $0, libraryID: drive.id) }
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        CloudFolderView(drive: drive, path: entry.path)
                            .navigationTitle(entry.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        folderRow(entry)
                    }
                    .buttonStyle(.plain)
                } else if entry.isAudio {
                    Button {
                        let queue = tracks
                        if let song = queue.first(where: { $0.id.hasSuffix(entry.path) }) {
                            audio.play(song, in: queue)
                        }
                    } label: {
                        fileRow(entry)
                    }
                    .buttonStyle(.plain)
                }
                // Anything else — a cover, a cue sheet, a text file — is
                // simply not shown. A music browser listing `folder.jpg` is
                // noise the listener has to read past on every screen.
            }
        }
    }

    private func folderRow(_ entry: WebDAVService.Entry) -> some View {
        HStack(spacing: Space.l) {
            SonavaIcon(glyph: .library, size: 20, tint: Theme.accentSoft)
                .frame(width: Space.iconColumn, height: Space.iconColumn)
            Text(entry.name)
                .font(.sonavaRowTitle)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            SonavaIcon(glyph: .chevronRight, size: 13, tint: Theme.textTertiary)
        }
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }

    private func fileRow(_ entry: WebDAVService.Entry) -> some View {
        HStack(spacing: Space.l) {
            SonavaIcon(glyph: .note, size: 18, tint: Theme.textSecondary)
                .frame(width: Space.iconColumn, height: Space.iconColumn)
            VStack(alignment: .leading, spacing: 2) {
                Text((entry.name as NSString).deletingPathExtension)
                    .font(.sonavaRowTitle)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if let size = entry.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.sonavaRowMeta)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let service = cloudStore.service(for: drive) else {
            failure = String(localized: "Couldn't reach the drive. Check the address and your network.")
            isLoading = false
            return
        }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            entries = try await service.list(path: path)
        } catch let error as WebDAVError {
            failure = error.message
        } catch {
            failure = WebDAVError.unreachable.message
        }
    }
}

// MARK: - Connecting

struct ConnectCloudView: View {
    @EnvironmentObject private var cloudStore: CloudStore
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: WebDAVService.Provider = .yandex
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPaywall = false

    private var canConnect: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && (provider != .other || !address.trimmingCharacters(in: .whitespaces).isEmpty)
            && !cloudStore.isConnecting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        SegmentedControl(
                            segments: WebDAVService.Provider.allCases.map {
                                .init(value: $0, title: $0.title, identifier: "cloud.provider.\($0.rawValue)")
                            },
                            selection: $provider)

                        Text(provider.hint)
                            .font(.system(.footnote))
                            .foregroundColor(Theme.textTertiary)

                        if provider == .other {
                            field("Address", text: $address, secure: false)
                        }
                        field("Username", text: $username, secure: false)
                        field("App password", text: $password, secure: true)

                        if let error = cloudStore.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(Theme.error)
                        }

                        Button {
                            // The second drive is Pro. This used to fall
                            // through to the store's guard, which could only
                            // answer with an inline error — the one gate in
                            // the app with no road to the paywall. Now the
                            // button takes the `ConnectServerView` route.
                            if cloudStore.canAddDrive {
                                Task {
                                    if await cloudStore.add(provider: provider, urlString: address,
                                                            username: username, password: password) {
                                        dismiss()
                                    }
                                }
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            HStack {
                                if cloudStore.isConnecting {
                                    AnimatedIcon(glyph: .loading, mode: .loop(true),
                                                 size: 20, tint: Theme.background)
                                } else if !cloudStore.canAddDrive {
                                    SonavaIcon(glyph: .lock, size: 16, tint: Theme.background)
                                }
                                Text(cloudStore.isConnecting ? "Connecting…" : "Connect")
                            }
                        }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                        .disabled(!canConnect)
                        .accessibilityIdentifier("cloud.submit")

                        if !cloudStore.canAddDrive {
                            // The store's own sentence, shown *before* the
                            // listener types credentials that can't be saved.
                            Text("Connecting more than one drive needs Sonava Pro.")
                                .font(.footnote)
                                .foregroundColor(Theme.textTertiary)
                        }

                        Text("Your password is kept in the iPhone's Keychain and never leaves it — not in a backup, not in a shared link.")
                            .font(.system(.caption2))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(Space.screenMargin)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Connect a drive")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption2).weight(.bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundColor(.white)
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .card(cornerRadius: Radius.control)
        }
    }
}
