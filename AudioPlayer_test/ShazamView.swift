//
//  ShazamView.swift
//  AudioPlayer_test
//
//  "What's playing?" — listen, identify, and jump straight into the track on
//  Aurora's own catalogue.
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
                AuroraBackground(colors: [Color(hex: 0x00C6FF), Color(hex: 0x0072FF), Theme.accent],
                                 animated: shazam.isListening)
                    .overlay(Theme.background.opacity(0.25))

                content
            }
            .foregroundColor(.white)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { shazam.stop(); dismiss() }.foregroundColor(.white)
                }
            }
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

    // MARK: - Listen

    private var listenView: some View {
        VStack(spacing: 30) {
            Spacer()
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 160 + CGFloat(i) * 60, height: 160 + CGFloat(i) * 60)
                        .scaleEffect(shazam.isListening ? 1.15 : 1)
                        .opacity(shazam.isListening ? 0 : 0.6)
                        .animation(
                            shazam.isListening
                                ? .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.4)
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
                    Image(systemName: shazam.isListening ? "waveform" : "waveform.circle.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 150)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5))
                        .symbolEffectBounce(trigger: shazam.isListening)
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.94))
            }

            Text(statusText)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if case .failed(let message) = shazam.state {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
    }

    private var statusText: String {
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
        VStack(spacing: 22) {
            Spacer()
            AsyncImage(url: result.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x00C6FF), Theme.accent], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text(result.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(result.artist)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 30)

            VStack(spacing: 12) {
                Button {
                    findOnAudius(result)
                } label: {
                    HStack {
                        if isFindingOnAudius { ProgressView().tint(Theme.background) }
                        Image(systemName: "play.fill")
                        Text(isFindingOnAudius ? "Searching…" : "Play on Aurora")
                    }
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.97))
                .disabled(isFindingOnAudius)

                if let appleURL = result.appleMusicURL {
                    Link(destination: appleURL) {
                        Text("Open in Apple Music")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .glass(cornerRadius: 30)
                    }
                }

                Button("Identify another") { shazam.reset() }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 30)
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
