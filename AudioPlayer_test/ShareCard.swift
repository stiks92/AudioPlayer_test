//
//  ShareCard.swift
//  AudioPlayer_test
//
//  A beautiful, shareable "now playing" card rendered to an image — every
//  share is a tiny advert for the app.
//

import SwiftUI

/// The visual card (fixed size, designed to render crisply via ImageRenderer).
struct NowPlayingShareCard: View {
    let song: Song

    var body: some View {
        ZStack {
            LinearGradient(colors: song.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.12)

            VStack(spacing: 40) {
                Spacer()
                ArtworkImage(song: song, glyphSize: 160)
                    .frame(width: 620, height: 620)
                    .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 50, y: 30)

                VStack(spacing: 14) {
                    Text(song.title)
                        .font(.system(size: 70, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.system(size: 42, weight: .medium))
                        .opacity(0.85)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 60)

                let barHeights: [CGFloat] = [40, 90, 60, 120, 80, 130, 55, 100, 45]
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<barHeights.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 12, height: barHeights[i])
                    }
                }

                Spacer()

                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .bold))
                    Text("Now playing on Aurora")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
                .padding(.bottom, 50)
            }
        }
        .frame(width: 1080, height: 1350)
    }
}

/// Wrapper so we can present a share sheet via `.sheet(item:)`.
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum ShareCardRenderer {
    @MainActor
    static func render(_ song: Song) -> ShareableImage? {
        let renderer = ImageRenderer(content: NowPlayingShareCard(song: song))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return ShareableImage(image: image)
    }
}

/// UIActivityViewController bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
