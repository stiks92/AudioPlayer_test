//
//  ConnectScrobbleView.swift
//  Sonava
//
//  Connects a ListenBrainz account so plays are scrobbled. Users paste the
//  token from their ListenBrainz profile; it's validated and stored in the
//  Keychain.
//

import SwiftUI

struct ConnectScrobbleView: View {
    @EnvironmentObject private var scrobble: ScrobbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Space.l) {
                        header
                        if scrobble.isConnected {
                            connectedCard
                        } else {
                            form
                        }
                    }
                    .padding(Space.screenMargin)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Scrobbling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(Theme.accentSoft)
            Text("ListenBrainz")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Scrobble every play to your ListenBrainz history — the open, private alternative to Last.fm.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var connectedCard: some View {
        HStack(spacing: Space.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.title2)).foregroundColor(Theme.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected").font(.system(.callout).weight(.bold))
                Text("Plays are being scrobbled.")
                    .font(.caption).foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(Space.l)
        .card(cornerRadius: Radius.card)

        Toggle(isOn: $scrobble.isEnabled) {
            Label("Scrobble my plays", systemImage: "dot.radiowaves.up.forward")
                .font(.system(.subheadline))
        }
        .tint(Theme.accent)
        .padding(Space.l)
        .card(cornerRadius: Radius.card)

        Button(role: .destructive) {
            scrobble.disconnect()
        } label: {
            Text("Disconnect")
                .font(.headline).foregroundColor(Theme.destructive)
                .frame(maxWidth: .infinity).padding(.vertical, Space.l)
                .card(cornerRadius: Radius.hero)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    private var form: some View {
        VStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("User token")
                    .textCase(.uppercase)
                    .font(.system(.caption2).weight(.bold)).tracking(1)
                    .foregroundColor(Theme.textTertiary)
                SecureField("Paste your ListenBrainz token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    .card(cornerRadius: Radius.control)
            }

            if let error = scrobble.lastError {
                Text(error)
                    .font(.footnote).foregroundColor(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { _ = await scrobble.connect(token: token) }
            } label: {
                HStack {
                    if scrobble.isConnecting { ProgressView().tint(Theme.background) }
                    Text(scrobble.isConnecting ? "Connecting…" : "Connect")
                        .font(.headline)
                }
                .foregroundColor(Theme.background)
                .frame(maxWidth: .infinity).padding(.vertical, Space.l)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.97))
            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || scrobble.isConnecting)

            Text("Find your token on listenbrainz.org → Settings. It's stored only in your device's Keychain.")
                .font(.system(.caption2))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
