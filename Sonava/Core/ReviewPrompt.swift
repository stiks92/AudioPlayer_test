//
//  ReviewPrompt.swift
//  Sonava
//
//  Asks for an App Store rating at a genuinely good moment — never on launch,
//  never after an error. A high, recent rating is one of the strongest ASO
//  signals, and Apple weighs the *trajectory* of recent reviews, so we only
//  spend a prompt when the user has just done something they enjoyed.
//
//  Apple already caps the system prompt to ~3 per year; this adds taste on top:
//  a weighted signal threshold and a long cooldown so we ask rarely and well.
//

import Foundation
import Combine

@MainActor
final class ReviewPrompt: ObservableObject {

    /// Flips true when the moment is right; the view layer observes it, calls
    /// the system request, then acknowledges with `markPresented()`.
    @Published private(set) var shouldPresent = false

    /// Things a user does that signal genuine satisfaction, weighted by how
    /// strong a signal each is.
    enum Event {
        case trackFinished     // listened all the way through
        case playlistCreated   // invested in the library
        case mixGenerated      // got value from a Pro feature

        var weight: Int {
            switch self {
            case .trackFinished:   return 1
            case .playlistCreated: return 4
            case .mixGenerated:    return 3
            }
        }
    }

    private let defaults: UserDefaults
    private let threshold: Int
    private let cooldown: TimeInterval

    private let signalsKey = "review.signals.v1"
    private let lastAskedKey = "review.lastAsked.v1"

    init(
        defaults: UserDefaults = .standard,
        threshold: Int = 8,
        cooldownDays: Int = 120
    ) {
        self.defaults = defaults
        self.threshold = threshold
        self.cooldown = Double(cooldownDays) * 86_400
    }

    private(set) var accumulatedSignals: Int {
        get { defaults.integer(forKey: signalsKey) }
        set { defaults.set(newValue, forKey: signalsKey) }
    }

    private var lastAsked: Date? {
        defaults.object(forKey: lastAskedKey) as? Date
    }

    /// Records a positive signal and opens the gate if the threshold is crossed
    /// and we're past the cooldown.
    func record(_ event: Event, now: Date = Date()) {
        // Once asked, stay quiet for the whole cooldown — no counting, no nagging.
        if let last = lastAsked, now.timeIntervalSince(last) < cooldown { return }

        accumulatedSignals += event.weight
        if accumulatedSignals >= threshold {
            shouldPresent = true
        }
    }

    /// The view has shown (or the system suppressed) the prompt: reset and start
    /// the cooldown so we don't ask again for a long time.
    func markPresented(now: Date = Date()) {
        shouldPresent = false
        accumulatedSignals = 0
        defaults.set(now, forKey: lastAskedKey)
    }
}
