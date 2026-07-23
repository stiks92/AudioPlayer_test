//
//  EqualizerView.swift
//  Sonava
//
//  A 10-band graphic equalizer — a Sonava Pro feature. Drives the shared
//  `AudioEffects`, so changes are heard live on whatever is playing from the
//  user's own files.
//

import SwiftUI

struct EqualizerView: View {
    @ObservedObject var effects: AudioEffects
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if proStore.isPro {
                    equalizer
                } else {
                    lockedState
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Unlocked

    private var equalizer: some View {
        ScrollView {
            VStack(spacing: 24) {
                enableRow
                bands
                preampRow
                presetPicker
                footnote
            }
            .padding(20)
            .padding(.bottom, 40)
            .disabled(!effects.equalizer.isEnabled)
            .animation(.easeInOut(duration: 0.2), value: effects.equalizer.isEnabled)
        }
    }

    private var enableRow: some View {
        Toggle(isOn: Binding(
            get: { effects.equalizer.isEnabled },
            set: { effects.setEnabled($0); Haptics.selection() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Equalizer").font(.system(size: 17, weight: .bold))
                Text(effects.selectedPreset.map { LocalizedStringKey($0.name) } ?? "Custom")
                    .font(.caption).foregroundColor(Theme.textSecondary)
                    .accessibilityIdentifier("eq.selectedPreset")
            }
        }
        .tint(Theme.accent)
        .accessibilityIdentifier(AccessibilityID.eqEnable)
        .disabled(false)
    }

    private var bands: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(EqualizerBand.frequencies.enumerated()), id: \.offset) { index, frequency in
                BandSlider(
                    gain: Binding(
                        get: { effects.equalizer.gains[index] },
                        set: { effects.setGain($0, at: index) }
                    ),
                    label: EqualizerBand.label(for: frequency)
                )
            }
        }
        .frame(height: 220)
        .padding(.vertical, 8)
    }

    private var preampRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pre-amp").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(gainText(effects.equalizer.preamp))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(effects.equalizer.preamp) },
                    set: { effects.setPreamp(Float($0)) }
                ),
                in: Double(-EqualizerSettings.gainLimit)...Double(EqualizerSettings.gainLimit)
            )
            .tint(Theme.accent)
        }
        .padding(16)
        .glass(cornerRadius: 18)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .bold)).tracking(1)
                .foregroundColor(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqualizerPreset.all) { preset in
                        let selected = effects.equalizer.presetID == preset.id
                        Button {
                            effects.apply(preset)
                            Haptics.selection()
                        } label: {
                            Text(LocalizedStringKey(preset.name))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selected ? Theme.background : Theme.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        // Identify by preset id so UI tests are language-agnostic.
                        .accessibilityIdentifier("eq.preset.\(preset.id)")
                    }
                }
            }
        }
    }

    private var footnote: some View {
        Text("The equalizer shapes playback of your imported files. Streaming sources play flat.")
            .font(.footnote)
            .foregroundColor(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func gainText(_ gain: Float) -> String {
        let rounded = (gain * 10).rounded() / 10
        return rounded > 0 ? "+\(gainString(rounded))" : gainString(rounded)
    }

    private func gainString(_ value: Float) -> String {
        String(format: "%.1f dB", value)
    }

    // MARK: - Locked (free tier)

    private var lockedState: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 54, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Theme.accent.opacity(0.6), radius: 18)
            Text("The equalizer is a Pro feature")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text("Ten bands, a pre-amp and a dozen presets to shape your sound exactly the way you like it.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Sonava Pro")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 26).padding(.vertical, 15)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            Spacer()
        }
        .padding(30)
    }
}

// MARK: - One vertical band

private struct BandSlider: View {
    @Binding var gain: Float
    let label: String

    private let range: ClosedRange<Float> = -EqualizerSettings.gainLimit...EqualizerSettings.gainLimit

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let fraction = CGFloat((gain - range.lowerBound) / (range.upperBound - range.lowerBound))
            let knobY = height * (1 - fraction)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 5)

                // Fill from the centre (0 dB) toward the knob, so cut and boost
                // read differently at a glance.
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 5,
                           height: max(3, abs(knobY - height / 2)))
                    .offset(y: -(height - max(knobY, height / 2)))

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedY = min(max(0, value.location.y), height)
                        let newFraction = Float(1 - clampedY / height)
                        gain = range.lowerBound + newFraction * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .overlay(alignment: .bottom) {
            Text(label)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundColor(Theme.textTertiary)
                .fixedSize()
                .offset(y: 16)
        }
        .padding(.bottom, 18)
    }
}
