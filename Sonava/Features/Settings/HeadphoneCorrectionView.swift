//
//  HeadphoneCorrectionView.swift
//  Sonava
//
//  Import and manage a headphone-correction profile.
//
//  v1 ships no bundled third-party measurements (the AutoEq data licence is
//  code-only; letters to the measurement owners are drafted in
//  docs/letters/). Instead this works like the playlist importer: the
//  listener brings the ParametricEQ export for THEIR headphones from
//  autoeq.app — their download, their data, our DSP. When permissions
//  arrive, a bundled picker drops in above this without changing anything
//  underneath.
//

import SwiftUI
import UniformTypeIdentifiers

struct HeadphoneCorrectionView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var pasted = ""
    @State private var showFilePicker = false
    @State private var parseFailed = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                // The whole screen is Pro (the `EqualizerView` pattern). An
                // installed profile survives a lapse on disk — the lock is on
                // the door, not on the listener's data.
                if proStore.isPro {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xl) {
                            if let profile = audio.correction.profile {
                                installed(profile)
                            } else {
                                importer
                            }
                            // Voicing and A/B live below both states on
                            // purpose: the tilt works with or without a
                            // measured profile.
                            voicing
                            comparison
                        }
                        .padding(Space.screenMargin)
                    }
                } else {
                    lockedState
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Headphone correction")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            // A/B is a comparison instrument, not a setting: leaving the
            // screen always returns the sound to what the controls say.
            .onDisappear { audio.correction.setBypassed(false) }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.plainText, .text, .data]) { result in
                if case .success(let url) = result { importFile(url) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Locked (free tier)

    private var lockedState: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            SonavaIcon(glyph: .wave, size: 56)
                .font(.system(size: 54, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Theme.accent.opacity(0.6), radius: 18)
            Text("Headphone correction is a Pro feature")
                .font(.system(.title2).weight(.bold))
                .multilineTextAlignment(.center)
            // The same pitch the importer opens with — the promise is
            // identical on both sides of the gate.
            Text("Studio-grade correction for your exact headphones — from a measurement of your model, not a generic bass boost.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Sonava Pro")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            .accessibilityIdentifier("correction.unlock")
            Spacer()
        }
        .padding(Space.xxl)
    }

    // MARK: - Installed state

    private func installed(_ profile: CorrectionProfile) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.sonavaName)
                Text("\(profile.bands.count) bands · preamp \(String(format: "%.1f", profile.preampDB)) dB")
                    .font(.sonavaFact)
                    .foregroundColor(Theme.textSecondary)
            }

            Toggle(isOn: Binding(
                get: { profile.isEnabled },
                set: { audio.correction.setEnabled($0) }
            )) {
                Text("Correction on").font(.system(.subheadline))
            }
            .tint(Theme.accentDeep)
            .accessibilityIdentifier("correction.toggle")

            // The bands, as a quiet machine-face table — the profile is a
            // measured fact sheet, not a control surface.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(profile.bands.prefix(14).enumerated()), id: \.offset) { _, band in
                    Text(verbatim: bandLine(band))
                        .font(.sonavaFact)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(Space.l)
            .card(cornerRadius: Radius.card)

            Text("Applied to files and streams alike, before your own EQ. One profile for both ears for now.")
                .font(.footnote)
                .foregroundColor(Theme.textTertiary)

            HStack(spacing: Space.l) {
                Button("Replace") { audio.correction.remove() }
                    .buttonStyle(SecondaryCapsuleButtonStyle(expands: false))
                Button("Remove") {
                    audio.correction.remove()
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func bandLine(_ band: CorrectionBand) -> String {
        let kind: String
        switch band.kind {
        case .peaking: kind = "PK "
        case .lowShelf: kind = "LSC"
        case .highShelf: kind = "HSC"
        }
        return String(format: "%@  %6.0f Hz  %+5.1f dB  Q %.2f",
                      kind, band.frequency, band.gainDB, band.q)
    }

    // MARK: - Voicing (stage 1.5)

    private var voicing: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            sectionTitle("Voicing")
            Text("A gentle bass and treble tilt — over the measured profile, or on its own.")
                .font(.footnote)
                .foregroundColor(Theme.textTertiary)

            SegmentedControl(
                segments: VoicingPreset.all.map {
                    .init(value: $0.tilt,
                          title: LocalizedStringKey($0.name),
                          identifier: "correction.voicing.\($0.id)")
                },
                selection: Binding(
                    get: { audio.correction.tilt },
                    set: { audio.correction.setTilt($0) }
                ))

            tiltSlider("Bass", value: tiltBinding(\.bassDB),
                       range: VoicingTilt.bassRange, identifier: "correction.tilt.bass")
            tiltSlider("Treble", value: tiltBinding(\.trebleDB),
                       range: VoicingTilt.trebleRange, identifier: "correction.tilt.treble")
        }
    }

    private func tiltBinding(_ keyPath: WritableKeyPath<VoicingTilt, Double>) -> Binding<Double> {
        Binding(
            get: { audio.correction.tilt[keyPath: keyPath] },
            set: { value in
                var tilt = audio.correction.tilt
                tilt[keyPath: keyPath] = value
                audio.correction.setTilt(tilt)
            })
    }

    /// The `EqualizerView` pre-amp row pattern: a titled slider in a card.
    private func tiltSlider(_ title: LocalizedStringKey, value: Binding<Double>,
                            range: ClosedRange<Double>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(.subheadline).weight(.semibold))
                Spacer()
                Text(verbatim: tiltText(value.wrappedValue))
                    .font(.system(.footnote).weight(.medium).monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
            }
            Slider(value: value, in: range, step: 0.5)
                .tint(Theme.accent)
                .accessibilityIdentifier(identifier)
        }
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
    }

    /// Locale-honest dB: typographic minus, localized decimal separator,
    /// translated unit — the lessons the equalizer's readout already earned.
    private func tiltText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let number = rounded
            .formatted(.number.precision(.fractionLength(1)))
            .replacingOccurrences(of: "-", with: "\u{2212}")
        let text = String(localized: "\(number) dB")
        return rounded > 0 ? "+\(text)" : text
    }

    // MARK: - A/B comparison

    /// Whether the cascade would do anything at all right now — with nothing
    /// installed and both knobs at rest, "before" and "after" are the same
    /// sound and the switch would be a lie. While bypassed it stays live so
    /// the way back is never locked.
    private var hasAudibleChain: Bool {
        (audio.correction.profile?.isEnabled ?? false)
            || !audio.correction.tilt.isNeutral
            || audio.correction.isBypassed
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            sectionTitle("Compare")
            SegmentedControl(
                segments: [
                    .init(value: true, title: "Before", identifier: "correction.ab.before"),
                    .init(value: false, title: "After", identifier: "correction.ab.after"),
                ],
                selection: Binding(
                    get: { audio.correction.isBypassed },
                    set: { audio.correction.setBypassed($0); Haptics.selection() }
                ))
                .frame(maxWidth: .infinity, alignment: .center)
            Text("“Before” is the untouched sound — no profile, no voicing. It resets when you close this screen.")
                .font(.footnote)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
        // Receding, not vanishing — the EqualizerView off-state rule.
        .opacity(hasAudibleChain ? 1 : 0.55)
        .allowsHitTesting(hasAudibleChain)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(.caption).weight(.bold)).tracking(1)
            .foregroundColor(Theme.textTertiary)
    }

    // MARK: - Import state

    private var importer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Studio-grade correction for your exact headphones — from a measurement of your model, not a generic bass boost.")
                .font(.system(.subheadline))
                .foregroundColor(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                instruction(number: 1, text: "Open autoeq.app and pick your headphone model.")
                instruction(number: 2, text: "Choose “Parametric Equalizer” and copy the result.")
                instruction(number: 3, text: "Paste it below.")
            }

            TextEditor(text: $pasted)
                .font(.system(.footnote, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(Space.m)
                .card(cornerRadius: Radius.card)
                .accessibilityIdentifier("correction.paste")

            if parseFailed {
                Text("Couldn't read this profile — check it's a Parametric EQ export.")
                    .font(.footnote)
                    .foregroundColor(Theme.destructive)
            }

            Button {
                install(text: pasted, name: String(localized: "My headphones"))
            } label: {
                Text("Apply profile")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("correction.apply")

            Button("Open a file instead") { showFilePicker = true }
                .buttonStyle(QuietButtonStyle())
        }
    }

    private func instruction(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text(verbatim: "\(number)")
                .font(.sonavaOrdinal)
                .foregroundColor(Theme.accentSoft)
            Text(text)
                .font(.system(.footnote))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func importFile(_ url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            parseFailed = true
            return
        }
        // The filename is usually the model: "Sony WH-1000XM5 ParametricEQ.txt".
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "ParametricEQ", with: "")
            .trimmingCharacters(in: .whitespaces)
        install(text: text, name: name.isEmpty ? String(localized: "My headphones") : name)
    }

    private func install(text: String, name: String) {
        guard let profile = CorrectionProfileParser.parse(text, name: name) else {
            parseFailed = true
            return
        }
        parseFailed = false
        audio.correction.install(profile)
        pasted = ""
    }
}
