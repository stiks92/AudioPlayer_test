//
//  SettingsView.swift
//  Sonava
//
//  Settings: Sonava Pro, playback, sources and support.
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
    @State private var showEqualizer = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Sonava \(short)"
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
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(effects: audio.effects)
                    .environmentObject(proStore)
            }
            .confirmationDialog("Sleep timer", isPresented: $showSleepOptions, titleVisibility: .visible) {
                ForEach(Self.sleepTimerChoices, id: \.self) { minutes in
                    Button("\(minutes) min") { audio.setSleepTimer(minutes: minutes) }
                }
                Button("Turn off", role: .destructive) { audio.setSleepTimer(minutes: nil) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private static let sleepTimerChoices = [15, 30, 45, 60]

    // MARK: - Pro

    @ViewBuilder
    private var proCard: some View {
        if proStore.isPro {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sonava Pro").font(.system(size: 17, weight: .bold))
                    Text("Active — thank you for your support!")
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(18)
            .background(Theme.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock Sonava Pro").font(.system(size: 17, weight: .bold))
                        Text("AI Mix · all sources · EQ · offline")
                            .font(.caption).foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.8))
                }
                .padding(18)
                .background(Theme.proGradient)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.98))
        }
    }

    // MARK: - Playback

    private var sleepTimerValue: LocalizedStringKey {
        guard let minutes = audio.sleepTimerMinutes else { return "Off" }
        return "\(minutes) min"
    }

    private var playbackSection: some View {
        section("Playback") {
            row(icon: "slider.vertical.3", title: "Equalizer", value: equalizerValue) {
                showEqualizer = true
            }
            divider
            row(icon: "moon.zzz.fill", title: "Sleep timer", value: sleepTimerValue) {
                showSleepOptions = true
            }
            divider
            Toggle(isOn: $audio.autoExtendEnabled) {
                Label("Endless playback", systemImage: "infinity")
                    .font(.system(size: 15))
            }
            .tint(Theme.accent)
            .padding(.vertical, 6)
        }
    }

    private var equalizerValue: LocalizedStringKey {
        guard audio.effects.equalizer.isEnabled else { return "Off" }
        return audio.effects.selectedPreset.map { LocalizedStringKey($0.name) } ?? "Custom"
    }

    // MARK: - Sources

    /// The self-hosted row shows the connected host verbatim when we have one.
    /// Interpolating it keeps the parameter a `LocalizedStringKey` so the two
    /// static states ("Connect" / "Connected") still translate.
    private var selfHostedValue: LocalizedStringKey {
        guard serverStore.isConnected else { return "Connect" }
        guard let host = serverStore.host else { return "Connected" }
        return "\(host)"
    }

    private var sourcesSection: some View {
        section("Sources") {
            VStack(spacing: 0) {
                staticRow(icon: "waveform", title: "Audius",
                          value: "Connected", valueColor: Theme.positive)
                divider
                staticRow(icon: "dot.radiowaves.left.and.right", title: "Internet Radio",
                          value: "Connected", valueColor: Theme.positive)
                divider
                row(icon: "server.rack", title: "Self-hosted (Subsonic)", value: selfHostedValue) {
                    showConnectServer = true
                }
                divider
                staticRow(icon: "music.note.list", title: "Spotify / Apple Music",
                          value: "Soon", valueColor: Theme.textTertiary)
            }
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        section("Support") {
            VStack(spacing: 0) {
                row(icon: "arrow.clockwise", title: "Restore purchases", value: nil) {
                    Task { await proStore.restore() }
                }
                divider
                staticRow(icon: "lock.shield", title: "Privacy",
                          value: "On-device", valueColor: Theme.textSecondary)
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

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .glass(cornerRadius: 18)
        }
    }

    private func row(
        icon: String,
        title: LocalizedStringKey,
        value: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24).foregroundColor(Theme.accentSoft)
                Text(title).font(.system(size: 15))
                Spacer()
                if let value {
                    Text(value).font(.system(size: 14)).foregroundColor(Theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func staticRow(
        icon: String,
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        valueColor: Color
    ) -> some View {
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
