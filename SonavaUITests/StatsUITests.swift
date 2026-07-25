//
//  StatsUITests.swift
//  SonavaUITests
//
//  "Your Sound" is the retention hook (the streak) and the viral loop (the
//  share card), so the path a real user takes — Home card → stats → longer
//  window → paywall — is driven end to end here.
//
//  The log is seeded from a launch argument, because a stats screen with no
//  history proves nothing.
//

import XCTest

@MainActor
final class StatsUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(pro: Bool = false, language: String = "en") -> XCUIApplication {
        XCUIApplication.launched(language: language, pro: pro, extraArguments: ["-seedStats"])
    }

    func testHomeCardOpensTheStatsScreen() {
        let app = launch()

        let card = app.buttons["home.stats"]
        waitFor(card, "the Your Sound card is missing from Home")
        card.tap()

        waitFor(app.navigationBars["Your Sound"], "the stats screen did not open")
        waitFor(app.staticTexts["You listened for"])
        waitFor(app.staticTexts["TOP ARTISTS"], "the ranked list did not render")
    }

    func testTotalAndStreakAreRealNumbers() {
        let app = launch()
        app.buttons["home.stats"].tap()
        waitFor(app.navigationBars["Your Sound"])

        // The hero must show a duration, not a placeholder or an empty state.
        let total = app.staticTexts["stats.total"]
        waitFor(total, "the total listening time is missing")
        XCTAssertFalse(total.label.isEmpty)
        XCTAssertTrue(
            total.label.contains("h") || total.label.contains("m"),
            "expected a formatted duration, got '\(total.label)'"
        )

        // The seeded fortnight is contiguous, so there is a streak to show.
        waitFor(app.staticTexts["day streak"])
    }

    func testLongerWindowsAreProGatedAndOpenThePaywall() {
        let app = launch(pro: false)
        app.buttons["home.stats"].tap()
        waitFor(app.navigationBars["Your Sound"])

        app.buttons["stats.range.month"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked range did not open the paywall")
        app.buttons["paywall.close"].tap()

        // Declining leaves the free window selected rather than silently
        // switching to content the user hasn't paid for.
        waitFor(app.staticTexts["You listened for"])
    }

    func testProCanSwitchToTheLongerWindows() {
        let app = launch(pro: true)
        app.buttons["home.stats"].tap()
        waitFor(app.navigationBars["Your Sound"])

        app.buttons["stats.range.all"].tap()
        // No paywall for a subscriber — the screen simply re-renders.
        XCTAssertFalse(app.staticTexts["Sonava Pro"].waitForExistence(timeout: 2),
                       "a subscriber was shown the paywall")
        waitFor(app.staticTexts["You listened for"])
    }

    func testStatsAreTranslated() {
        let app = launch(language: "ru")
        waitFor(app.buttons["home.stats"], "the Your Sound card is missing on a Russian device")
        app.buttons["home.stats"].tap()

        waitFor(app.navigationBars["Твой звук"], "the stats screen shipped in English on a Russian device")
        waitFor(app.staticTexts["Прослушано"])
        waitFor(app.staticTexts["дней подряд"])
    }

    func testHistoryCanBeCleared() {
        let app = launch()
        app.buttons["home.stats"].tap()
        waitFor(app.navigationBars["Your Sound"])

        app.buttons["stats.menu"].tap()
        app.buttons["Clear history"].tap()
        app.buttons["Clear"].tap()

        // Clearing is honest: the screen falls back to the empty state rather
        // than keeping stale numbers on screen.
        waitFor(app.staticTexts["Nothing here yet"], "clearing did not empty the screen")
    }
}
