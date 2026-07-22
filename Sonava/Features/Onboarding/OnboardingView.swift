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
        let icon: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let colors: [Color]
    }

    private let slides: [Slide] = [
        Slide(icon: "square.stack.3d.up.fill",
              title: "All your music, one player",
              subtitle: "Streaming, internet radio, podcasts and your own server — unified in one beautiful place.",
              colors: [Theme.accent, Theme.accentDeep]),
        Slide(icon: "magnifyingglass",
              title: "Search everything at once",
              subtitle: "One query fans out across Audius, Apple, Deezer and your library — full tracks and previews together.",
              colors: [Color(hex: 0x00C6FF), Color(hex: 0x0072FF)]),
        Slide(icon: "sparkles",
              title: "AI Mix & Shazam",
              subtitle: "Describe a vibe and get an instant mix. Identify what's playing around you in a tap.",
              colors: [Theme.accentPink, Color(hex: 0x8E2DE2)]),
        Slide(icon: "lock.shield.fill",
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        slideView(slide).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 20)

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
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.97))
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .foregroundColor(.white)
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: slide.icon)
                .font(.system(size: 76, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.4), radius: 20)
            VStack(spacing: 14) {
                Text(slide.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
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
