//
//  LibraryAcceptanceTests.swift
//  SonavaUITests
//
//  Acceptance-level checks for the promises the product makes on screen:
//  the app ships no music of its own and says so, previews are labelled as
//  previews, and Pro features are gated rather than silently broken.
//

import XCTest

final class LibraryAcceptanceTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Sonava bundles no catalogue by design, so a fresh install shows an
    /// empty library. That state has to explain itself and offer a way out,
    /// or it reads as a broken app.
    func testEmptyLibraryExplainsItselfAndOffersImport() {
        let app = XCUIApplication.launched()

        app.tab("Library").tap()
        waitFor(app.staticTexts["Your Library"], "library did not open")

        app.staticTexts["Songs"].tap()

        waitFor(app.staticTexts["No files yet"], "the empty library gives the user no explanation")
        XCTAssertTrue(
            app.buttons["library.import"].exists,
            "the empty library offers no way to add music"
        )
    }

    func testImportOpensTheSystemFilePicker() {
        let app = XCUIApplication.launched()

        app.tab("Library").tap()
        app.staticTexts["Songs"].tap()
        waitFor(app.buttons["library.import"])
        app.buttons["library.import"].tap()

        // The picker is a separate process; asserting on our own UI being
        // covered is the stable signal here.
        let picker = app.otherElements["DocumentPickerView"]
        let cancelled = picker.waitForExistence(timeout: 8)
            || app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 8)
        XCTAssertTrue(cancelled, "the Files picker never appeared")
    }

    func testLibraryTabsSwitch() {
        let app = XCUIApplication.launched()
        app.tab("Library").tap()
        waitFor(app.staticTexts["Your Library"])

        for section in ["Songs", "Favorites", "Playlists"] {
            app.staticTexts[section].tap()
            XCTAssertTrue(app.staticTexts[section].exists, "the \(section) segment disappeared")
        }
    }

    func testEmptyFavouritesTellsTheUserHowToFillIt() {
        let app = XCUIApplication.launched()
        app.tab("Library").tap()
        app.staticTexts["Favorites"].tap()

        waitFor(app.staticTexts["No favourites yet"])
        XCTAssertTrue(app.staticTexts["Tap the heart on any track to save it here."].exists)
    }

    func testCreatingAPlaylistFromTheLibrary() {
        let app = XCUIApplication.launched()
        app.tab("Library").tap()
        app.staticTexts["Playlists"].tap()

        waitFor(app.buttons["New Playlist"])
        app.buttons["New Playlist"].tap()

        let alert = app.alerts["New playlist"]
        waitFor(alert, "the new-playlist prompt did not appear")
        alert.textFields.firstMatch.typeText("Road trip")
        alert.buttons["Create"].tap()

        waitFor(app.staticTexts["Road trip"], "the created playlist is not listed")
    }
}

final class PaywallAcceptanceTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// AI Mix is the headline Pro feature. Free users must hit a paywall, not
    /// a dead button — App Review checks exactly this.
    func testAIMixIsGatedBehindPro() {
        let app = XCUIApplication.launched()
        waitFor(app.staticTexts["Create an AI Mix"], "the AI Mix entry point is missing from Home")

        XCTAssertTrue(app.staticTexts["PRO"].exists, "AI Mix is not marked as a Pro feature")

        app.staticTexts["Create an AI Mix"].tap()
        waitFor(app.staticTexts["AI Mix"], "AI Mix did not open")
        XCTAssertTrue(
            app.staticTexts["AI Mix is a Pro feature"].waitForExistence(timeout: 5),
            "a free user was not told AI Mix needs Pro"
        )
    }

    func testPaywallStatesItsTermsBeforeAskingForMoney() {
        let app = XCUIApplication.launched()
        app.buttons["home.settings"].tap()
        waitFor(app.navigationBars["Settings"])

        app.staticTexts["Unlock Sonava Pro"].tap()

        waitFor(app.staticTexts["Sonava Pro"], "the paywall did not open")
        // Guideline 3.1.2: subscription terms have to be visible on the page.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'renew automatically'")
            ).firstMatch.exists,
            "the paywall does not disclose subscription terms"
        )
    }
}
