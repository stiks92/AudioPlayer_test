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

    /// Whether to fade the whole label when disabled.
    ///
    /// Right for the icon buttons this style mostly wraps, and wrong for a
    /// filled capsule: fading a dark label and its light fill together
    /// collapses the contrast *between* them — one such button measured
    /// 1.81:1. Those buttons colour their own disabled state and opt out.
    var dimsWhenDisabled = true

    /// A custom `ButtonStyle` gets no disabled treatment for free, so without
    /// this a disabled button renders pixel-identical to a live one.
    @Environment(\.isEnabled) private var isEnabled

    private var opacity: Double {
        (dimsWhenDisabled && !isEnabled) ? 0.35 : 1
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(opacity)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: isEnabled)
    }
}

// MARK: - Dismissal

extension View {
    /// The one way a sheet is dismissed.
    ///
    /// Eleven sheets had built this for themselves, and they did not agree.
    /// Ten put "Done" at the trailing edge and one at the leading edge — the
    /// position that means Cancel or Back everywhere else in iOS — and three
    /// coloured it white while eight used the accent. A reader builds muscle
    /// memory for the dismiss target within a session, and this app was
    /// moving it and recolouring it between screens.
    ///
    /// Composes with a screen's other toolbar items: SwiftUI merges multiple
    /// `.toolbar` modifiers, so a view that also needs a menu keeps declaring
    /// it separately.
    func doneToolbar(_ dismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done", action: dismiss)
                    .foregroundColor(Theme.accentSoft)
            }
        }
    }
}

// MARK: - Primary action

/// The app's one full-width primary action: a white capsule with a dark label.
///
/// Extracted because three screens had built it independently — Scrobble,
/// Add server and AI Mix — and two of them carried the same defect. A dark
/// label on a light fill cannot be dimmed as a whole: fading both together
/// collapses the contrast *between* them, and the label goes with it. Measured
/// at 1.60:1 on the Scrobble button and 1.81:1 before AI Mix was fixed by hand.
///
/// AI Mix's hand-written fix was correct and stayed a local fact, which is the
/// actual failure — a review round later found the identical bug two screens
/// over. So the disabled colours live here now, where a fourth call site
/// inherits them instead of having to remember them.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    /// Full width in a form; hugging when it sits in an empty state beside
    /// nothing else. The height never changes — a 44pt target is a floor, not
    /// a preference, and it was being met by three different means.
    var expands = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isEnabled ? Theme.background : .white.opacity(0.55))
            .tint(isEnabled ? Theme.background : .white)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Space.hitTarget)
            .padding(.vertical, expands ? Space.s : 0)
            .background(
                Capsule().fill(isEnabled ? Color.white : Color.white.opacity(0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: isEnabled)
    }
}

// MARK: - The rest of the button ladder

/// The second rung: an action that matters but isn't *the* action.
///
/// Sixteen files had each invented this — an ivory word on a
/// `Color.white.opacity(0.08)` capsule, or a hairline border, or bare accent
/// text — at different heights and radii. A screen carrying two of those
/// reads as two screens. There are three rungs now and nothing else: white
/// capsule, bordered capsule, bare word.
struct SecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    /// Full width for a form's second action; hugging for a row's.
    var expands = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .foregroundColor(isEnabled ? Theme.accentSoft : Theme.textTertiary)
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Space.hitTarget)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: isEnabled)
    }
}

/// The third rung: a word that acts, with no surface at all — Retry, Cancel,
/// "See all". Sized to the same 44pt target as the other two, because a
/// borderless control still has to be hittable.
/// Type-erased button style, so a view can switch styles on state without
/// duplicating the whole button.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .foregroundColor(isEnabled ? Theme.accentSoft : Theme.textTertiary)
            .padding(.horizontal, Space.m)
            .frame(minHeight: Space.hitTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
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
                // One shape leaning between the two states, not two glyphs
                // cross-fading. The optical nudge stays: a play triangle sits
                // right of centre by its own geometry, and the old fix for that
                // has to travel with it.
                PlayPauseGlyph(isPlaying: isPlaying, size: size * 0.42,
                               tint: Theme.background)
                    .offset(x: isPlaying ? 0 : size * 0.02)
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

    var body: some View {
        Button(action: action) {
            // The burst heart's canvas is mostly air — the heart itself is a
            // third of it, the rest is room for the particle ring to fly —
            // so the animation renders at ~3× the glyph slot and overflows
            // it deliberately.
            AnimatedIcon(glyph: .heartBurst,
                         mode: .toggle(isOn),
                         size: size * 3.6,
                         tint: isOn ? Theme.destructive : Theme.textSecondary)
                .frame(width: size + 16, height: size + 16)
                // The animation view refuses hits (it must not eat the
                // button's own gesture), which left the button with no
                // tappable surface at all — a tap on the heart's exact centre
                // fell straight through to whatever sat behind it. The shape
                // is the button's honest hit area.
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

// MARK: - Volume row

/// The volume block the players share: low glyph, scrubber, high glyph, and
/// the route picker beside it — how loud, then where the sound goes.
///
/// Under VoiceOver the three volume pieces collapse into one adjustable
/// element ("Volume, NN%") stepped in fives, because a drag-only scrubber is
/// unusable by swipe. The collapse is gated on VoiceOver actually running:
/// an adjustable container swallows the child elements that Voice Control
/// and the UI tests address, so it must never be the default shape.
struct VolumeRow: View {
    /// The radio booth turns this off: its transport already leads with the
    /// route picker, and one screen must not offer the same control twice.
    var showsRoutePicker = true

    @EnvironmentObject private var audio: AudioManager
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    var body: some View {
        HStack(spacing: Space.m) {
            slider
            if showsRoutePicker {
                // Where the sound goes, next to how loud it is.
                RoutePickerButton(tint: .white.opacity(0.6), size: 18)
                    .frame(width: 30, height: 30)
                    .accessibilityLabel(Text("Output device"))
            }
        }
    }

    @ViewBuilder
    private var slider: some View {
        if voiceOverOn {
            sliderRow
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Volume"))
                .accessibilityValue(Text(verbatim: "\(Int((audio.volume * 100).rounded()))%"))
                .accessibilityAdjustableAction { direction in
                    let step: Float = direction == .increment ? 0.05 : -0.05
                    audio.volume = min(max(audio.volume + step, 0), 1)
                }
        } else {
            sliderRow
        }
    }

    private var sliderRow: some View {
        HStack(spacing: Space.m) {
            SonavaIcon(glyph: .volumeLow, size: 16, tint: .white.opacity(0.6))
            ScrubberView(
                value: Binding(
                    get: { Double(audio.volume) },
                    set: { audio.volume = Float($0) }
                ),
                onEditingChanged: { _ in }
            )
            SonavaIcon(glyph: .volumeHigh, size: 16, tint: .white.opacity(0.6))
        }
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
                .font(.system(.title3).weight(.bold))
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

// MARK: - Shelf states

/// What a shelf shows when its source could not be reached.
///
/// Collapsing `.failed` into `.empty` — which is what every shelf used to do —
/// tells someone whose train just went into a tunnel that there is no music in
/// the world, and offers them nothing to do about it.
struct ShelfFailure: View {
    let title: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: title)
            HStack(spacing: Space.m) {
                SonavaIcon(glyph: .radio, size: 20, tint: Theme.textSecondary)
                    .frame(width: Space.iconColumn, height: Space.iconColumn)
                Text("Couldn't load this right now.")
                    .font(.sonavaRowMeta)
                    .foregroundColor(Theme.textSecondary)
                Spacer(minLength: Space.s)
                Button("Retry", action: retry)
                    .font(.sonavaRowMeta.weight(.semibold))
                    .foregroundColor(Theme.accentSoft)
                    .hitTarget()
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .card(cornerRadius: Radius.card)
        }
    }
}

/// The grey shapes a shelf shows while it is loading, so the layout does not
/// jump when the real cards arrive.
struct ShelfPlaceholder: View {
    let title: LocalizedStringKey
    var cardWidth: CGFloat = 150
    var cardHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: title)
            HStack(spacing: Space.l) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: cardWidth, height: cardHeight)
                }
            }
            .redacted(reason: .placeholder)
        }
        .accessibilityLabel(Text("Loading"))
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
