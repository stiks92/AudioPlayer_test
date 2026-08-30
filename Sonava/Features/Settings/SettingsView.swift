//
//  SettingsView.swift
//  Sonava
//
//  Settings: Sonava Pro, playback, sources and support.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var journeyStore: JourneyStore
    @ObservedObject private var appleMusic = AppleMusicService.shared
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var scrobble: ScrobbleStore
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var cloudStore: CloudStore
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var appIcon = AppIconManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var showSleepOptions = false
    @State private var mondayMixReminder = UserDefaults.standard.bool(forKey: MondayMix.reminderDefaultsKey)
    @State private var showCorrection = false
    @State private var showHistoryImport = false
    @State private var showSourcesHub = false
    @State private var showConnectServer = false
    @State private var showEqualizer = false
    @State private var showScrobble = false
    @State private var showBackup = false

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
            .sheet(isPresented: $showSourcesHub) {
                SourcesHubView()
                    .environmentObject(library)
                    .environmentObject(serverStore)
                    .environmentObject(cloudStore)
                    .environmentObject(proStore)
                    .environmentObject(journeyStore)
                    .environmentObject(playlistStore)
                    .environmentObject(audio)
            }
            .sheet(isPresented: $showHistoryImport) {
                ImportHistoryView()
                    .environmentObject(journeyStore)
                    .environmentObject(library)
            }
            .sheet(isPresented: $showCorrection) {
                HeadphoneCorrectionView()
                    .environmentObject(audio)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(effects: audio.effects)
                    .environmentObject(proStore)
                    .environmentObject(audio)
            }
            .sheet(isPresented: $showScrobble) {
                ConnectScrobbleView().environmentObject(scrobble)
            }
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(library)
                    .environmentObject(playlistStore)
                    .environmentObject(serverStore)
                    .environmentObject(audio)
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
            // Quiet, like a paid-up receipt should be: no gradient shouting
            // about money already spent. The checkmark draws itself in on
            // appear — the one place the status earns a little motion.
            HStack(spacing: Space.l) {
                AnimatedIcon(glyph: .checkmark, mode: .toggle(true),
                             size: 22, tint: Theme.accentWarm)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sonava Pro")
                        .font(.system(.footnote).weight(.semibold))
                        .textCase(.uppercase).tracking(2.2)
                        .foregroundColor(Theme.accent)
                    Text("Active — thank you for your support!")
                        .font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, Space.m)
        } else {
            // The upsell keeps the app's one warm gradient — it is the door
            // to the paywall and allowed to look like one.
            Button { showPaywall = true } label: {
                HStack(spacing: Space.l) {
                    SonavaIcon(glyph: .aiMix, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock Sonava Pro").font(.system(.body).weight(.bold))
                        Text("Offline · Crate Mix · Pro sound · AI Mix")
                            .font(.caption).foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    SonavaIcon(glyph: .chevronRight, size: 16, tint: .white.opacity(0.8))
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
                    // A miniature of the real icon: the glow dissolving into
                    // near-black, the mark in its own tint.
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(RadialGradient(colors: option.gradientHex.colors,
                                             center: .center,
                                             startRadius: 0,
                                             endRadius: Swatch.size * 0.72))
                        .frame(width: Swatch.size, height: Swatch.size)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(selected ? Color.white : Color.white.opacity(0.15),
                                              lineWidth: selected ? 3 : 1)
                        )
                    HStack(spacing: 2.5) {
                        ForEach([0.34, 0.62, 1.0, 0.70, 0.44], id: \.self) { height in
                            Capsule()
                                .fill(Color(hex: option.markHex))
                                .frame(width: Swatch.size * 0.107, height: Swatch.size * 0.54 * height)
                        }
                    }
                    if locked {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: Swatch.size, height: Swatch.size)
                        SonavaIcon(glyph: .lock, size: 15)
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
                    // A flat disc of the accent itself, not a three-stop
                    // gradient blob: the swatch answers "what colour will my
                    // accents be", and a gradient answers a different
                    // question nothing in the app asks any more.
                    Circle()
                        .fill(palette.accentColor)
                        .frame(width: Swatch.size, height: Swatch.size)
                        .overlay(
                            Circle().strokeBorder(selected ? Color.white : Color.white.opacity(0.15),
                                                  lineWidth: selected ? 3 : 1)
                        )
                    if locked {
                        SonavaIcon(glyph: .lock, size: 14, tint: .black.opacity(0.75))
                    } else if selected {
                        AnimatedIcon(glyph: .checkmark, mode: .toggle(true),
                                     size: 15, tint: .black.opacity(0.8))
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
            row(icon: .equalizer, title: "Equalizer", value: equalizerValue) {
                showEqualizer = true
            }
            divider
            // Pro since the paid zone widened; the badge says so at the door,
            // the way the AI Mix card does on Home. The value column would
            // read "Off" to a free user — technically true, but it implies a
            // switch they could flip, so the badge replaces it.
            row(icon: .wave, title: "Headphone correction",
                value: proStore.isPro ? correctionValue : nil,
                showsProBadge: !proStore.isPro) {
                showCorrection = true
            }
            divider
            row(icon: .sleep, title: "Sleep timer", value: sleepTimerValue) {
                showSleepOptions = true
            }
            divider
            // `Label` sizes its own icon column, so this row's text started
            // 8pt left of every other row in the card — a visible step in the
            // card's left edge. It uses the same leading column as `row()`.
            Toggle(isOn: $audio.autoExtendEnabled) {
                HStack(spacing: Space.iconGap) {
                    SonavaIcon(glyph: .infinity, size: 20, tint: Theme.textSecondary)
                        .frame(width: Space.iconColumn, height: Space.iconColumn)
                    Text("Endless playback").font(.system(.subheadline))
                }
            }
            .tint(Theme.accentDeep)   // ivory knob on ivory track vanished; umber keeps the knob visible
            .padding(.vertical, 6)
            divider
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: mondayMixBinding) {
                    HStack(spacing: Space.iconGap) {
                        SonavaIcon(glyph: .note, size: 20, tint: Theme.textSecondary)
                            .frame(width: Space.iconColumn, height: Space.iconColumn)
                        Text("Monday Mix reminder").font(.system(.subheadline))
                    }
                }
                .tint(Theme.accentDeep)
                Text("A fresh weekly mix, announced once on Monday morning.")
                    .font(.system(.caption2))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, Space.textRail)
            }
            .padding(.vertical, 6)
            divider
            // Free, and stated honestly: levelling works where the app can
            // measure the audio or be told its level — files, downloads, and
            // servers that publish ReplayGain. A live stream plays as it comes.
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(get: { audio.loudness.isEnabled },
                                     set: { audio.loudness.isEnabled = $0 })) {
                    HStack(spacing: Space.iconGap) {
                        SonavaIcon(glyph: .wave, size: 20, tint: Theme.textSecondary)
                            .frame(width: Space.iconColumn, height: Space.iconColumn)
                        Text("Even out volume").font(.system(.subheadline))
                    }
                }
                .tint(Theme.accentDeep)
                Text("Files, downloads and level-reporting servers — applied to streams too. Live radio plays as it comes.")
                    .font(.system(.caption2))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, Space.textRail)
            }
            .padding(.vertical, 6)
        }
    }

    /// The toggle reflects what will actually happen: flipping it on asks for
    /// notification permission, and a declined prompt snaps it back off
    /// rather than leaving an "on" that will never fire.
    private var mondayMixBinding: Binding<Bool> {
        Binding(
            get: { mondayMixReminder },
            set: { wanted in
                mondayMixReminder = wanted
                Task {
                    let actual = await MondayMix.setReminder(wanted)
                    if actual != wanted { mondayMixReminder = actual }
                }
            }
        )
    }

    private var appleMusicValue: LocalizedStringKey {
        switch appleMusic.availability {
        case .ready: return "Connected"
        case .noSubscription: return "No subscription"
        case .notConfigured: return "Needs App Store Connect setup"
        case .notConnected: return "Connect"
        }
    }

    private var historyValue: LocalizedStringKey {
        journeyStore.journey.tracks.isEmpty ? "Import" : "\(journeyStore.journey.totalPlays) plays"
    }

    private var correctionValue: LocalizedStringKey {
        if let profile = audio.correction.profile, profile.isEnabled {
            return LocalizedStringKey(profile.name)
        }
        // No measured profile (or it is switched off), but the voicing tilt
        // still colours the sound — "Off" would be a lie.
        if !audio.correction.tilt.isNeutral {
            return LocalizedStringKey(VoicingPreset.matching(audio.correction.tilt)?.name ?? "Voicing")
        }
        return "Off"
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
                row(icon: .shuffle, title: "All sources", value: "Hub") {
                    showSourcesHub = true
                }
                divider
                row(icon: .note, title: "Apple Music", value: appleMusicValue) {
                    Task { await AppleMusicService.shared.connect() }
                }
                divider
                staticRow(icon: .wave, title: "Audius",
                          value: "Connected", valueColor: Theme.positive)
                divider
                staticRow(icon: .radio, title: "Internet Radio",
                          value: "Connected", valueColor: Theme.positive)
                divider
                row(icon: .server, title: "Self-hosted (Subsonic)", value: selfHostedValue) {
                    showConnectServer = true
                }
                divider
                row(icon: .restore, title: "Listening history", value: historyValue) {
                    showHistoryImport = true
                }
                divider
                // Free, deliberately. Every competitor either ships
                // scrobbling free or bundles it in the base price, and a gate
                // on "log the plays of music I already own" is the shape of
                // complaint that costs a rating without earning a sale.
                row(icon: .scrobble, title: "Scrobble to ListenBrainz",
                    value: scrobbleValue) {
                    showScrobble = true
                }
                divider
                staticRow(icon: .note, title: "Spotify / Apple Music",
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
                row(icon: .download, title: "Move to a new iPhone", value: nil) {
                    showBackup = true
                }
                divider
                row(icon: .restore, title: "Restore purchases", value: nil) {
                    Task { await proStore.restore() }
                }
                divider
                staticRow(icon: .shield, title: "Privacy",
                          value: "On-device", valueColor: Theme.textSecondary)
                divider
                row(icon: .shield, title: "Privacy Policy", value: nil) {
                    openURL(Links.privacyPolicy)
                }
                divider
                row(icon: .lock, title: "Terms of Use", value: nil) {
                    openURL(Links.termsOfUse)
                }
                #if DEBUG
                divider
                Toggle(isOn: Binding(
                    get: { proStore.developerOverride },
                    set: { proStore.setDeveloperOverride($0) }
                )) {
                    HStack(spacing: Space.iconGap) {
                        SonavaIcon(glyph: .server, size: 20, tint: Theme.textSecondary)
                            .frame(width: Space.iconColumn, height: Space.iconColumn)
                        Text("Developer: unlock Pro").font(.system(.subheadline))
                    }
                }
                .tint(Theme.accentDeep)   // ivory knob on ivory track vanished; umber keeps the knob visible
                .padding(.vertical, Space.m)
                #endif
            }
        }
    }

    // MARK: - Building blocks

    /// A section is a tracked-caps header over hairline-ruled rows on the
    /// bare ground — the anchor's language. The boxed cards this screen wore
    /// were the last of the old skeleton: a settings list is not elevated
    /// content, it is the page itself.
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption).weight(.bold))
                .tracking(1)
                .foregroundColor(Theme.textTertiary)
            VStack(spacing: 0) { content() }
        }
    }

    private func row(
        icon: SonavaIcon.Glyph,
        title: LocalizedStringKey,
        value: LocalizedStringKey?,
        showsProBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.l) {
                SonavaIcon(glyph: icon, size: 20, tint: Theme.textSecondary)
                    .frame(width: Space.iconColumn, height: Space.iconColumn)
                Text(title).font(.system(.subheadline))
                Spacer()
                if showsProBadge {
                    // The Home AI Mix card's badge, at row scale.
                    Text("PRO")
                        .font(.system(.caption2).weight(.heavy))
                        .foregroundColor(Theme.background)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                }
                if let value {
                    Text(value).font(.system(.footnote)).foregroundColor(Theme.textSecondary)
                }
                SonavaIcon(glyph: .chevronRight, size: 13, tint: Theme.textTertiary)
            }
            .padding(.vertical, Space.m)
            .frame(minHeight: Space.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func staticRow(
        icon: SonavaIcon.Glyph,
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        valueColor: Color
    ) -> some View {
        HStack(spacing: Space.l) {
            SonavaIcon(glyph: icon, size: 20, tint: Theme.textSecondary)
                .frame(width: Space.iconColumn, height: Space.iconColumn)
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
