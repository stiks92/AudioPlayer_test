//
//  NavigationUITests.swift
//  SonavaUITests
//
//  The shell: onboarding, the five tabs, and settings. These are the screens
//  every session passes through, so a regression here is a dead app.
//

import XCTest

final class NavigationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingIsShownOnFirstLaunchAndCanBeSkipped() {
        let app = XCUIApplication.launched(onboarding: .shown)

        waitFor(app.staticTexts["All your music, one player"], "onboarding did not appear")

        app.buttons["Skip"].tap()

        // Skipping lands on Home, not a blank screen.
        waitFor(app.tab("Home"), "tab bar did not appear after skipping onboarding")
    }

    func testOnboardingCanBePagedThrough() {
        let app = XCUIApplication.launched(onboarding: .shown)
        waitFor(app.staticTexts["All your music, one player"])

        app.buttons["Continue"].tap()
        waitFor(app.staticTexts["Search everything at once"])

        app.buttons["Continue"].tap()
        waitFor(app.staticTexts["AI Mix & Shazam"])

        app.buttons["Continue"].tap()
        waitFor(app.staticTexts["Private by design"])

        // The last slide commits instead of continuing.
        app.buttons["Start listening"].tap()
        waitFor(app.tab("Home"))
    }

    func testEveryTabOpens() {
        let app = XCUIApplication.launched()

        for name in ["Search", "Radio", "Podcasts", "Library", "Home"] {
            let tab = app.tab(name)
            waitFor(tab, "the \(name) tab is missing")
            tab.tap()
            XCTAssertTrue(tab.exists, "the tab bar vanished after opening \(name)")
        }
    }

    func testTabsKeepTheirStateWhenSwitchedAwayAndBack() {
        let app = XCUIApplication.launched()

        app.tab("Search").tap()
        let field = app.textFields["search.query"]
        waitFor(field, "search field is missing")
        field.tap()
        field.typeText("piano")

        app.tab("Library").tap()
        app.tab("Search").tap()

        // Tabs are deliberately kept alive rather than rebuilt, so the query
        // must still be there.
        XCTAssertEqual(field.value as? String, "piano", "the search query was lost on tab switch")
    }

    func testSettingsOpensAndCloses() {
        let app = XCUIApplication.launched()
        waitFor(app.tab("Home"))

        app.buttons["home.settings"].tap()
        waitFor(app.navigationBars["Settings"], "settings did not open")

        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Settings"].exists, "settings did not close")
    }
}
