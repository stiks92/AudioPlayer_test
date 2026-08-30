//
//  PlayerShell.swift
//  Sonava
//
//  The genie: the player grows out of the mini capsule and shrinks back into
//  it, Wolt-style — one container morphing between two states with a spring,
//  its contents cross-fading in flight.
//
//  Why a shell and not a matched-geometry flight: the mini capsule lives
//  inside `tabViewBottomAccessory`, a system-hosted container whose coordinate
//  space does not resolve into the app's own hierarchy — a matched flight was
//  built earlier, captured mid-air flying from the wrong corner, and reverted
//  (see RootView). So instead of matching *across* that boundary, the shell
//  renders its own capsule at the same spot, and the accessory steps aside the
//  instant the shell appears. One view, one geometry, nothing to mismatch.
//
//  The morph is interruptible spring physics; the dismissal completion uses
//  `withAnimation(_:completionCriteria:)` so state flips only when the capsule
//  has actually landed. Reduce Motion skips the journey in both directions.
//

import SwiftUI

struct PlayerShell: View {
    let onDismiss: () -> Void

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var clock: PlaybackClock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    @State private var expanded = false

    /// The capsule's metrics, mirroring the accessory it stands in for.
    private let capsuleHeight: CGFloat = 58
    private let capsuleMargin: CGFloat = 12
    private let capsuleBottom: CGFloat = 84

    private var spring: Animation {
        .spring(response: 0.52, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // The ground dims as the player rises, so the morph reads as
                // one object lifting off the page rather than a scene cut.
                Color.black.opacity(expanded ? 0.45 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ZStack {
                    // The shell ignores the safe area so the morphing container
                    // can reach the physical edges; the player's *content* must
                    // not — without these paddings the header slid under the
                    // status bar, chevron pressed against the clock.
                    //
                    // Two players, one shell: a live station opens the radio
                    // booth, everything else the track player. `currentSong`
                    // is published, so a queue that walks from a track into a
                    // station cross-fades between them in place.
                    ZStack {
                        if audio.isLive {
                            RadioLiveView(namespace: ns) { dismiss() }
                                .transition(.opacity)
                        } else {
                            NowPlayingView(namespace: ns) { dismiss() }
                                .transition(.opacity)
                        }
                    }
                    .animation(Motion.fade, value: audio.isLive)
                    .padding(.top, expanded ? geo.safeAreaInsets.top : 0)
                    .padding(.bottom, expanded ? geo.safeAreaInsets.bottom : 0)
                    .opacity(expanded ? 1 : 0)
                    capsule
                        .opacity(expanded ? 0 : 1)
                }
                .frame(
                    width: expanded ? geo.size.width : geo.size.width - capsuleMargin * 2,
                    height: expanded ? geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                                     : capsuleHeight
                )
                .background(expanded ? Color.black : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : capsuleHeight / 2,
                                            style: .continuous))
                .padding(.bottom, expanded ? 0 : capsuleBottom)
                .ignoresSafeArea(edges: expanded ? .all : [])
            }
        }
        .onAppear {
            if reduceMotion {
                expanded = true
            } else {
                withAnimation(spring) { expanded = true }
            }
        }
    }

    /// What the shell looks like folded: the accessory's twin, so the handoff
    /// between the two is invisible.
    private var capsule: some View {
        HStack(spacing: Space.m) {
            if let song = audio.currentSong {
                SpinningDisc(song: song, side: 38,
                             isSpinning: audio.isPlaying && !reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.system(.subheadline).weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(.caption))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            PlayPauseGlyph(isPlaying: audio.isPlaying, size: 18)
            SonavaIcon(glyph: .next, size: 18)
        }
        .padding(.horizontal, Space.l)
        .frame(height: capsuleHeight)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func dismiss() {
        guard !reduceMotion else { onDismiss(); return }
        withAnimation(spring, completionCriteria: .logicallyComplete) {
            expanded = false
        } completion: {
            onDismiss()
        }
    }
}
