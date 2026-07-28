//
//  AIMixView.swift
//  Sonava
//
//  Natural-language mix creation. A flagship Sonava Pro feature.
//

import SwiftUI

struct AIMixView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var mix: AIMixService.Mix?
    @State private var failed = false
    @State private var showPaywall = false

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !isGenerating
    }
    @FocusState private var focused: Bool

    /// Example prompts. The English string is the catalog key; the chip shows
    /// its translation and, when tapped, fills the field with that same
    /// translation — which `AIMixService` understands in either language.
    private let suggestions = [
        "Rainy day focus", "Late night drive", "Morning energy",
        "Deep work, no vocals", "Sad piano", "Epic cinematic", "Cozy jazz"
    ]

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                AuroraBackground(colors: [Theme.accent, Theme.accentPink, Theme.accentDeep],
                                 animated: !proStore.isPro)
                    .opacity(proStore.isPro ? 0.25 : 0.6)

                if proStore.isPro {
                    generator
                } else {
                    lockedState
                }
            }
            .foregroundColor(.white)
            .navigationTitle("AI Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(proStore)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Generator (Pro)

    private var generator: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.screenMargin) {
                Text("Describe a vibe")
                    .font(.system(.title2, design: .rounded).weight(.bold))

                HStack(spacing: Space.m) {
                    Image(systemName: "sparkles").foregroundColor(Theme.accentSoft)
                    // An explicit prompt rather than the implicit placeholder:
                    // the default renders at 2.43:1, and this is the only text
                    // on the screen that tells you what to type.
                    TextField("", text: $prompt,
                              prompt: Text("e.g. rainy Sunday focus, no vocals")
                                .foregroundColor(.white.opacity(0.62)))
                        .focused($focused)
                        .foregroundColor(.white)
                        .submitLabel(.go)
                        .onSubmit(generate)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.l)
                .card(cornerRadius: Radius.card)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Text(LocalizedStringKey(s))
                                .font(.system(.footnote).weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, Space.l).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .onTapGesture { prompt = localized(s); generate() }
                        }
                    }
                }
                .carouselBleed()

                // A dark label on a white capsule cannot be dimmed as a whole:
                // fading both together collapses the contrast between them —
                // measured at 1.81:1. The disabled state gets its own colours
                // instead, and keeps a legible label.
                Button(action: generate) {
                    HStack {
                        if isGenerating { ProgressView().tint(canGenerate ? Theme.background : .white) }
                        Text(isGenerating ? "Composing…" : "Generate mix")
                            .font(.headline)
                    }
                    .foregroundColor(canGenerate ? Theme.background : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.l)
                    .background(Capsule().fill(canGenerate ? Color.white : Color.white.opacity(0.14)))
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.97, dimsWhenDisabled: false))
                .disabled(!canGenerate)

                if failed {
                    Text("Couldn't build a mix. Try another vibe or check your connection.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }

                if let mix {
                    resultHeader(mix)
                    LazyVStack(spacing: 2) {
                        ForEach(mix.songs) { song in
                            Button {
                                audio.play(song, in: mix.songs)
                            } label: {
                                SongRow(song: song, showBadge: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Space.screenMargin)
            .padding(.bottom, 120)
        }
    }

    private func resultHeader(_ mix: AIMixService.Mix) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mix.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("\(mix.songs.count) tracks · on-device AI")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button {
                if let first = mix.songs.first { audio.play(first, in: mix.songs) }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.95))
        }
        .padding(.top, 8)
    }

    private func generate() {
        let text = prompt.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isGenerating else { return }
        focused = false
        failed = false
        isGenerating = true
        Haptics.impact(.medium)
        Task {
            do {
                let result = try await AIMixService.shared.generate(prompt: text)
                mix = result.songs.isEmpty ? nil : result
                failed = result.songs.isEmpty
                if !result.songs.isEmpty { Haptics.success() }
            } catch {
                failed = true
            }
            isGenerating = false
        }
    }

    // MARK: - Locked (free tier)

    private var lockedState: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.5), radius: 18)
            Text("AI Mix is a Pro feature")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Describe any mood or moment and Sonava composes a\nmix for you — instantly, on your device.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Sonava Pro")
                    .font(.headline)
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            Spacer()
        }
        .padding(Space.xxl)
    }
}
