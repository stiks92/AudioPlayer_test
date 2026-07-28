//
//  ConnectServerView.swift
//  Sonava
//
//  Manage self-hosted Subsonic-compatible servers (Navidrome, Airsonic…).
//  One connection is free; several — and searching them all at once — is Pro.
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
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.screenMargin) {
                        if serverStore.servers.isEmpty {
                            emptyState
                        } else {
                            serverList
                        }
                        addButton
                        infoNote
                    }
                    .padding(Space.screenMargin)
                }
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

    // MARK: - List

    private var serverList: some View {
        VStack(spacing: 0) {
            ForEach(Array(serverStore.servers.enumerated()), id: \.element.id) { index, connection in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: Theme.hairlineWidth)
                        .padding(.leading, Space.textRail)
                }
                row(connection)
            }
        }
        .padding(.horizontal, Space.l)
        .card(cornerRadius: Radius.card)
    }

    private func row(_ connection: ServerConnection) -> some View {
        let active = serverStore.activeID == connection.id
        let locked = !serverStore.isUsable(connection)
        return HStack(spacing: Space.l) {
            Image(systemName: locked ? "lock.fill" : (active ? "checkmark.circle.fill" : "circle"))
                .font(.system(.body))
                .foregroundColor(locked ? Theme.textTertiary : (active ? Theme.positive : Theme.textTertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundColor(locked ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Text(connection.username)
                    .font(.system(.caption))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                pendingRemoval = connection
            } label: {
                Image(systemName: "trash")
                    .font(.system(.footnote))
                    .foregroundColor(Theme.destructive)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .identified("server.remove", label: "Remove server")
        }
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
        .onTapGesture {
            if locked {
                showPaywall = true
            } else {
                serverStore.select(connection)
                Haptics.selection()
            }
        }
        // No identifier on the row itself: giving a container one makes it a
        // single accessibility element, which would swallow the delete button
        // inside it — for VoiceOver as well as for the tests.
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
            .foregroundColor(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
        .identified("server.add", label: "Add server")
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
