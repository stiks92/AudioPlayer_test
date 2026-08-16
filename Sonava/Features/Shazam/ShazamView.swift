//
//  ShazamView.swift
//  Sonava
//
//  "What's playing?" — listen, identify, and jump straight into the track on
//  Sonava's own catalogue.
//

import SwiftUI

struct ShazamView: View {
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shazam = ShazamService()

    @State private var isFindingOnAudius = false

    var body: some View {
        NavigationStack {
            ZStack {
                // The last screen wearing the pre-redesign blue aurora — the
                // exact «нейрослоп» the rest of the app buried. Now it
                // stands on the same ground as every other screen: black,
                // with the sleeve's warmth once a match brings one.
                Color.black.ignoresSafeArea()
                LinearGradient(stops: [
                    .init(color: matchTint.opacity(shazam.isListening ? 0.35 : 0.22), location: 0),
                    .init(color: .black, location: 0.55)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(Motion.fade, value: shazam.isListening)

                content
            }
            .foregroundColor(.white)
            .navigationTitle("What's playing?")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { shazam.stop(); dismiss() }
            .onDisappear { shazam.stop() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch shazam.state {
        case .matched(let result):
            matchView(result)
        default:
            listenView
        }
    }

    /// Warmth for the ground: the matched sleeve's own colour once there is
    /// one, the app's quiet accent until then.
    private var matchTint: Color {
        if case .matched = shazam.state { return Theme.accent }
        return Theme.accentDeep
    }

    // MARK: - Listen

    private var listenView: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            ZStack {
                // The pulse reads as the lens breathing — hairline ivory
                // rings, not blue chrome.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accentSoft.opacity(0.35), lineWidth: 1)
                        .frame(width: 168 + CGFloat(i) * 52, height: 168 + CGFloat(i) * 52)
                        .scaleEffect(shazam.isListening ? 1.22 : 1)
                        .opacity(shazam.isListening ? 0 : 0.35)
                        .animation(
                            shazam.isListening
                                ? .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.45)
                                : .default,
                            value: shazam.isListening
                        )
                }
                Button {
                    if shazam.isListening {
                        shazam.reset()
                    } else {
                        audio.pause()
                        Haptics.impact(.medium)
                        shazam.start()
                    }
                } label: {
                    // A waveform that genuinely runs while the app is
                    // listening and stands still when it is not. (The pack's
                    // microphone was tried first: its loop is a mute toggle,
                    // and a slash flashing over the mic mid-listen reads as
                    // the exact opposite of "listening".)
                    AnimatedIcon(glyph: .activity,
                                 mode: .loop(shazam.isListening),
                                 size: 64, tint: Theme.textPrimary)
                        .frame(width: 152, height: 152)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: matchTint.opacity(shazam.isListening ? 0.5 : 0),
                                radius: 26)
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.94))
            }
            .frame(height: 280)

            Text(statusText)
                .font(.sonavaFact)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if case .failed(let message) = shazam.state {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            #if targetEnvironment(simulator)
            Text("Music recognition needs a physical device.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            #endif

            Spacer()
        }
    }

    private var statusText: LocalizedStringKey {
        switch shazam.state {
        case .idle:      return "Tap to identify the music around you"
        case .listening: return "Listening…"
        case .noMatch:   return "No match — try again"
        case .failed:    return "Something went wrong"
        case .matched:   return ""
        }
    }

    // MARK: - Match

    private func matchView(_ result: ShazamService.Result) -> some View {
        VStack(spacing: Space.xl) {
            Spacer()
            // A record, found: square sleeve with the hairline border every
            // other sleeve in the product wears.
            AsyncImage(url: result.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.06)
                    SonavaIcon(glyph: .note, size: 56, tint: Theme.textTertiary)
                }
            }
            .frame(width: 232, height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

            VStack(spacing: 4) {
                Text(result.title)
                    .font(.system(.title2).weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(result.artist)
                    .font(.system(.callout))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, Space.xxl)

            VStack(spacing: Space.m) {
                Button {
                    findOnAudius(result)
                } label: {
                    HStack(spacing: Space.s) {
                        if isFindingOnAudius { ProgressView().tint(Theme.background) }
                        SonavaIcon(glyph: .play, size: 15, tint: Theme.background)
                        Text(isFindingOnAudius ? "Searching…" : "Play on Sonava")
                    }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(isFindingOnAudius)

                if let appleURL = result.appleMusicURL {
                    Link(destination: appleURL) {
                        Text("Open in Apple Music")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                }

                Button("Identify another") { shazam.reset() }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, Space.xxl)
            Spacer()
        }
    }

    private func findOnAudius(_ result: ShazamService.Result) {
        isFindingOnAudius = true
        let query = "\(result.title) \(result.artist)".trimmingCharacters(in: .whitespaces)
        Task {
            let results = (try? await AudiusService.shared.search(query)) ?? []
            isFindingOnAudius = false
            if let first = results.first {
                audio.play(first, in: results)
                Haptics.success()
                dismiss()
            } else {
                Haptics.warning()
            }
        }
    }
}
