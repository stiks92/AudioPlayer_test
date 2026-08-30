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
