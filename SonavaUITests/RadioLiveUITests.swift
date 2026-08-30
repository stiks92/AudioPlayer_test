//
//  RadioLiveUITests.swift
//  SonavaUITests
//
//  The radio booth: a live station must open its own screen — no seek ring,
//  no dead "0:00" — with working station turnover and a favourite that
//  survives a relaunch.
//
//  Assertions ride accessibility identifiers and element state (label
//  inequality, the selected trait), never localized copy: the suite also
//  runs in Russian.
//

import XCTest

@MainActor
final class RadioLiveUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Straight into the open radio booth on the demo dial.
    private func launchOnRadioBooth() -> XCUIApplication {
        XCUIApplication.launched(
            extraArguments: ["-seedDemoContent", "-demoRadio"]
        )
    }

    private func stationElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["radio.station"].firstMatch
    }

    func testBoothOpensWithoutATimeline() {
        let app = launchOnRadioBooth()
        waitFor(app.buttons["player.collapse"], "the radio booth never opened")

        // The booth's own furniture is present…
        waitFor(stationElement(in: app), "the station identity is not exposed")
        waitFor(app.descendants(matching: .any)["radio.status"].firstMatch,
                "the stream-state line is not exposed")
        waitFor(app.buttons["radio.playStop"].firstMatch,
                "the play/stop control is not exposed")

        // …and the track player's timeline is not: no seek ring…
        XCTAssertFalse(app.descendants(matching: .any)["player.ring"].firstMatch.exists,
                       "a live stream must not offer a seek ring")
        // …and no frozen countdown stamped into the glass.
        XCTAssertFalse(app.staticTexts["0:00"].exists,
                       "a live stream has no countdown to print")
    }

    func testNextTunesTheNextStation() {
        let app = launchOnRadioBooth()
        waitFor(app.buttons["player.collapse"], "the radio booth never opened")

        let station = stationElement(in: app)
        waitFor(station, "the station identity is not exposed")
        let before = station.label
        XCTAssertFalse(before.isEmpty, "the station element carries no name to assert against")

        app.buttons["radio.next"].firstMatch.tap()

        // Waiting on the element's state, not on playback timing.
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before),
            object: station
        )
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed,
                       "next did not turn the dial to another station")
    }

    func testFavouriteStationSurvivesRelaunch() {
        var app = launchOnRadioBooth()
        waitFor(app.buttons["player.collapse"], "the radio booth never opened")

        let heart = app.buttons["radio.heart"].firstMatch
        waitFor(heart, "the favourite control is not exposed")
        // The state rides the element's value as "1"/"0" — readable in both
        // test languages, unlike a localized label.
        let initiallyOn = (heart.value as? String) == "1"
        let target = initiallyOn ? "0" : "1"
        heart.tap()

        // The toggle must land in the element's state before the relaunch.
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", target),
            object: heart
        )
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 5), .completed,
                       "tapping the heart did not change its state")

        app.terminate()
        app = launchOnRadioBooth()
        waitFor(app.buttons["player.collapse"], "the radio booth never reopened")
        let heartAfter = app.buttons["radio.heart"].firstMatch
        waitFor(heartAfter, "the favourite control is not exposed after relaunch")
        XCTAssertEqual(heartAfter.value as? String, target,
                       "the favourite did not survive the relaunch")

        // Leave the favourites store the way this test found it.
        heartAfter.tap()
    }
}
