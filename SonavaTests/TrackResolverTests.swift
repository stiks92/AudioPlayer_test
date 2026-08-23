//
//  TrackResolverTests.swift
//  SonavaTests
//
//  The hub's engine room, proven: door order, matching rules, cache, and
//  the honest not-found. Every door is a stub — the resolver's job is the
//  ORDER and the ARITHMETIC, not the networks behind them.
//

import Foundation
import Testing
@testable import Sonava

@MainActor
struct TrackResolverTests {

    private func song(_ id: String, _ artist: String = "Vaelo",
                      _ title: String = "Halcyon Drift",
                      source: TrackSource = .local,
                      duration: Double? = 212) -> Song {
        Song(id: id, title: title, artist: artist, album: "L", source: source,
             gradientHex: [0, 1], durationSeconds: duration)
    }

    private let wanted = ForeignTrack(title: "Halcyon Drift", artist: "Vaelo", durationSeconds: 212)

    @Test func filesBeatEveryOtherDoor() async {
        var serverAsked = false
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [self.song("local:1")] },
            serverSearch: { _ in serverAsked = true; return [self.song("srv:1", source: .subsonic)] },
            appleMusicSearch: nil,
            audiusSearch: nil))
        let result = await resolver.resolve(wanted)
        #expect(result == .matched(song("local:1")))
        #expect(!serverAsked, "a local hit must not cost a network call")
    }

    @Test func doorsOpenInOrderUntilOneAnswers() async {
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [] },
            serverSearch: { _ in [] },
            appleMusicSearch: { _ in [self.song("applemusic:9", source: .appleMusic)] },
            audiusSearch: { _ in Issue.record("Audius must not be asked once Apple answered"); return [] }))
        let result = await resolver.resolve(wanted)
        if case .matched(let hit) = result {
            #expect(hit.source == .appleMusic)
        } else {
            Issue.record("expected the subscription door to answer")
        }
    }

    @Test func durationDisagreementIsNotAMatch() async {
        // Same name, 7-minute album cut against the 3:32 we asked for.
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [self.song("local:long", duration: 431)] },
            serverSearch: nil, appleMusicSearch: nil, audiusSearch: nil))
        #expect(await resolver.resolve(wanted) == .notFound,
                "tags agreeing while durations differ by minutes is a different recording")
    }

    @Test func editionsFoldViaTheNormaliser() async {
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [self.song("local:rm", "Vaelo", "Halcyon Drift (Remastered 2011)")] },
            serverSearch: nil, appleMusicSearch: nil, audiusSearch: nil))
        if case .matched = await resolver.resolve(wanted) {} else {
            Issue.record("a remaster edition must match its plain title")
        }
    }

    @Test func honestNotFoundAndCachedSecondAsk() async {
        var asks = 0
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [] },
            serverSearch: { _ in asks += 1; return [] },
            appleMusicSearch: nil, audiusSearch: nil))
        #expect(await resolver.resolve(wanted) == .notFound)
        #expect(await resolver.resolve(wanted) == .notFound)
        #expect(asks == 1, "the second ask must come from the cache, not the network")
    }

    @Test func fullTracksBeatPreviewsInsideOneList() {
        let preview = song("deezer:1", source: .deezer)
        let full = song("audius:1", source: .audius)
        let best = TrackResolver.bestMatch(wanted, in: [preview, full])
        #expect(best?.source == .audius, "a 30-second preview must never outrank a full track")
    }

    @Test func previewIsItsOwnHonestOutcome() async {
        // Nothing full anywhere; iTunes has a 30-second clip.
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [] },
            serverSearch: nil, appleMusicSearch: nil, audiusSearch: { _ in [] },
            previewSearch: { _ in [self.song("itunes:1", source: .itunes)] }))
        let result = await resolver.resolve(wanted)
        if case .preview(let hit) = result {
            #expect(hit.source == .itunes)
        } else {
            Issue.record("a preview must surface as .preview, never as .matched — got \(result)")
        }
    }

    @Test func containmentIsRefusedByDesign() async {
        // "Help" must not match "Help Me Out" however близко the names look.
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [self.song("local:h", "The Band", "Help Me Out")] },
            serverSearch: nil, appleMusicSearch: nil, audiusSearch: nil))
        let result = await resolver.resolve(
            ForeignTrack(title: "Help", artist: "The Band"))
        #expect(result == .notFound,
                "a wrong match plays the wrong song with full confidence — refuse containment")
    }

    @Test func albumAgreementBreaksTies() {
        let want = ForeignTrack(title: "Halcyon Drift", artist: "Vaelo",
                                album: "Nightfold", durationSeconds: 212)
        let live = Song(id: "s:live", title: "Halcyon Drift", artist: "Vaelo",
                        album: "Live at Roskilde", source: .audius,
                        gradientHex: [0, 1], durationSeconds: 212)
        let studio = Song(id: "s:studio", title: "Halcyon Drift", artist: "Vaelo",
                          album: "Nightfold", source: .audius,
                          gradientHex: [0, 1], durationSeconds: 212)
        #expect(TrackResolver.bestMatch(want, in: [live, studio])?.id == "s:studio",
                "when the foreign row names its album, the same album wins the tie")
    }

    @Test func invalidateReopensSettledQuestions() async {
        var round = 0
        let resolver = TrackResolver(doors: .init(
            librarySongs: { round == 0 ? [] : [self.song("local:new")] },
            serverSearch: nil, appleMusicSearch: nil, audiusSearch: nil))
        #expect(await resolver.resolve(wanted) == .notFound)
        round = 1
        #expect(await resolver.resolve(wanted) == .notFound,
                "the cache answers until a door actually changes")
        resolver.invalidate()
        if case .matched = await resolver.resolve(wanted) {} else {
            Issue.record("after invalidate, the newly connected door must be asked")
        }
    }
}
