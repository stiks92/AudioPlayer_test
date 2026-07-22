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
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var isPurchasing = false

    private let perks: [(String, String, String)] = [
        ("sparkles", "AI Mix", "Describe a vibe — get an instant, on-device mix."),
        ("dot.radiowaves.left.and.right", "Every source, unified", "Streaming, radio, podcasts & your own servers."),
        ("waveform.path.ecg", "Studio EQ & spatial", "Shape your sound with pro presets."),
        ("arrow.down.circle", "Offline & lossless", "Download free-licensed tracks in top quality."),
        ("heart.fill", "Support indie dev", "No ads. No tracking. Ever.")
    ]

    var body: some View {
        ZStack {
            AuroraBackground(colors: [Theme.accent, Theme.accentPink, Theme.accentDeep])

            ScrollView {
                VStack(spacing: 22) {
                    closeRow
                    hero
                    perksList
                    plans
                    subscribeButton
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .foregroundColor(.white)
        .task {
            if proStore.products.isEmpty { await proStore.loadProducts() }
            selectedID = selectedID ?? proStore.products.first?.id
        }
        .onChange(of: proStore.isPro) { _, pro in
            if pro { dismiss() }
        }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.5), radius: 16)
            Text("Sonava Pro")
                .font(.system(size: 34, design: .rounded).weight(.heavy))
            Text("The one player for all your music —\nunlocked to the fullest.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var perksList: some View {
        VStack(spacing: 14) {
            ForEach(perks, id: \.1) { icon, title, subtitle in
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.ultraThinMaterial))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        Text(subtitle).font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
        .glass(cornerRadius: 22)
    }

    @ViewBuilder
    private var plans: some View {
        if proStore.products.isEmpty {
            Text(proStore.isLoadingProducts ? "Loading plans…" : "Plans will be available at launch.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else {
            VStack(spacing: 12) {
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
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName.isEmpty ? product.id : product.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(proStore.period(for: product))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var subscribeButton: some View {
        Button {
            guard let id = selectedID,
                  let product = proStore.products.first(where: { $0.id == id }) else { return }
            isPurchasing = true
            Task {
                await proStore.purchase(product)
                isPurchasing = false
            }
        } label: {
            HStack {
                if isPurchasing { ProgressView().tint(Theme.background) }
                Text(isPurchasing ? "Processing…" : "Unlock Sonava Pro")
                    .font(.headline)
            }
            .foregroundColor(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
        .disabled(proStore.products.isEmpty || selectedID == nil || isPurchasing)
        .opacity(proStore.products.isEmpty ? 0.5 : 1)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Restore purchases") {
                Task { await proStore.restore() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.85))

            Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24h before the period ends. Manage in Settings.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}
