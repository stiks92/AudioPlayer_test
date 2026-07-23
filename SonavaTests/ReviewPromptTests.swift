//
//  ReviewPromptTests.swift
//  SonavaTests
//
//  The rating prompt only helps ASO if it fires at the right moment and stays
//  quiet otherwise. These pin the gate: threshold, cooldown, and reset.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
struct ReviewPromptTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "review-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Below the threshold it stays silent")
    func silentBelowThreshold() {
        let prompt = ReviewPrompt(defaults: freshDefaults(), threshold: 8)
        prompt.record(.trackFinished)   // +1
        prompt.record(.trackFinished)   // +2
        #expect(prompt.shouldPresent == false)
    }

    @Test("Crossing the threshold opens the gate")
    func opensAtThreshold() {
        let prompt = ReviewPrompt(defaults: freshDefaults(), threshold: 8)
        prompt.record(.playlistCreated) // +4
        prompt.record(.mixGenerated)    // +3  -> 7
        #expect(prompt.shouldPresent == false)
        prompt.record(.trackFinished)   // +1  -> 8
        #expect(prompt.shouldPresent)
    }

    @Test("A stronger signal reaches the gate faster")
    func weightsMatter() {
        let prompt = ReviewPrompt(defaults: freshDefaults(), threshold: 8)
        prompt.record(.playlistCreated) // 4
        prompt.record(.playlistCreated) // 8
        #expect(prompt.shouldPresent)
    }

    @Test("After presenting, it resets and goes quiet for the cooldown")
    func cooldownSilencesFurtherSignals() {
        let defaults = freshDefaults()
        let prompt = ReviewPrompt(defaults: defaults, threshold: 8, cooldownDays: 120)
        let day0 = Date(timeIntervalSince1970: 1_000_000)

        prompt.record(.playlistCreated, now: day0)
        prompt.record(.playlistCreated, now: day0)
        #expect(prompt.shouldPresent)
        prompt.markPresented(now: day0)
        #expect(prompt.shouldPresent == false)

        // A day later, even a big signal must not re-open the gate.
        let day1 = day0.addingTimeInterval(86_400)
        prompt.record(.playlistCreated, now: day1)
        prompt.record(.playlistCreated, now: day1)
        #expect(prompt.shouldPresent == false, "asked again inside the cooldown")
    }

    @Test("After the cooldown expires it can ask again")
    func asksAgainAfterCooldown() {
        let defaults = freshDefaults()
        let prompt = ReviewPrompt(defaults: defaults, threshold: 8, cooldownDays: 120)
        let day0 = Date(timeIntervalSince1970: 2_000_000)
        prompt.record(.playlistCreated, now: day0)
        prompt.record(.playlistCreated, now: day0)
        prompt.markPresented(now: day0)

        let later = day0.addingTimeInterval(121 * 86_400)
        prompt.record(.playlistCreated, now: later)
        prompt.record(.playlistCreated, now: later)
        #expect(prompt.shouldPresent, "should be eligible again after the cooldown")
    }

    @Test("The accumulated count survives a relaunch")
    func signalsPersist() {
        let defaults = freshDefaults()
        ReviewPrompt(defaults: defaults, threshold: 8).record(.playlistCreated)

        let relaunched = ReviewPrompt(defaults: defaults, threshold: 8)
        #expect(relaunched.accumulatedSignals == 4)
    }
}
