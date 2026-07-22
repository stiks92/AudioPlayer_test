//
//  MarqueeText.swift
//  Sonava
//
//  Text that gently scrolls when it is wider than its container.
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .headline
    var color: Color = Theme.textPrimary
    var speed: Double = 30          // points per second
    var spacing: CGFloat = 44

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let shouldScroll = textWidth > geo.size.width + 1
            ZStack(alignment: .leading) {
                if shouldScroll {
                    HStack(spacing: spacing) {
                        label
                        label
                    }
                    .offset(x: offset)
                    .onAppear { startAnimation() }
                    .onChange(of: text) { _ in restart() }
                    .onChange(of: textWidth) { _ in restart() }
                } else {
                    label
                        .frame(width: geo.size.width, alignment: .leading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .background(widthReader)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
    }

    private var widthReader: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: WidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(WidthKey.self) { textWidth = $0 }
    }

    private func startAnimation() {
        offset = 0
        let distance = textWidth + spacing
        guard distance > 0 else { return }
        let duration = Double(distance) / speed
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }

    private func restart() {
        withAnimation(.none) { offset = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            startAnimation()
        }
    }

    private struct WidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
