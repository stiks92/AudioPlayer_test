//
//  DesignComponents.swift
//  Sonava
//
//  Reusable, animated UI primitives shared across screens.
//

import SwiftUI

// MARK: - Press animation

/// Subtle spring scale on tap, applied to buttons.
struct BouncyButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Circular icon button

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 46
    var iconSize: CGFloat = 18
    var tint: Color = Theme.textPrimary
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(filled ? Theme.background : tint)
                .frame(width: size, height: size)
                .background(
                    Group {
                        if filled {
                            Circle().fill(Color.white)
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(filled ? 0 : 0.10), lineWidth: 1)
                )
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

// MARK: - Big morphing play / pause button

struct PlayPauseButton: View {
    let isPlaying: Bool
    var size: CGFloat = 76
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .white.opacity(0.35), radius: 22, y: 8)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundColor(Theme.background)
                    .offset(x: isPlaying ? 0 : size * 0.03)
                    .scaleEffect(isPlaying ? 1 : 1.02)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPlaying)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
    }
}

// MARK: - Heart / favourite button with burst

struct HeartButton: View {
    let isOn: Bool
    var size: CGFloat = 22
    let action: () -> Void

    @State private var burst = false

    var body: some View {
        Button {
            action()
            if !isOn {
                burst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { burst = false }
            }
        } label: {
            ZStack {
                Image(systemName: isOn ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(isOn ? Theme.destructive : Theme.textSecondary)
                    .symbolEffectBounce(trigger: isOn)

                if burst {
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(Theme.destructive)
                            .frame(width: 4, height: 4)
                            .offset(y: -size)
                            .rotationEffect(.degrees(Double(i) / 6 * 360))
                            .scaleEffect(burst ? 1.6 : 0.1)
                            .opacity(burst ? 0 : 1)
                            .animation(.easeOut(duration: 0.5), value: burst)
                    }
                }
            }
            .frame(width: size + 16, height: size + 16)
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

// MARK: - Draggable scrubber

/// A custom progress bar that grows on touch and supports scrubbing.
struct ScrubberView: View {
    @Binding var value: Double          // 0...1
    var onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = isDragging ? 10 : 6
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: height)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, min(width, width * CGFloat(value))), height: height)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = Double(min(max(0, g.location.x / width), 1))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        }
        .frame(height: 24)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accentSoft)
            }
        }
    }
}

// MARK: - Symbol effect compatibility helper

private struct BounceModifier: ViewModifier {
    let trigger: Bool
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.bounce, value: trigger)
        } else {
            content
                .scaleEffect(trigger ? 1.15 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: trigger)
        }
    }
}

extension View {
    func symbolEffectBounce(trigger: Bool) -> some View {
        modifier(BounceModifier(trigger: trigger))
    }
}
