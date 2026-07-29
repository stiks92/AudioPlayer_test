//
//  ConnectServerView.swift
//  Sonava
//
//  Manage self-hosted Subsonic-compatible servers (Navidrome, Airsonic…).
//  One connection is free; several — and searching them all at once — is Pro.
//
//  A design review named what was wrong with this screen better than a list of
//  fixes would have: it was three rows saying "listener" and three delete
//  buttons. Everything a self-hoster navigates by — which box, is it up, how
//  big is the library, when did we last talk to it — was known to the app and
//  shown to nobody, while the one thing that was prominent was the button that
//  destroys a connection.
//
//  So it is a rack now. Each row states its host, its measured reachability and
//  what the server itself reports having indexed; the active connection is
//  marked by a rail you can see from across the room rather than by a tick in a
//  column of ticks. Removal moved behind a swipe, where destructive actions
//  belong.
//
//  Nothing on the row is inferred. `ServerHealth` fields are either measured or
//  absent, and an absent one draws nothing — this is the screen that has to
//  make somebody trust their own infrastructure, and a plausible invented
//  number would be exactly the wrong thing to put on it.
//

import SwiftUI
import UIKit

struct ConnectServerView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddServer = false
    @State private var showPaywall = false
    @State private var pendingRemoval: ServerConnection?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                rack
            }
            .foregroundColor(.white)
            .navigationTitle("Self-hosted servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView().environmentObject(serverStore)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
            // An alert rather than a confirmation dialog: inside a sheet the
            // latter is presented as a popover, whose only way out is tapping
            // outside. A destructive action deserves an explicit Cancel.
            .alert(
                "Remove this server?",
                isPresented: Binding(get: { pendingRemoval != nil },
                                     set: { if !$0 { pendingRemoval = nil } })
            ) {
                Button("Remove", role: .destructive) {
                    if let pendingRemoval { serverStore.remove(pendingRemoval) }
                    pendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text("Your music stays on your server. Only this connection is forgotten.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - The rack

    /// A `List` rather than the previous `ScrollView`, for one reason: swipe to
    /// delete. Three always-armed trash cans put the destructive action at the
    /// same prominence as the connection itself, on a screen whose subject is
    /// which library is playing.
    private var rack: some View {
        List {
            if serverStore.servers.isEmpty {
                emptyState.rackRow()
            } else {
                ForEach(serverStore.servers) { connection in
                    row(connection)
                        .rackRow()
                        // `allowsFullSwipe` off deliberately: a flick that
                        // removes a saved credential with no landing point is
                        // the wrong amount of ceremony for this.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingRemoval = connection
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .identified("server.remove", label: "Remove server")
                        }
                }
            }
            addButton.rackRow()
            infoNote.rackRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        // Pull to re-probe: the natural gesture for "is it back yet" on a
        // screen whose whole point is the state of somebody's own network.
        .refreshable { await serverStore.refreshHealth() }
        .task { await serverStore.refreshHealth() }
    }

    private func row(_ connection: ServerConnection) -> some View {
        let active = serverStore.activeID == connection.id
        let locked = !serverStore.isUsable(connection)
        let health = serverStore.health(for: connection)

        return HStack(spacing: 0) {
            // The active connection gets a rail, not a tick. On a screen about
            // hardware, "which box am I listening to" should survive being
            // glanced at, and a checkmark in a column of circles does not.
            Capsule()
                .fill(active ? Theme.accentSoft : Color.clear)
                .frame(width: 3)
                .padding(.vertical, Space.m)
                .padding(.leading, Space.s)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(connection.displayName)
                        .font(.sonavaCardTitle)
                        .foregroundColor(locked ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s)
                    if locked {
                        Label("Pro", systemImage: "lock.fill")
                            .font(.system(.caption).weight(.semibold))
                            .foregroundColor(Theme.accentSoft)
                    } else {
                        StatusBadge(state: health.state)
                    }
                }

                HStack(spacing: Space.xs) {
                    // Stated, not assumed. A plain-http box on a LAN is a
                    // legitimate setup, and drawing a padlock over it would be
                    // a lie about the user's own network.
                    Image(systemName: connection.isSecure ? "lock.fill" : "lock.open.fill")
                        .font(.system(.caption2))
                        .foregroundColor(connection.isSecure ? Theme.textTertiary : Theme.live)
                    Text(connection.host)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                metaLine(connection, health)
            }
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(active ? Theme.surfaceElevated : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(active ? Theme.accentSoft.opacity(0.5) : Theme.hairline,
                              lineWidth: active ? 1.5 : Theme.hairlineWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            if locked {
                showPaywall = true
            } else if !active {
                withAnimation(Motion.standard) { serverStore.select(connection) }
                Haptics.selection()
            }
        }
        // No identifier on the row itself: giving a container one makes it a
        // single accessibility element, which would swallow the host and status
        // inside it — for VoiceOver as well as for the tests.
    }

    /// Facts about the connection, each one omitted rather than guessed.
    ///
    /// Rendered as symbol-and-number pairs instead of a sentence, which keeps
    /// it to one line at any text size and sidesteps plural agreement — "12 431
    /// файлов" versus "12 432 файла" is a category of bug this screen does not
    /// need. VoiceOver gets the words spelled out instead.
    private func metaLine(_ connection: ServerConnection, _ health: ServerHealth) -> some View {
        HStack(spacing: Space.m) {
            fact("person", connection.username)
            if let files = health.files {
                fact("music.note", files.formatted(.number))
            }
            if let latency = health.latency {
                fact("bolt", "\(Int((latency * 1000).rounded())) ms")
            }
        }
        .font(.sonavaRowMeta.monospacedDigit())
        .foregroundColor(Theme.textTertiary)
        .lineLimit(1)
        .accessibilityElement()
        .accessibilityLabel(metaDescription(connection, health))
    }

    private func fact(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: symbol).font(.system(.caption2))
            Text(value)
        }
    }

    private func metaDescription(_ connection: ServerConnection, _ health: ServerHealth) -> Text {
        var text = Text("Signed in as \(connection.username)")
        if let files = health.files {
            text = text + Text(", ") + Text("indexed files: \(files.formatted(.number))")
        }
        if let latency = health.latency {
            text = text + Text(", ") + Text("response \(Int((latency * 1000).rounded())) milliseconds")
        }
        return text
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No server connected")
                .font(.system(.body).weight(.bold))
            Text("Stream your own library straight from Navidrome, Airsonic or any Subsonic-compatible server.")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
    }

    // MARK: - Add

    private var addButton: some View {
        Button {
            if serverStore.canAddServer {
                showAddServer = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: serverStore.canAddServer ? "plus.circle.fill" : "lock.fill")
                Text(serverStore.servers.isEmpty ? "Connect a server" : "Add another server")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            // Was a pure-white capsule: the loudest object on a screen whose
            // actual subject is which server is active. Tint belongs to the
            // call to action, and white belongs to the purchase.
            .background(Capsule().fill(Theme.accent.mix(with: Theme.background, by: 0.12)))
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
        .identified("server.add", label: "Add server")
        .padding(.top, Space.m)
    }

    private var infoNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Works with Navidrome, Airsonic, Gonic and any Subsonic-compatible server.", systemImage: "info.circle")
            Label("Your password is stored securely in the Keychain and only used to sign requests to your server.", systemImage: "lock.shield")
            if !proStore.isPro {
                Label("Sonava Pro connects unlimited servers and searches them all at once.", systemImage: "sparkles")
            }
        }
        .font(.footnote)
        .foregroundColor(Theme.textTertiary)
        .padding(.top, 8)
    }
}

// MARK: - Status

/// Measured reachability, stated in a word and a dot.
///
/// The unreachable colour is `live` (amber), not `destructive` (red): a server
/// that is off or off-network is a fact about the house, not an error the
/// listener made, and colouring it like a failure invites them to go looking
/// for a bug in the app.
private struct StatusBadge: View {
    let state: ServerHealth.State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(colour)
                .frame(width: 7, height: 7)
                .opacity(state == .checking && pulsing ? 0.25 : 1)
            Text(title)
                .font(.system(.caption).weight(.semibold))
                .foregroundColor(colour)
        }
        .onAppear {
            guard state == .checking, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
    }

    private var title: LocalizedStringKey {
        switch state {
        case .unknown: "Not checked"
        case .checking: "Checking…"
        case .online: "Online"
        case .unreachable: "Unreachable"
        }
    }

    private var colour: Color {
        switch state {
        case .unknown, .checking: Theme.textTertiary
        case .online: Theme.positive
        case .unreachable: Theme.live
        }
    }
}

private extension View {
    /// A list row carrying no list chrome — the cards do their own drawing.
    func rackRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.screenMargin,
                                      bottom: Space.xs, trailing: Space.screenMargin))
    }
}

// MARK: - Add a server

struct AddServerView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var username = ""
    @State private var password = ""
    @State private var label = ""
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Space.l) {
                        field("Server URL", text: $urlString,
                              placeholder: "https://music.example.com", keyboard: .URL)
                        field("Username", text: $username, placeholder: "Username")
                        secureField("Password", text: $password)
                        field("Name (optional)", text: $label, placeholder: "Home server")

                        if let error = serverStore.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(Theme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: connect) {
                            HStack {
                                if isConnecting { ProgressView().tint(Theme.background) }
                                Text(isConnecting ? "Connecting…" : "Connect")
                                    .font(.headline)
                            }
                            .foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.l)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.97))
                        .disabled(!canConnect || isConnecting)
                        .opacity(canConnect ? 1 : 0.5)
                        .identified("server.connect", label: "Connect")
                    }
                    .padding(Space.screenMargin)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Add server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canConnect: Bool {
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func connect() {
        isConnecting = true
        Task {
            let ok = await serverStore.add(urlString: urlString, username: username,
                                           password: password, label: label)
            isConnecting = false
            if ok { dismiss() }
        }
    }

    // MARK: - Field builders

    private func field(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption2).weight(.bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .card(cornerRadius: Radius.control)
        }
    }

    private func secureField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption2).weight(.bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            SecureField("••••••••", text: text)
                .foregroundColor(.white)
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .card(cornerRadius: Radius.control)
        }
    }
}
