//
//  ProStore.swift
//  Sonava
//
//  Sonava Pro entitlement + purchasing via StoreKit 2. Degrades gracefully
//  when products aren't configured yet in App Store Connect (the UI still
//  renders; purchase is simply unavailable). Configure the product IDs below
//  and add a StoreKit configuration file to test purchases locally.
//

import StoreKit
import SwiftUI

@MainActor
final class ProStore: ObservableObject {

    @Published private(set) var isPro = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published var lastError: String?

    /// Configure these to match your App Store Connect subscription group.
    /// The monthly and yearly products should carry a 7-day free-trial
    /// introductory offer — the onboarding paywall surfaces it automatically.
    let productIDs = [
        "com.sonava.pro.monthly",
        "com.sonava.pro.yearly",
        "com.sonava.pro.lifetime"
    ]

    private let overrideKey = "pro.dev.override.v1"
    private var updatesTask: Task<Void, Never>?

    init() {
        // Local developer override (persists a manual unlock, e.g. from Settings in DEBUG).
        if UserDefaults.standard.bool(forKey: overrideKey) { isPro = true }
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: productIDs)
            // Keep a stable order: monthly, yearly, lifetime.
            products = productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchase / restore

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    Haptics.success()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
            Haptics.warning()
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        if UserDefaults.standard.bool(forKey: overrideKey) { isPro = true; return }
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isPro = entitled
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    // MARK: - Developer override (DEBUG only)

    func setDeveloperOverride(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: overrideKey)
        Task { await refreshEntitlements() }
        if on { isPro = true }
    }

    var developerOverride: Bool {
        UserDefaults.standard.bool(forKey: overrideKey)
    }

    // MARK: - Display helpers

    func displayPrice(for product: Product) -> String {
        product.displayPrice
    }

    func period(for product: Product) -> String {
        guard let sub = product.subscription else { return "one-time" }
        return "per \(unitName(sub.subscriptionPeriod))"
    }

    /// The product whose trial the onboarding CTA should offer — the yearly
    /// plan if it has one, else any plan with a free trial.
    var trialProduct: Product? {
        products.first { $0.id.contains("yearly") && hasFreeTrial($0) }
            ?? products.first { hasFreeTrial($0) }
    }

    func hasFreeTrial(_ product: Product) -> Bool {
        product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    /// e.g. "7-day free trial" — nil when the product has no trial offer.
    func trialText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        let unit = unitName(period, plural: period.value > 1)
        return "\(period.value)-\(unit) free trial"
    }

    private func unitName(_ period: Product.SubscriptionPeriod, plural: Bool = false) -> String {
        let base: String
        switch period.unit {
        case .day: base = "day"
        case .week: base = "week"
        case .month: base = "month"
        case .year: base = "year"
        @unknown default: base = "period"
        }
        return plural ? "\(base)s" : base
    }
}
