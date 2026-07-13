//
//  ConnectServerView.swift
//  AudioPlayer_test
//
//  Connect a self-hosted Subsonic-compatible server (Navidrome, Airsonic…).
//

import SwiftUI

struct ConnectServerView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if serverStore.isConnected {
                            connectedCard
                        } else {
                            form
                        }
                        infoNote
                    }
                    .padding(20)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Self-hosted server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: 0x38EF7D))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected").font(.system(size: 16, weight: .bold))
                    Text(serverStore.host ?? "Your server")
                        .font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            Button(role: .destructive) {
                serverStore.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(hex: 0xFF3B6B))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glass(cornerRadius: 14)
            }
        }
        .padding(18)
        .glass(cornerRadius: 20)
    }

    private var form: some View {
        VStack(spacing: 14) {
            field("Server URL", text: $urlString, placeholder: "https://music.example.com", keyboard: .URL)
            field("Username", text: $username, placeholder: "username")
            secureField("Password", text: $password)

            if let error = serverStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(Color(hex: 0xFF6B8A))
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
                .padding(.vertical, 15)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.97))
            .disabled(!canConnect || isConnecting)
            .opacity(canConnect ? 1 : 0.5)
        }
    }

    private var infoNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Works with Navidrome, Airsonic, Gonic and any Subsonic-compatible server.", systemImage: "info.circle")
            Label("Your password is stored securely in the Keychain and only used to sign requests to your server.", systemImage: "lock.shield")
        }
        .font(.footnote)
        .foregroundColor(Theme.textTertiary)
        .padding(.top, 8)
    }

    private var canConnect: Bool {
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func connect() {
        isConnecting = true
        Task {
            let ok = await serverStore.connect(urlString: urlString, username: username, password: password)
            isConnecting = false
            if ok { dismiss() }
        }
    }

    // MARK: - Field builders

    private func field(_ title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glass(cornerRadius: 12)
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            SecureField("••••••••", text: text)
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glass(cornerRadius: 12)
        }
    }
}
