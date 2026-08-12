//
//  RecapView.swift
//  Sonava
//
//  «Ваш год» — the November ritual on the biography's data.
//
//  Positioning rules from the plan: the numbers are counted on the phone
//  and say so (privacy is the differentiator, not a footnote), and the
//  recap is about the COLLECTION — discoveries, oldest companions — not a
//  minutes-listened flex, which the research called the weakest part of
//  the Wrapped formula.
//

import SwiftUI

struct RecapView: View {
    let year: String
    @EnvironmentObject private var journeyStore: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareableImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let recap = journeyStore.recap(year: year) {
                    ScrollView {
                        content(recap)
                            .padding(Space.screenMargin)
                            .padding(.bottom, 40)
                    }
                } else {
                    Text("No listening in this year yet.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Your year")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.image]) }
        }
        .preferredColorScheme(.dark)
    }

    private func content(_ recap: JourneyStore.Recap) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: recap.year)
                    .font(.sonavaFigure)
                Text("plays this year: \(recap.plays)")
                    .font(.sonavaFact)
                    .foregroundColor(Theme.textSecondary)
                if let previous = recap.previousYearPlays, previous > 0 {
                    let delta = Int((Double(recap.plays - previous) / Double(previous) * 100).rounded())
                    // The sign and the % are data, not format: a literal %
                    // inside an interpolated key silently misses the
                    // catalogue and ships English — this frame caught it.
                    let figure = (delta >= 0 ? "+" : "") + "\(delta)%"
                    Text("\(figure) vs last year")
                        .font(.sonavaFact)
                        .foregroundColor(Theme.accentSoft)
                }
            }

            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: "Top artists", fact: "")
                ForEach(Array(recap.topArtists.enumerated()), id: \.offset) { index, artist in
                    HStack(spacing: Space.m) {
                        Text(verbatim: String(format: "%02d", index + 1))
                            .font(.sonavaOrdinal).foregroundColor(Theme.accentSoft)
                        Text(artist.name).font(.sonavaRowTitle)
                        Spacer()
                        Text(verbatim: "\(artist.plays)")
                            .font(.sonavaFact).foregroundColor(Theme.textTertiary)
                    }
                }
            }

            if !recap.discoveries.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Department(title: "Discovered this year", fact: "")
                    Text(recap.discoveries.joined(separator: " · "))
                        .font(.system(.subheadline))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if let companion = recap.oldestCompanion {
                VStack(alignment: .leading, spacing: 4) {
                    Department(title: "Still with you", fact: "")
                    Text(verbatim: companion.name).font(.sonavaName)
                    Text("in your rotation since \(companion.since)")
                        .font(.sonavaFact)
                        .foregroundColor(Theme.accentSoft)
                }
            }

            Text("Counted on this phone. Your listening never leaves it.")
                .font(.footnote)
                .foregroundColor(Theme.textTertiary)

            Button {
                shareItem = RecapCardRenderer.render(recap)
            } label: {
                Text("Share the card")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityIdentifier("recap.share")
        }
    }
}

/// The story-format share card: 1080×1350, black paper, the year enormous,
/// the collection's headline facts — and the privacy line, because it is
/// the differentiator, printed on the artifact itself.
struct RecapShareCard: View {
    let recap: JourneyStore.Recap

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(verbatim: recap.year)
                .font(.system(size: 200, weight: .bold))
            // Sizes on this card sit at or above the token lint's display
            // floor on purpose: this is a fixed 1080-pt canvas rendered to
            // PNG, but the floor keeps the rule simple — no allowlists.
            Text("MY YEAR IN MUSIC")
                .font(.system(size: 38, weight: .heavy))
                .kerning(6)
                .foregroundColor(Color(hex: 0xD9A441))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(recap.topArtists.prefix(3).enumerated()), id: \.offset) { index, artist in
                    HStack(spacing: 18) {
                        Text(verbatim: String(format: "%02d", index + 1))
                            .font(.system(size: 40, design: .monospaced))
                            .foregroundColor(Color(hex: 0xD9A441))
                        Text(artist.name)
                            .font(.system(size: 44, weight: .semibold))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("plays this year: \(recap.plays)")
                        .font(.system(size: 38, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Counted on this phone. Your listening never leaves it.")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Text(verbatim: "SONAVA")
                    .font(.system(size: 38, weight: .black, design: .serif))
            }
        }
        .padding(64)
        .frame(width: 1080, height: 1350, alignment: .topLeading)
        .background(Color(hex: 0x0D0B09))
        .foregroundColor(Color(hex: 0xF2EDE4))
    }
}

enum RecapCardRenderer {
    @MainActor
    static func render(_ recap: JourneyStore.Recap) -> ShareableImage? {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return ShareableImage(image: image)
    }
}
