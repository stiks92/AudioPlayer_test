//
//  PlayerGesturesUITests.swift
//  SonavaUITests
//
//  The full player's two artwork gestures: a horizontal swipe on the record
//  changes track, and — the regression this file exists to hold — a pull
//  down that starts on the record still dismisses the player, because both
//  meanings now ride one axis-locked gesture and a bug in the lock would
//  silently eat the dismissal.
//
//  Assertions ride accessibility identifiers and fixture track titles, never
//  localized copy: the suite also runs in Russian.
//

import XCTest

@MainActor
final class PlayerGesturesUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Straight into the open full player with the demo queue loaded.
    private func launchOnNowPlaying() -> XCUIApplication {
        XCUIApplication.launched(
            pro: true,
            extraArguments: ["-seedDemoContent", "-demoPlay", "-openNowPlaying"]
        )
    }

    /// The record disc. Registered as a plain accessibility element, so it is
    /// matched by identifier across element types rather than guessed at one.
    private func discElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["player.disc"].firstMatch
    }

    func testSwipingLeftOnTheDiscAdvancesToTheNextTrack() {
        let app = launchOnNowPlaying()
        waitFor(app.buttons["player.collapse"], "the full player never opened")

        let disc = discElement(in: app)
        waitFor(disc, "the artwork disc is not exposed to accessibility")

        guard let before = disc.value as? String, !before.isEmpty else {
            XCTFail("the disc carries no track title to assert against")
            return
        }

        // A deliberate, unambiguous horizontal drag: well past the 60pt
        // commit threshold, and slow enough that the axis lock — not swipe
        // velocity heuristics — is what the test exercises.
        let start = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -180, dy: 0)))

        // The disc's value is the fixture track's title; the next track has a
        // different one. Waiting on the element's state, not on playback
        // timing.
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before),
            object: disc
        )
        XCTAssertEqual(XCTWaiter().wait(for: [advanced], timeout: 10), .completed,
                       "swiping left on the record did not change the track")
    }

    func testDraggingTheDiscDownStillDismissesThePlayer() {
        let app = launchOnNowPlaying()
        waitFor(app.buttons["player.collapse"], "the full player never opened")

        let disc = discElement(in: app)
        waitFor(disc, "the artwork disc is not exposed to accessibility")

        // Straight down from the record, far past the 140pt dismiss
        // threshold. Before the axis lock existed this went to the root
        // dismiss gesture; now the artwork gesture must hand it over.
        let start = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 450)))

        waitFor(app.otherElements["player.mini"],
                "dragging the record down no longer collapses the player")
        XCTAssertFalse(app.buttons["player.collapse"].exists,
                       "the full player is still on screen after the dismiss drag")
    }
}
