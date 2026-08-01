//
//  OnboardingView.swift
//  Sonava
//
//  First-run welcome. Highlights what makes Sonava different.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let glyph: SonavaIcon.Glyph?
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let colors: [Color]
    }

    private let slides: [Slide] = [
        // `nil` glyph = the app's own mark. Only the opening slide gets it;
        // repeating a logo on all four would make it wallpaper. The rest are
        // drawn glyphs — the first four screens of the app are not the place
        // for symbols every other app on the phone also ships.
        Slide(glyph: nil,
              title: "All your music, one player",
              subtitle: "Streaming, internet radio, podcasts and your own server — unified in one beautiful place.",
              colors: [Theme.accent, Theme.accentDeep]),
        Slide(glyph: .search,
              title: "Search everything at once",
              subtitle: "One query fans out across Audius, Apple, Deezer and your library — full tracks and previews together.",
              colors: [Color(hex: 0x00C6FF), Color(hex: 0x0072FF)]),
        Slide(glyph: .aiMix,
              title: "AI Mix & Shazam",
              subtitle: "Describe a vibe and get an instant mix. Identify what's playing around you in a tap.",
              colors: [Theme.accentWarm, Color(hex: 0xB4552D)]),
        Slide(glyph: .server,
              title: "Private by design",
              subtitle: "On-device intelligence, no tracking, no ads. Your taste stays yours.",
              colors: [Color(hex: 0x11998E), Theme.positive])
    ]

    var body: some View {
        ZStack {
            AuroraBackground(colors: slides[page].colors)
                .animation(.easeInOut(duration: 0.6), value: page)

            VStack(spacing: 0) {
                Button("Skip", action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .hitTarget()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.top, Space.m)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        slideView(slide).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, Space.screenMargin)

                Button {
                    if page < slides.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < slides.count - 1 ? "Continue" : "Start listening")
                        .font(.headline)
                        .foregroundColor(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.97))
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, 40)
            }
        }
        .foregroundColor(.white)
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: Space.xxl) {
            Spacer()
            // The first frame of the app is the app's own mark, not a symbol
            // Apple ships on every device. `SonavaMark` existed and appeared on
            // exactly one screen in the whole product — the paywall — while the
            // screen a person actually sees first opened with
            // `square.stack.3d.up.fill`, a glyph that also duplicated the tab
            // bar's old library icon.
            Group {
                if let glyph = slide.glyph {
                    SonavaIcon(glyph: glyph, size: 76)
                } else {
                    SonavaMark(height: 76)
                }
            }
            .shadow(color: .white.opacity(0.4), radius: 20)
            VStack(spacing: Space.l) {
                Text(slide.title)
                    .font(.system(.title).weight(.heavy))
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.system(.callout))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.screenMargin)
            Spacer()
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == page ? 1 : 0.35))
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }
}
