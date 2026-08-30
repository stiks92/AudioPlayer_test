//
//  LiveRadioTests.swift
//  SonavaTests
//
//  The radio booth's mechanics, tested as arithmetic wherever possible.
//
//  ICY parsing is a pure file-scope function; the live state machine is
//  driven through the same internal handlers AVFoundation's observers call,
//  so no test waits on a network or a wall clock — the drop timeout is
//  injected, and the "five seconds since pause" fact comes from an injected
//  clock, not from sleeping through five seconds. Where a real AVPlayer is
//  involved (the live-edge rejoin) the assertion is about *attachment* — a
//  new item replacing the old — which is deterministic; buffer flow is
//  never asserted (that lesson is on the record).
//

import Testing
import Foundation
import AVFoundation
@testable import Sonava

// MARK: - ICY StreamTitle parsing

struct StreamTitleParsingTests {

    @Test("Nothing in, nothing out")
    func emptyIsNil() {
        #expect(parseStreamTitle(nil) == nil)
        #expect(parseStreamTitle("") == nil)
        #expect(parseStreamTitle("   ") == nil)
    }

    @Test("Artist - Title passes through, trimmed")
    func realTitlePasses() {
        #expect(parseStreamTitle("  Burial - Archangel  ") == "Burial - Archangel")
        #expect(parseStreamTitle("Nightflight") == "Nightflight")
    }

    @Test("A bare separator is ICY's way of sending nothing")
    func separatorGarbageIsNil() {
        #expect(parseStreamTitle("-") == nil)
        #expect(parseStreamTitle(" - ") == nil)
        #expect(parseStreamTitle("—") == nil)
    }

    @Test("A bare URL is an ad tag, not a track")
    func urlIsNil() {
        #expect(parseStreamTitle("https://ads.example.com/spot.mp3") == nil)
        #expect(parseStreamTitle("http://station.example/stream") == nil)
    }
}

// MARK: - Live state machine

@MainActor
struct LiveStreamStateTests {

    @Test("A stall mid-air buffers, and a buffer past the timeout is a drop")
    func stallBuffersThenDrops() async {
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.liveDropTimeout = 0.05
        engine.enterLiveModeForTesting()
        engine.play()

        var states: [LiveStreamState] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            engine.onLiveStateChange = { state in
                states.append(state)
                if state == .dropped { done.resume() }
            }
            engine.handleTimeControl(.playing)   // the air arrives
            engine.handleLiveStall()             // and falls out
        }
        #expect(states == [.onAir, .buffering, .dropped],
                "stall must pass through buffering before it is called a drop")
        #expect(engine.isPlaying == false, "a dropped stream is not playing")
    }

    @Test("Recovery cancels the drop countdown")
    func recoveryCancelsDrop() async {
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.liveDropTimeout = 0.05
        engine.enterLiveModeForTesting()
        engine.play()

        engine.handleTimeControl(.playing)
        engine.handleLiveStall()
        // The stream comes back before the timeout: the countdown was
        // cancelled synchronously at this transition, the sleep below only
        // gives a would-be bug room to appear.
        engine.handleTimeControl(.playing)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(engine.liveStreamState == .onAir,
                "a recovered stream must never be dropped by a stale countdown")
    }

    @Test("A failed item is a drop, immediately")
    func failureDrops() {
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.enterLiveModeForTesting()
        engine.play()

        var last: LiveStreamState?
        engine.onLiveStateChange = { last = $0 }
        engine.handleLiveItemFailed()
        #expect(last == .dropped)
        #expect(engine.isPlaying == false)
    }

    @Test("The ICY title is deduplicated and garbage becomes nil")
    func icyDedup() {
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.enterLiveModeForTesting()

        var reported: [String?] = []
        engine.onLiveMetadata = { reported.append($0) }
        engine.ingestStreamTitle("Artist - Title")
        engine.ingestStreamTitle("Artist - Title")   // the station repeats itself
        engine.ingestStreamTitle(" - ")              // then sends nothing dressed up
        engine.ingestStreamTitle(" - ")
        #expect(reported.count == 2, "repeats must not republish")
        #expect(reported.first == "Artist - Title")
        #expect(reported.last == .some(nil), "garbage clears the line rather than printing it")
    }
}

// MARK: - Live resume (real AVPlayer; attachment only, never buffer flow)

@MainActor
struct LiveResumeTests {

    @Test("Tuning back in after more than five seconds rebuilds the item — the live edge, not a stale buffer")
    func longPauseRejoinsLiveEdge() throws {
        let url = try TestAudioFile.makeTone(named: "live-resume.m4a", seconds: 0.3)
        defer { TestAudioFile.cleanUp(url) }
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: url, isLive: true, autoplay: false)
        let before = try #require(engine.currentItemForTesting)

        engine.pause()
        engine.nowProvider = { Date().addingTimeInterval(6) }   // six seconds pass, instantly
        engine.play()
        let after = try #require(engine.currentItemForTesting)
        #expect(after !== before, "a long live pause must rejoin the edge with a fresh item")
    }

    @Test("A short pause resumes in place")
    func shortPauseResumesInPlace() throws {
        let url = try TestAudioFile.makeTone(named: "live-resume-short.m4a", seconds: 0.3)
        defer { TestAudioFile.cleanUp(url) }
        let engine = RemoteAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: url, isLive: true, autoplay: false)
        let before = try #require(engine.currentItemForTesting)

        engine.pause()
        engine.nowProvider = { Date().addingTimeInterval(2) }
        engine.play()
        let after = try #require(engine.currentItemForTesting)
        #expect(after === before, "a blip of a pause must not tear the stream down")
    }
}

// MARK: - Radio Browser mapping

struct RadioStationMappingTests {

    private func songs(from json: String) throws -> [Song] {
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8))
        return stations.compactMap { RadioBrowserService.shared.map($0) }
    }

    @Test("Bitrate and codec ride into the song when the directory reports them")
    func qualityRidesThrough() throws {
        let mapped = try songs(from: """
        [{"stationuuid":"u1","name":"Jazz24","url":"http://s.example/x",
          "country":"Germany","tags":"jazz","bitrate":256,"codec":"AAC+"}]
        """)
        let song = try #require(mapped.first)
        #expect(song.bitRate == 256)
        #expect(song.qualityParts.format == "AAC+")
        #expect(song.qualityParts.kbps == 256)
    }

    @Test("Unreported quality stays absent — zero guessing")
    func absentQualityStaysAbsent() throws {
        let mapped = try songs(from: """
        [{"stationuuid":"u2","name":"Mystery FM","url":"http://s.example/y",
          "country":"","tags":"talk","bitrate":0,"codec":"UNKNOWN"},
         {"stationuuid":"u3","name":"Silent Keys","url":"http://s.example/z"}]
        """)
        #expect(mapped.count == 2)
        for song in mapped {
            #expect(song.bitRate == nil)
            #expect(song.qualityParts.format == nil)
            #expect(song.qualityParts.kbps == nil)
        }
    }
}

// MARK: - AudioManager live facts (drives the shared singleton → LibrarySuite)

extension LibrarySuite {

    @MainActor
    @Suite(.serialized)
    struct LiveFactsTests {

        init() {
            // A singleton: a previous test's queue must not be mistaken for
            // the state under test.
            AudioManager.shared.stop()
        }

        /// A station with no stream URL at all: `load` records it as current
        /// and returns before touching any engine — no audio session for the
        /// parallel suites to fight over.
        private func station(_ id: String) -> Song {
            Song(id: "radio:\(id)", title: "Station \(id)", artist: "Country",
                 album: "Radio", source: .radio, fileExtension: "", isLive: true,
                 gradientHex: Palette.hex(for: 0))
        }

        @Test("The ICY title belongs to one station and dies with the change")
        func icyResetsOnStationChange() {
            let audio = AudioManager.shared
            let a = station("a"), b = station("b")
            audio.play(a, in: [a, b])
            audio.handleLiveMetadata("Artist - Title")
            #expect(audio.liveNowPlaying == "Artist - Title")
            audio.next()
            #expect(audio.currentSong?.id == b.id)
            #expect(audio.liveNowPlaying == nil,
                    "the next station must not wear the last one's title")
            audio.stop()
        }

        @Test("A dropped stream stops in place — it never advances the dial")
        func droppedStopsInPlace() {
            let audio = AudioManager.shared
            let a = station("a"), b = station("b")
            audio.play(a, in: [a, b])
            audio.handleLiveState(.dropped)
            #expect(audio.liveState == .dropped)
            #expect(audio.currentSong?.id == a.id,
                    "a drop is a fact about this station, not a skip to the next one")
            #expect(audio.isPlaying == false)
            audio.stop()
        }
    }
}
