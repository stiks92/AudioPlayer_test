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
    @EnvironmentObject private var scrobble: ScrobbleStore
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var appIcon = AppIconManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var showSleepOptions = false
    @State private var showConnectServer = false
    @State private var showEqualizer = false
    @State private var showScrobble = false

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
                        appearanceSection
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
                ConnectServerView()
                    .environmentObject(serverStore)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(effects: audio.effects)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showScrobble) {
                ConnectScrobbleView().environmentObject(scrobble)
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
            HStack(alignment: .top, spacing: Space.iconGap) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.title).weight(.bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sonava Pro").font(.system(.body).weight(.bold))
                    Text("Active — thank you for your support!")
                        .font(.caption).foregroundColor(.white)
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
                        .font(.system(.title).weight(.bold))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock Sonava Pro").font(.system(.body).weight(.bold))
                        Text("Offline · EQ · AI Mix · themes")
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

    // MARK: - Appearance (theme palettes)

    private var appearanceSection: some View {
        section("Appearance") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent")
                        .font(.system(.footnote).weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ThemePalette.all) { palette in
                                paletteSwatch(palette)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if appIcon.supportsAlternateIcons {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App icon")
                            .font(.system(.footnote).weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(AppIconOption.all) { option in
                                    iconSwatch(option)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        if let error = appIcon.lastError {
                            Text(error).font(.footnote).foregroundColor(Theme.error)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func iconSwatch(_ option: AppIconOption) -> some View {
        let selected = appIcon.current.id == option.id
        let locked = option.isPro && !proStore.isPro
        return Button {
            if locked {
                showPaywall = true
            } else {
                appIcon.select(option)
                Haptics.selection()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // A miniature of the real icon: same gradient, same mark.
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: option.gradientHex.colors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(selected ? Color.white : Color.white.opacity(0.15),
                                              lineWidth: selected ? 3 : 1)
                        )
                    HStack(spacing: 2.5) {
                        ForEach([0.34, 0.62, 1.0, 0.70, 0.44], id: \.self) { height in
                            Capsule()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: 5, height: 30 * height)
                        }
                    }
                    if locked {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 56, height: 56)
                        Image(systemName: "lock.fill")
                            .font(.system(.subheadline).weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                Text(LocalizedStringKey(option.name))
                    .font(.system(.caption2).weight(.medium))
                    .foregroundColor(selected ? Theme.textPrimary : Theme.textSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.9))
        .accessibilityIdentifier("icon.\(option.id)")
        // The active choice is shown only by a border, which says nothing to
        // VoiceOver — and nothing to a test either.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func paletteSwatch(_ palette: ThemePalette) -> some View {
        let selected = theme.palette.id == palette.id
        let locked = palette.isPro && !proStore.isPro
        return Button {
            if locked {
                showPaywall = true
            } else {
                theme.select(palette)
                Haptics.selection()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: palette.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().strokeBorder(selected ? Color.white : Color.white.opacity(0.15),
                                                  lineWidth: selected ? 3 : 1)
                        )
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(.subheadline).weight(.bold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    } else if selected {
                        Image(systemName: "checkmark")
                            .font(.system(.callout).weight(.bold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                Text(LocalizedStringKey(palette.name))
                    .font(.system(.caption2).weight(.medium))
                    .foregroundColor(selected ? Theme.textPrimary : Theme.textSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.9))
        .accessibilityIdentifier("palette.\(palette.id)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                    .font(.system(.subheadline))
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

    /// The self-hosted row shows the active host verbatim when we have one, and
    /// the count once several are connected. Interpolating keeps the parameter a
    /// `LocalizedStringKey`, so the static states still translate.
    private var selfHostedValue: LocalizedStringKey {
        guard serverStore.isConnected else { return "Connect" }
        if serverStore.servers.count > 1 { return "\(serverStore.servers.count) servers" }
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
                row(icon: "waveform.badge.magnifyingglass", title: "Scrobble to ListenBrainz",
                    value: scrobbleValue) {
                    if proStore.isPro { showScrobble = true } else { showPaywall = true }
                }
                divider
                staticRow(icon: "music.note.list", title: "Spotify / Apple Music",
                          value: "Soon", valueColor: Theme.textTertiary)
            }
        }
    }

    private var scrobbleValue: LocalizedStringKey {
        scrobble.isConnected ? (scrobble.isEnabled ? "On" : "Paused") : "Connect"
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
                        .font(.system(.subheadline))
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
                .font(.system(.caption).weight(.bold))
                .tracking(1)
                .foregroundColor(Theme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .card(cornerRadius: Radius.card)
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
                Text(title).font(.system(.subheadline))
                Spacer()
                if let value {
                    Text(value).font(.system(.footnote)).foregroundColor(Theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.system(.caption)).foregroundColor(Theme.textTertiary)
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
            Text(title).font(.system(.subheadline))
            Spacer()
            Text(value).font(.system(.footnote).weight(.semibold)).foregroundColor(valueColor)
        }
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }
}
