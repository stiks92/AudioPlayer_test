//
//  TourUITests.swift
//  SonavaUITests
//
//  A guided walk through the app, for recording.
//
//  Not a test of anything — it asserts almost nothing on purpose. Its job is
//  to drive real taps at a human pace while `simctl io recordVideo` runs, so
//  the app's motion can be *seen*: the genie opening and closing, the
//  play/pause glyph morphing, an album growing out of its own sleeve, the
//  segmented control scrolling, the progress ring turning.
//
//  Screenshots cannot show any of that, and the alternative — describing the
//  animation in prose — is how a design conversation goes wrong.
//

import XCTest

final class TourUITests: XCTestCase {

    /// Long enough that a spring has finished and a person has seen it.
    private func beat(_ seconds: Double = 1.6) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func testGuidedTour() throws {
        let app = XCUIApplication.launched(
            language: "ru", pro: true,
            extraArguments: ["-seedDemoContent", "-seedStats", "-seedServers", "3", "-demoPlay"]
        )
        beat(2.5)   // let Home settle and the mini player appear

        // ── The genie: the player grows out of the capsule and back ──────
        let mini = app.otherElements["player.mini"]
        if mini.waitForExistence(timeout: 8) {
            mini.tap()
            beat(2.2)

            // The play/pause glyph morphing, twice, in the full player.
            let playPause = app.buttons[AccessibilityIDMirror.playPause]
            if playPause.exists {
                playPause.tap(); beat(1.2)
                playPause.tap(); beat(1.2)
            }

            // Back into the capsule.
            let collapse = app.buttons["player.collapse"]
            if collapse.exists { collapse.tap(); beat(2.0) }
        }

        // ── The tab bar, and the segmented control scrolling ─────────────
        for tab in ["Поиск", "Радио", "Медиатека"] {
            let button = app.tabBars.buttons[tab]
            if button.exists { button.tap(); beat(1.8) }
        }

        // Library's shelves, one after another — the pill slides between them.
        for shelf in ["albums", "playlists", "songs", "downloads", "favorites", "sources"] {
            let segment = app.buttons["library.segment.\(shelf)"]
            if segment.exists { segment.tap(); beat(1.2) }
        }

        // ── An album opening out of its own sleeve (the zoom morph) ──────
        let segment = app.buttons["library.segment.albums"]
        if segment.exists { segment.tap(); beat(1.2) }
        let firstAlbum = app.scrollViews.buttons.firstMatch
        if firstAlbum.exists {
            firstAlbum.tap(); beat(2.4)
            // Back by swipe, not by a Back button: the album screen is pushed
            // with the zoom transition and its navigation bar has no visible
            // button to find. The edge swipe drives the same dismissal, and
            // it is what a person actually does.
            app.swipeRight(velocity: .slow); beat(2.0)
        }

        // Home again, so the recording ends where it began.
        let home = app.tabBars.buttons.firstMatch
        if home.exists { home.tap(); beat(2.0) }
    }
}

/// The app's identifiers are not visible to the test target, so the two the
/// tour needs are mirrored here rather than hard-coded at each call site.
private enum AccessibilityIDMirror {
    static let playPause = "player.playPause"
}
