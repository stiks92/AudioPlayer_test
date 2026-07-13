//
//  SettingsView.swift
//  AudioPlayer_test
//
//  Settings: Aurora Pro, playback, sources and support.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var proStore: ProStore
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var serverStore: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var showSleepOptions = false
    @State private var showConnectServer = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Aurora \(v)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        proCard
                        playbackSection
                        sourcesSection
                        supportSection
                        Text(version)
                            .font(.footnote)
                            .foregroundColor(Theme.textTertiary)
                            .padding(.top, 6)
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
            .sheet(isPresented: $showConnectServer) {
                ConnectServerView().environmentObject(serverStore)
            }
            .confirmationDialog("Sleep timer", isPresented: $showSleepOptions, titleVisibility: .visible) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { audio.setSleepTimer(minutes: minutes) }
                }
                Button("Turn off", role: .destructive) { audio.setSleepTimer(minutes: nil) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pro

    @ViewBuilder
    private var proCard: some View {
        if proStore.isPro {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Pro").font(.system(size: 17, weight: .bold))
                    Text("Active — thank you for your support!")
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(18)
            .background(
                LinearGradient(colors: [Theme.accent, Color(hex: 0x4A00E0)], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock Aurora Pro").font(.system(size: 17, weight: .bold))
                        Text("AI Mix · all sources · EQ · offline")
                            .font(.caption).foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.8))
                }
                .padding(18)
                .background(
                    LinearGradient(colors: [Theme.accent, Color(hex: 0xFF6FD8), Color(hex: 0x4A00E0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.98))
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        section("Playback") {
            row(icon: "moon.zzz.fill", title: "Sleep timer",
                value: audio.sleepTimerMinutes.map { "\($0) min" } ?? "Off") {
                showSleepOptions = true
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        section("Sources") {
            VStack(spacing: 0) {
                staticRow(icon: "waveform", title: "Audius", value: "Connected", valueColor: Color(hex: 0x38EF7D))
                divider
                staticRow(icon: "dot.radiowaves.left.and.right", title: "Internet Radio", value: "Connected", valueColor: Color(hex: 0x38EF7D))
                divider
                row(icon: "server.rack", title: "Self-hosted (Subsonic)",
                    value: serverStore.isConnected ? (serverStore.host ?? "Connected") : "Connect") {
                    showConnectServer = true
                }
                divider
                staticRow(icon: "music.note.list", title: "Spotify / Apple Music", value: "Soon", valueColor: Theme.textTertiary)
            }
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        section("Support") {
            VStack(spacing: 0) {
                row(icon: "arrow.clockwise", title: "Restore purchases", value: "") {
                    Task { await proStore.restore() }
                }
                divider
                staticRow(icon: "lock.shield", title: "Privacy", value: "On-device", valueColor: Theme.textSecondary)
                #if DEBUG
                divider
                Toggle(isOn: Binding(
                    get: { proStore.developerOverride },
                    set: { proStore.setDeveloperOverride($0) }
                )) {
                    Label("Developer: unlock Pro", systemImage: "hammer")
                        .font(.system(size: 15))
                }
                .tint(Theme.accent)
                .padding(.vertical, 12)
                #endif
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .glass(cornerRadius: 18)
        }
    }

    private func row(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24).foregroundColor(Theme.accentSoft)
                Text(title).font(.system(size: 15))
                Spacer()
                if !value.isEmpty {
                    Text(value).font(.system(size: 14)).foregroundColor(Theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func staticRow(icon: String, title: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 24).foregroundColor(Theme.accentSoft)
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(valueColor)
        }
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }
}
