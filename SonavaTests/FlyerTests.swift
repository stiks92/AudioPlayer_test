//
//  FlyerTests.swift
//  SonavaTests
//
//  The flyer is HTML that travels to strangers, so the tests are about the
//  two ways it could betray someone: executing a malicious track title, or
//  breaking the iTunes terms it depends on.
//

import Foundation
import Testing
@testable import Sonava

struct FlyerTests {

    private func flyer(_ entries: [FlyerEntry]) -> String {
        FlyerBuilder.html(entries: entries, heading: "Records I live with",
                          subtitle: "s", openHint: "h", creditText: "Previews courtesy of")
    }

    @Test func aHostileTitleCannotScriptTheReceiver() {
        let hostile = FlyerEntry(artist: "a<script>alert(1)</script>",
                                 title: "\"><img src=x onerror=alert(2)>", note: "'note'")
        let html = flyer([hostile])
        // The first version of this test grepped for "onerror=alert" and
        // failed on its own success: the payload IS present — as inert,
        // entity-escaped text inside &lt;img …&gt;. What must never appear
        // is a RAW tag or a raw quote-escape out of the attribute.
        #expect(!html.contains("<script>alert"), "raw script tag must not survive")
        #expect(!html.contains("<img"), "raw img tag must not survive")
        #expect(!html.contains("\"><img"), "the attribute must not be escapable")
        #expect(html.contains("&lt;script&gt;"), "the title must render as text, not markup")
    }

    @Test func everyEntryAndItsNoteAppear() {
        let html = flyer([
            FlyerEntry(artist: "Vaelo", title: "Halcyon Drift", note: "with me since 2014"),
            FlyerEntry(artist: "Iri", title: "Drift", note: nil)
        ])
        #expect(html.contains("Halcyon Drift") && html.contains("Vaelo"))
        #expect(html.contains("with me since 2014"))
        #expect(html.contains("Iri"))
    }

    @Test func capsAtTenRecords() {
        let many = (0..<20).map { FlyerEntry(artist: "A\($0)", title: "T\($0)", note: nil) }
        let html = flyer(many)
        #expect(html.contains("T9") && !html.contains("T10"),
                "a flyer is ten records, not a database dump")
    }

    @Test func honoursTheITunesTerms() {
        let html = flyer([FlyerEntry(artist: "V", title: "T", note: nil)])
        #expect(html.contains("Previews courtesy of"), "the credit is a term, not a nicety")
        #expect(html.contains("https://www.apple.com/itunes/"))
        #expect(!html.contains("download"), "streams only — no download affordance anywhere")
    }

    @Test func onlyScriptIsOursPlusJSONP() {
        let html = flyer([FlyerEntry(artist: "V", title: "T", note: nil)])
        // One inline <script> block; the only dynamic script source is the
        // iTunes search endpoint the receiver taps to hear a preview.
        #expect(html.components(separatedBy: "<script>").count == 2)
        #expect(!html.contains("src=\"http"), "no static external scripts")
        #expect(html.contains("itunes.apple.com/search"))
    }

    @Test func fileWritesAndRoundTrips() throws {
        let url = FlyerBuilder.writeFile(entries: [FlyerEntry(artist: "V", title: "Ti", note: nil)],
                                         heading: "h", subtitle: "s", openHint: "o", creditText: "c")
        let unwrapped = try #require(url)
        defer { try? FileManager.default.removeItem(at: unwrapped) }
        let read = try String(contentsOf: unwrapped, encoding: .utf8)
        #expect(read.contains("Ti"))
        #expect(unwrapped.pathExtension == "html")
    }
}
