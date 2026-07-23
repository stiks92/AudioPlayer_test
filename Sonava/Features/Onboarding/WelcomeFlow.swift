//
//  WelcomeFlow.swift
//  Sonava
//
//  First-run flow: the welcome slides, then a soft paywall. Placing the trial
//  offer here is deliberate — the overwhelming majority of subscription trials
//  start on the day of install, so this is the highest-leverage moment to make
//  the offer. It's soft: "Maybe later" always lets the user into the free app.
//

import SwiftUI

struct WelcomeFlow: View {
    let onFinish: () -> Void

    @EnvironmentObject private var proStore: ProStore
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            if showPaywall {
                PaywallView(isOnboarding: true, onContinue: onFinish)
                    .transition(.opacity)
            } else {
                OnboardingView(onFinish: finishedSlides)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showPaywall)
    }

    private func finishedSlides() {
        // Already a subscriber (or a DEBUG unlock): don't pitch — go straight in.
        if proStore.isPro {
            onFinish()
        } else {
            showPaywall = true
        }
    }
}
