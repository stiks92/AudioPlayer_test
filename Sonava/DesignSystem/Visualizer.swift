//
//  Visualizer.swift
//  AudioPlayer_test
//
//  Live audio-reactive visualizer + a compact "now playing" equaliser
//  indicator used inside list rows.
//

import SwiftUI

/// A row of bars that react to the engine's live `audioLevel`.
struct AudioVisualizerView: View {
    var level: CGFloat
    var isActive: Bool
    var barCount: Int = 44
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let width = geo.size.width
                let spacing: CGFloat = 3
                let barWidth = max(1.5, (width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.35), tint.opacity(0.95)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: barWidth, height: barHeight(i, t: t, max: geo.size.height))
                    }
                }
                .frame(width: width, height: geo.size.height, alignment: .center)
            }
        }
    }

    private func barHeight(_ index: Int, t: TimeInterval, max maxHeight: CGFloat) -> CGFloat {
        guard isActive else { return maxHeight * 0.06 }
        // Mirror-symmetric around the centre — tallest in the middle, and a
        // gentle shimmer that depends on distance from centre (identical for
        // mirrored bars) so it pulses in place rather than travelling sideways.
        let mid = Double(max(barCount - 1, 1)) / 2
        let dist = abs(Double(index) - mid) / mid          // 0 centre … 1 edge
        let envelope = 1.0 - 0.55 * dist
        let shimmer = 0.9 + 0.1 * sin(t * 2.4 + dist * 5)
        let value = 0.1 + Double(level) * envelope * shimmer
        return maxHeight * CGFloat(min(max(value, 0.06), 1))
    }
}

/// The tiny 4-bar equaliser shown next to the currently playing row.
struct NowPlayingBars: View {
    var isAnimating: Bool
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height(i, t: t))
                }
            }
            .frame(width: 20, height: 16, alignment: .bottom)
        }
    }

    private func height(_ index: Int, t: TimeInterval) -> CGFloat {
        guard isAnimating else { return 4 }
        let v = 0.5 + 0.5 * sin(t * 6 + Double(index) * 1.3)
        return 4 + CGFloat(v) * 12
    }
}
