//
//  SonavaMark.swift
//  Sonava
//
//  The app's mark, drawn rather than bundled: the same five-bar waveform the
//  home-screen icon is built from, so the icon a person tapped and the hero
//  they land on are recognisably the same object.
//
//  Before this the paywall's hero was `sparkles` — a symbol Apple ships on
//  every device, and one already used for a single feature on the same screen.
//

import SwiftUI

struct SonavaMark: View {
    var height: CGFloat = 44
    var tint: Color = .white

    /// The icon's proportions, so the two never drift apart.
    private let bars: [CGFloat] = [0.34, 0.62, 1.00, 0.70, 0.44]

    var body: some View {
        HStack(alignment: .center, spacing: height * 0.11) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, scale in
                Capsule()
                    .fill(tint)
                    .frame(width: height * 0.19, height: height * scale)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
