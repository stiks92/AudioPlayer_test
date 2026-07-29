//
//  OutputMeter.swift
//  Sonava
//
//  A meter that only moves when it is measuring something.
//
//  What it replaces was a 44-bar "spectrum", and it was not a spectrum. Every
//  bar received the same scalar shaped by a fixed distance-from-centre envelope:
//
//      let envelope = 1.0 - 0.55 * dist
//      let value = 0.1 + Double(level) * envelope * shimmer
//
//  Bar 3 carried exactly as much information as bar 40 — none of its own. And
//  on any stream the scalar itself was invented, because `AVPlayer` exposes no
//  metering and `RemoteAudioEngine.refresh()` synthesises
//  `0.45 + 0.22·sin(t·3.1) + 0.12·sin(t·7.3)`.
//
//  So the app was animating arithmetic and calling it sound. That is decoration
//  pretending to be instrumentation, and it is exactly the kind of motion that
//  makes an interface feel machine-made: it moves a lot and means nothing.
//
//  The honest version is also the more distinctive one. There is one real
//  number available — broadband RMS from the local engine's output tap — and one
//  number earns one dimension. Forty segments, lit from a true level, and when
//  there is nothing to measure the meter says so instead of miming.
//
//  That turns the app's most awkward implementation detail into its clearest
//  signal: **when the meter moves, you are playing your own file.**
//

import SwiftUI

struct OutputMeter: View {
    let level: CGFloat
    /// False on streams and radio, where no level exists to read.
    let metered: Bool
    var isPlaying: Bool = true
    var segments: Int = 40
    var tint: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Peak hold, the way a hardware meter keeps the loudest recent transient
    /// visible for a moment after it has passed.
    @State private var peak: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("OUTPUT")
                Spacer(minLength: Space.m)
                Text(metered ? "RMS · LOCAL FILE" : "NO METER · STREAM")
            }
            .font(.sonavaStamp)
            .tracking(1.2)
            .foregroundColor(Theme.textTertiary)

            GeometryReader { geo in
                let gap: CGFloat = 1.5
                let width = max(1, (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments))
                let lit = metered ? Int((level * CGFloat(segments)).rounded()) : 0
                let peakIndex = metered ? Int((peak * CGFloat(segments)).rounded()) : 0
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { index in
                        Rectangle()
                            .fill(colour(index: index, lit: lit, peak: peakIndex))
                            .frame(width: width)
                    }
                }
                .frame(height: geo.size.height, alignment: .bottom)
            }
            .frame(height: metered ? 22 : Theme.hairlineWidth * 3)
            .animation(.linear(duration: 0.08), value: level)

            if metered {
                // A scale, not decoration. A bar tells you how much; a scale
                // tells you how much *of what*.
                HStack(spacing: 0) {
                    ForEach(["−60", "−40", "−30", "−20", "−12", "−6", "0"], id: \.self) { mark in
                        Text(mark)
                            .frame(maxWidth: .infinity, alignment: mark == "−60" ? .leading : .trailing)
                    }
                }
                .font(.sonavaStamp)
                .foregroundColor(Theme.textTertiary)
            }
        }
        .onChange(of: level) { _, new in
            guard metered else { peak = 0; return }
            if new >= peak {
                peak = new
            } else if !reduceMotion {
                withAnimation(.easeOut(duration: 0.9)) { peak = new }
            } else {
                peak = new
            }
        }
        .onChange(of: metered) { _, _ in peak = 0 }
        .accessibilityElement()
        .accessibilityLabel(metered ? "Output level" : "No meter on a stream")
        .accessibilityValue(metered ? "\(Int(level * 100)) percent" : "")
    }

    private func colour(index: Int, lit: Int, peak: Int) -> Color {
        // The unlit floor is never invisible: an instrument with no signal still
        // shows you where its scale is.
        guard metered else { return tint.opacity(0.14) }
        if index == peak && peak > lit { return tint.opacity(0.75) }
        guard index < lit else { return tint.opacity(0.10) }
        // The last sixth is where clipping lives, and it is the one place this
        // meter spends a colour.
        return index >= segments - segments / 6 ? Theme.warning : tint.opacity(0.92)
    }
}
