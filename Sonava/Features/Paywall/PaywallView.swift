//
//  PaywallView.swift
//  Sonava
//
//  Sonava Pro upsell. Designed to feel like a premium product worth paying
//  for — clear value, beautiful presentation, honest copy.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    /// When presented as the last step of onboarding it becomes a *soft*
    /// paywall: a skip appears and finishing (purchase or skip) calls
    /// `onContinue` instead of dismissing a sheet.
    var isOnboarding = false
    var onContinue: (() -> Void)? = nil

    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var isPurchasing = false

    /// A Pro selling point. Typing the copy as `LocalizedStringKey` is what
    /// makes the literals below both translatable and extractable — passing
    /// plain strings to `Text` silently skips translation.
    private struct Perk: Identifiable {
        let icon: SonavaIcon.Glyph
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let id: String
    }

    // Every perk here is a real, Pro-gated feature — no promises the app can't
    // keep. App Review checks this, and so do users.
    /// The five broadest reasons to subscribe, in the order they persuade.
    /// Everything else that is gated is listed underneath rather than given a
    /// row of its own — a paywall that lists everything persuades of nothing.
    private let perks: [Perk] = [
        Perk(icon: .download, title: "Offline downloads",
             subtitle: "Save full tracks and listen with no signal.", id: "offline"),
        Perk(icon: .equalizer, title: "10-band equalizer",
             subtitle: "Studio presets and per-band control.", id: "eq"),
        Perk(icon: .aiMix, title: "AI Mix",
             subtitle: "Describe a vibe, get an instant mix.", id: "aimix"),
        Perk(icon: .palette, title: "Make it yours",
             subtitle: "Six accent themes and six app icons.", id: "themes"),
        Perk(icon: .heart, title: "Support indie dev",
             subtitle: "No ads. No tracking. Ever.", id: "indie")
    ]

    var body: some View {
        ZStack {
            AuroraBackground(colors: [Theme.accent, Theme.accentWarm, Theme.accentDeep])

            ScrollView {
                VStack(spacing: Space.xl) {
                    closeRow
                    hero
                    perksList
                    plans
                    if isOnboarding { maybeLater }
                    footer
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, Space.xxl)
            }
            // The action is pinned rather than scrolled.
            //
            // Measured, after two wrong fixes. The first diagnosis — "the page
            // overflows the screen" — was wrong: the page scrolls, and text
            // passing under the home indicator is what scrolling text does.
            // Restructuring the background around that theory changed the
            // numbers by nothing at all, which is how the theory died.
            //
            // What is a defect is narrower, and only visible in Russian: the
            // longer copy pushes the purchase control to 802–854pt while the
            // home indicator occupies 858–871pt, so the bottom of a *control*
            // sits inside the system's edge-gesture strip at rest. Pinning it
            // puts the one thing this screen exists for permanently above that
            // strip, in both languages, and lets the perks scroll behind it.
            .safeAreaInset(edge: .bottom, spacing: 0) { pinnedAction }
        }
        .foregroundColor(.white)
        .task {
            if proStore.products.isEmpty { await proStore.loadProducts() }
            selectedID = selectedID ?? proStore.trialProduct?.id ?? proStore.products.first?.id
        }
        .onChange(of: proStore.isPro) { _, pro in
            if pro { finish() }
        }
    }

    /// Purchase succeeded or the user skipped: advance onboarding, or dismiss
    /// the sheet in the normal (Settings / feature-gate) presentation.
    private func finish() {
        if let onContinue { onContinue() } else { dismiss() }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            // In onboarding the escape hatch is the "Maybe later" button at the
            // bottom, so the top corner stays clean.
            if !isOnboarding {
                Button { dismiss() } label: {
                    SonavaIcon(glyph: .close, size: 16, tint: .white.opacity(0.8))
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .interactiveGlass(in: Circle())
                        .contentShape(Circle())
                }
                .identified(AccessibilityID.paywallClose, label: "Close")
            }
        }
        .frame(height: 34)
        .padding(.top, 8)
    }

    private var maybeLater: some View {
        Button("Maybe later") { finish() }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white.opacity(0.8))
            .padding(.top, 2)
            .accessibilityIdentifier("paywall.skip")
    }

    private var hero: some View {
        VStack(spacing: Space.m) {
            // The app's own mark rather than a stock glyph: `sparkles` was
            // doing duty as both the product hero and one feature's icon
            // 700pt below, so the image standing for Sonava was one Apple
            // ships on every device.
            SonavaMark(height: 46)
                .shadow(color: .white.opacity(0.35), radius: 16)
            Text("Sonava Pro")
                .font(.sonavaMasthead)
            Text("The one player for all your music —\nunlocked to the fullest.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var perksList: some View {
        VStack(spacing: Space.l) {
            ForEach(perks) { perk in
                HStack(alignment: .top, spacing: Space.l) {
                    SonavaIcon(glyph: perk.icon, size: 19, tint: Theme.accentSoft)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.accent.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(perk.title).font(.system(.subheadline).weight(.semibold))
                        Text(perk.subtitle).font(.system(.caption)).foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                }
            }
            Text("Plus unlimited self-hosted servers searched together, scrobbling to ListenBrainz, and your full listening history.")
                .font(.system(.caption))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(Space.l)
        .card(cornerRadius: Radius.card)
    }

    @ViewBuilder
    private var plans: some View {
        if proStore.isLoadingProducts {
            // Filled skeletons in the plans' own footprint, so the composition
            // does not collapse and then shove the CTA ~200pt down the page
            // when the real cards arrive.
            //
            // Filled, not dashed. A dashed outline is the universal drawing for
            // "not built yet"; on the screen that asks for money it read as an
            // unfinished wireframe shipped by accident, which is what a review
            // called it. A solid block reads as "loading", which is true.
            VStack(spacing: Space.m) {
                Text("Loading plans…")
                    .font(.sonavaCardSubtitle.weight(.semibold))
                    .foregroundColor(.white)
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 68)
                }
            }
        } else if proStore.products.isEmpty {
            // Nothing to sell yet, so this states that and offers the only
            // action that is actually true right now. Previously the reader
            // finished the feature list and landed on two empty rectangles:
            // the app's monetisation screen had no primary action at all.
            VStack(spacing: Space.m) {
                Text("Plans will be available at launch.")
                    .font(.sonavaCardSubtitle.weight(.semibold))
                    .foregroundColor(.white)
                Text("Everything above is built and waiting. Nothing is on sale yet, so there is nothing to decide today.")
                    .font(.system(.footnote))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                // The button itself is pinned to the bottom, not here.
            }
        } else {
            VStack(spacing: Space.m) {
                ForEach(proStore.products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedID == product.id
        return Button {
            Haptics.selection()
            selectedID = product.id
        } label: {
            HStack(spacing: Space.m) {
                // The family's own radio dial: a ring, filled when chosen.
                ZStack {
                    Circle().strokeBorder(isSelected ? Color.white : .white.opacity(0.5),
                                          lineWidth: 1.6)
                    if isSelected {
                        Circle().fill(Color.white).padding(4.5)
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName.isEmpty ? product.id : product.displayName)
                        .font(.system(.subheadline).weight(.semibold))
                    Text(proStore.period(for: product))
                        .font(.system(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(.callout).weight(.bold))
            }
            .padding(Space.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedProduct: Product? {
        proStore.products.first { $0.id == selectedID }
    }

    /// Benefit-driven CTA: lead with the free trial when the chosen plan has
    /// one — "Start Free Trial" converts better than "Subscribe".
    private var ctaTitle: LocalizedStringKey {
        if isPurchasing { return "Processing…" }
        if let product = selectedProduct, proStore.hasFreeTrial(product) { return "Start Free Trial" }
        return "Unlock Sonava Pro"
    }

    /// The screen's one action, held above the home indicator.
    ///
    /// Onboarding is the exception: there the page already ends with "Maybe
    /// later", and pinning a second escape would leave the slide with two
    /// buttons doing one job.
    @ViewBuilder
    private var pinnedAction: some View {
        if !proStore.products.isEmpty || !isOnboarding {
            VStack(spacing: 0) {
                if proStore.products.isEmpty {
                    Button("Continue with the free version") { finish() }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                        .accessibilityIdentifier("paywall.continueFree")
                } else {
                    purchaseControls
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            // The perks scroll behind this, so it needs a ground of its own or
            // a track title would read through the button's own copy.
            .background(.ultraThinMaterial)
        }
    }

    private var purchaseControls: some View {
        VStack(spacing: 8) {
            Button {
                guard let product = selectedProduct else { return }
                isPurchasing = true
                Task {
                    await proStore.purchase(product)
                    isPurchasing = false
                }
            } label: {
                HStack {
                    if isPurchasing { ProgressView() }
                    Text(ctaTitle)
                }
            }
            // Was a hand-rolled white capsule, invisible in a build with no
            // products and therefore free to drift from the shared style the
            // moment there are some.
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(selectedID == nil || isPurchasing)
            .accessibilityIdentifier("paywall.subscribe")

            // Reassurance under the trial CTA.
            if let product = selectedProduct, let trial = proStore.trialText(for: product) {
                Text("\(trial), then \(product.displayPrice) \(proStore.period(for: product)). Cancel anytime.")
                    .font(.system(.caption2))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.m) {
            Button("Restore purchases") {
                Task { await proStore.restore() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.85))

            Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24h before the period ends. Manage in Settings.")
                .font(.system(.caption2))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}
