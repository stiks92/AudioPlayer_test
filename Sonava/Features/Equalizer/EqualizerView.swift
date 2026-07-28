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

    /// Which band the finger is on, and which one is currently resting in the
    /// 0 dB detent — so the detent taps once on arrival instead of buzzing.
    @State private var draggingBand: Int?
    @State private var snappedBand: Int?

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
            VStack(spacing: Space.xl) {
                enableRow
                // The switch must stay *outside* this group. `disabled` is
                // additive down the hierarchy — a control inside a disabled
                // subtree cannot re-enable itself — so with the switch inside
                // it, an off equalizer could never be switched back on.
                //
                // Dimming by opacity rather than `.disabled()` is also the only
                // way the off state reads honestly: `.disabled()` greys system
                // controls but leaves hand-drawn shapes like the band knobs at
                // full brightness, so the screen looked half-on, half-off.
                VStack(spacing: Space.xl) {
                    bands
                    preampRow
                    presetPicker
                }
                // 0.35 pushed the frequency scale to 1.69:1 and the preset
                // labels to 1.55:1 — a switched-off equalizer became a screen
                // nothing could be read on. Controls may recede; they may not
                // become invisible.
                .opacity(effects.equalizer.isEnabled ? 1 : 0.55)
                .allowsHitTesting(effects.equalizer.isEnabled)

                // Outside the dimmed group on purpose: this is the only text
                // that explains what the feature does and does not do, and it
                // is most needed when the equalizer is off.
                footnote
            }
            .padding(Space.screenMargin)
            .padding(.bottom, 40)
            .animation(.easeInOut(duration: 0.2), value: effects.equalizer.isEnabled)
        }
    }

    private var enableRow: some View {
        Toggle(isOn: Binding(
            get: { effects.equalizer.isEnabled },
            set: { effects.setEnabled($0); Haptics.selection() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Equalizer").font(.system(.body).weight(.bold))
                Text(effects.selectedPreset.map { LocalizedStringKey($0.name) } ?? "Custom")
                    .font(.caption).foregroundColor(Theme.textSecondary)
                    .accessibilityIdentifier("eq.selectedPreset")
            }
        }
        .tint(Theme.accent)
        .accessibilityIdentifier(AccessibilityID.eqEnable)
    }

    private var bands: some View {
        VStack(spacing: Space.s) {
            GeometryReader { geo in
                let columnWidth = geo.size.width / CGFloat(EqualizerBand.count)

                ZStack {
                    // The response the ten bands actually produce, behind them.
                    ResponseGraph(gains: effects.equalizer.gains,
                                  limit: EqualizerSettings.gainLimit)

                    ForEach(0..<EqualizerBand.count, id: \.self) { index in
                        BandHandle(gain: effects.equalizer.gains[index],
                                   isActive: draggingBand == index,
                                   height: geo.size.height,
                                   width: columnWidth)
                            .frame(width: columnWidth)
                            .position(x: columnWidth * (CGFloat(index) + 0.5),
                                      y: geo.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                // One surface, not ten. Ten separate columns would each be
                // ~33pt wide — under Apple's 44pt minimum, and impossible to
                // fit at 44. Resolving to the nearest band instead makes the
                // whole graph the target, and lets a single sweep draw a curve
                // the way a desk does.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDrag(at: value.location, in: geo.size, columnWidth: columnWidth)
                        }
                        .onEnded { _ in
                            withAnimation(Motion.press) { draggingBand = nil }
                            snappedBand = nil
                        }
                )
            }
            .frame(height: 240)

            // Frequency scale, outside the graph so the curve owns its full
            // height and the labels keep a stable baseline.
            HStack(spacing: 0) {
                ForEach(EqualizerBand.frequencies, id: \.self) { frequency in
                    Text(EqualizerBand.label(for: frequency))
                        .font(.system(.caption2).weight(.medium).monospacedDigit())
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Resolves a touch anywhere in the graph to a band and a gain.
    private func handleDrag(at point: CGPoint, in size: CGSize, columnWidth: CGFloat) {
        let index = min(max(Int(point.x / columnWidth), 0), EqualizerBand.count - 1)
        if draggingBand != index {
            withAnimation(Motion.press) { draggingBand = index }
            Haptics.selection()          // a tick per band the finger crosses
            snappedBand = nil
        }

        let limit = EqualizerSettings.gainLimit
        let clampedY = min(max(0, point.y), size.height)
        let raw = limit - Float(clampedY / size.height) * (limit * 2)

        // A detent at 0 dB: "back to flat" is the one value anyone ever wants
        // to hit exactly, and it should be findable without looking.
        if abs(raw) < 0.9 {
            if snappedBand != index { Haptics.impact(.light) }
            snappedBand = index
            effects.setGain(0, at: index)
        } else {
            snappedBand = nil
            effects.setGain(raw, at: index)
        }
    }

    private var preampRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pre-amp").font(.system(.subheadline).weight(.semibold))
                Spacer()
                Text(gainText(effects.equalizer.preamp))
                    .font(.system(.footnote).weight(.medium).monospacedDigit())
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
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Presets")
                .textCase(.uppercase)
                .font(.system(.caption).weight(.bold)).tracking(1)
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
                                .font(.system(.footnote).weight(.semibold))
                                .foregroundColor(selected ? Theme.background : Theme.textSecondary)
                                .padding(.horizontal, Space.l).padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        // Identify by preset id so UI tests are language-agnostic.
                        .accessibilityIdentifier("eq.preset.\(preset.id)")
                    }
                }
            }
            .carouselBleed()
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
        VStack(spacing: Space.xl) {
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
                    .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            Spacer()
        }
        .padding(Space.xxl)
    }
}

// MARK: - One band's handle

/// Purely presentational: the gesture lives on the graph, not here.
private struct BandHandle: View {
    let gain: Float
    let isActive: Bool
    let height: CGFloat
    /// The column this handle occupies, so it can centre itself in it.
    let width: CGFloat

    private var fraction: CGFloat {
        let limit = CGFloat(EqualizerSettings.gainLimit)
        return (CGFloat(gain) + limit) / (limit * 2)
    }

    private var text: String {
        String(format: gain > 0 ? "+%.1f" : "%.1f", gain)
    }

    var body: some View {
        let knobY = height * (1 - fraction)
        ZStack {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 4)

            Circle()
                .fill(Color.white)
                .frame(width: isActive ? 30 : 24, height: isActive ? 30 : 24)
                .shadow(color: .black.opacity(0.45), radius: isActive ? 8 : 4, y: 2)
                .position(x: width / 2, y: knobY)

            // The value exists only while you are changing it: ten idle
            // readouts are noise, and its absence while dragging meant you
            // could not tell what you had just done.
            if isActive {
                Text(text)
                    .font(.system(.caption2).weight(.bold).monospacedDigit())
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white))
                    .fixedSize()
                    .position(x: width / 2, y: max(16, knobY - 28))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
