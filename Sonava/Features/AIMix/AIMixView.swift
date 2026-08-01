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
                // The aurora belongs to the pitch, not to the tool.
                //
                // It was the only sheet in the app with a coloured ground —
                // (48,28,55) at the trailing edge where Settings, Stats,
                // Servers, Equalizer and Scrobbling all measure (8,8,12) — and
                // Apple's iOS 26 guidance is that a sheet takes its material
                // from the system. A subscriber using the feature now gets the
                // same ground as every other sheet; a free listener still gets
                // the atmosphere, because there the screen *is* an offer.
                if !proStore.isPro {
                    AuroraBackground(colors: [Theme.accent, Theme.accentWarm, Theme.accentDeep])
                        .opacity(0.6)
                }

                if proStore.isPro {
                    generator
                } else {
                    lockedState
                }
            }
            .foregroundColor(.white)
            .navigationTitle("AI Mix")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
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
                    .font(.system(.title2).weight(.bold))

                HStack(spacing: Space.m) {
                    SonavaIcon(glyph: .aiMix, size: 20, tint: Theme.accentSoft)
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
                // Matched to the token field on the Scrobbling sheet, which is
                // visually the same object and measured 45pt against this
                // one's 54, with a different corner radius on the same fill
                // and the same stroke.
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .card(cornerRadius: Radius.control)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(suggestions, id: \.self) { s in
                            Text(LocalizedStringKey(s))
                                .font(.sonavaRowMeta.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, Space.l)
                                // 31.7pt before this — under Apple's 44pt
                                // minimum, and the only chips in the app that
                                // were: Radio, Podcasts, the EQ presets and
                                // both segmented controls all measure exactly
                                // 44. Same fill as an unselected filter chip,
                                // too; these were 0.12 against everyone
                                // else's 0.08.
                                .frame(minHeight: Space.hitTarget)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .contentShape(Capsule())
                                .onTapGesture { prompt = localized(s); generate() }
                        }
                    }
                }
                .carouselBleed()

                // The disabled colours that used to be written out here now
                // live in the style, because a review found the identical
                // uncorrected bug on two other screens while this one carried
                // the fix as a local comment.
                Button(action: generate) {
                    HStack {
                        if isGenerating { ProgressView() }
                        Text(isGenerating ? "Composing…" : "Generate mix")
                    }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
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
                    .font(.system(.title3).weight(.bold))
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
            SonavaIcon(glyph: .aiMix, size: 60)
                .shadow(color: .white.opacity(0.5), radius: 18)
            Text("AI Mix is a Pro feature")
                .font(.system(.title2).weight(.bold))
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
