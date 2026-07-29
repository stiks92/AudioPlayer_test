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
                    VStack(spacing: Space.xl) {
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
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
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
            .padding(Space.l)
            .background(Theme.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: Space.l) {
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
                .padding(Space.l)
                .background(Theme.proGradient)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.98))
        }
    }

    // MARK: - Appearance (theme palettes)

    private var appearanceSection: some View {
        section("Appearance") {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Accent")
                        .font(.system(.footnote).weight(.semibold))
                    // Six across, not a scroller.
                    //
                    // Three rounds tried to make a horizontal scroller behave
                    // inside a clipping card: it sliced the sixth swatch
                    // against the card's own border, and a fade mask erased it
                    // outright. The scrolling was never the point — there are
                    // exactly six palettes and they fit. At six equal columns
                    // in the card's inner width nothing clips, nothing needs an
                    // affordance, and the paywall's promise of "six accent
                    // themes" is a thing you can count on the screen.
                    HStack(spacing: 0) {
                        ForEach(ThemePalette.all) { palette in
                            paletteSwatch(palette).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if appIcon.supportsAlternateIcons {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("App icon")
                            .font(.system(.footnote).weight(.semibold))
                        HStack(spacing: 0) {
                            ForEach(AppIconOption.all) { option in
                                iconSwatch(option).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 2)
                        if let error = appIcon.lastError {
                            Text(error).font(.footnote).foregroundColor(Theme.error)
                                // Identified so a test can tell "the system
                                // refused and we said so" apart from "the
                                // picker silently kept an icon that was never
                                // applied" — the second is the actual defect.
                                .accessibilityIdentifier("icon.error")
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
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(LinearGradient(colors: option.gradientHex.colors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: Swatch.size, height: Swatch.size)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(selected ? Color.white : Color.white.opacity(0.15),
                                              lineWidth: selected ? 3 : 1)
                        )
                    HStack(spacing: 2.5) {
                        ForEach([0.34, 0.62, 1.0, 0.70, 0.44], id: \.self) { height in
                            Capsule()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: Swatch.size * 0.107, height: Swatch.size * 0.54 * height)
                        }
                    }
                    if locked {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: Swatch.size, height: Swatch.size)
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
                        .frame(width: Swatch.size, height: Swatch.size)
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
            // `Label` sizes its own icon column, so this row's text started
            // 8pt left of every other row in the card — a visible step in the
            // card's left edge. It uses the same leading column as `row()`.
            Toggle(isOn: $audio.autoExtendEnabled) {
                HStack(spacing: Space.iconGap) {
                    Image(systemName: "infinity")
                        .font(.sonavaRowTitle)
                        .frame(width: Space.iconColumn, height: Space.iconColumn)
                        .foregroundColor(Theme.textSecondary)
                    Text("Endless playback").font(.system(.subheadline))
                }
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
                    HStack(spacing: Space.iconGap) {
                        Image(systemName: "hammer")
                            .font(.sonavaRowTitle)
                            .frame(width: Space.iconColumn, height: Space.iconColumn)
                            .foregroundColor(Theme.textSecondary)
                        Text("Developer: unlock Pro").font(.system(.subheadline))
                    }
                }
                .tint(Theme.accent)
                .padding(.vertical, Space.m)
                #endif
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption).weight(.bold))
                .tracking(1)
                .foregroundColor(Theme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, Space.l)
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
            HStack(spacing: Space.l) {
                Image(systemName: icon)
                    .font(.sonavaRowTitle)
                    .frame(width: Space.iconColumn, height: Space.iconColumn)
                    .foregroundColor(Theme.textSecondary)
                Text(title).font(.system(.subheadline))
                Spacer()
                if let value {
                    Text(value).font(.system(.footnote)).foregroundColor(Theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.system(.caption)).foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, Space.m)
            .frame(minHeight: Space.hitTarget)
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
        HStack(spacing: Space.l) {
            Image(systemName: icon)
                    .font(.sonavaRowTitle)
                    .frame(width: Space.iconColumn, height: Space.iconColumn)
                    .foregroundColor(Theme.textSecondary)
            Text(title).font(.system(.subheadline))
            Spacer()
            Text(value).font(.system(.footnote).weight(.semibold)).foregroundColor(valueColor)
        }
        .padding(.vertical, Space.m)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: Theme.hairlineWidth)
            .padding(.leading, Space.textRail)
    }
}
