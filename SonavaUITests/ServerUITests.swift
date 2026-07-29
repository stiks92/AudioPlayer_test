//
//  ServerUITests.swift
//  SonavaUITests
//
//  Self-hosting is the differentiator and "unlimited servers" is the Pro sell,
//  so the gate itself is the thing worth driving: a free listener must be
//  stopped politely and shown the offer, and a subscriber must never be.
//
//  Servers are seeded from a launch argument — the alternative is a live
//  Subsonic server in CI.
//

import XCTest

@MainActor
final class ServerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(servers: Int, pro: Bool = false) -> XCUIApplication {
        XCUIApplication.launched(
            pro: pro,
            extraArguments: ["-seedServers", "\(servers)", "-openServers"]
        )
    }

    func testEmptyStateInvitesTheFirstConnection() {
        let app = launch(servers: 0)
        waitFor(app.navigationBars["Self-hosted servers"], "the servers screen did not open")
        waitFor(app.staticTexts["No server connected"])

        app.buttons["server.add"].tap()
        waitFor(app.navigationBars["Add server"], "the add form did not open")
    }

    func testFreeListenerIsOfferedProForASecondServer() {
        let app = launch(servers: 1)
        waitFor(app.navigationBars["Self-hosted servers"])
        waitFor(app.staticTexts["Home server"], "the seeded server is missing")

        // The one free connection still works; asking for a second is the
        // upgrade moment.
        app.buttons["server.add"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "the second server did not open the paywall")
        app.buttons["paywall.close"].tap()
        waitFor(app.staticTexts["Home server"], "declining the offer left the screen")
    }

    func testExtraServersSurviveALapsedSubscription() {
        // Seeded as a subscriber would have left them, then run as a free user.
        let app = launch(servers: 3, pro: false)
        waitFor(app.navigationBars["Self-hosted servers"])

        // Nothing was deleted…
        waitFor(app.staticTexts["Home server"])
        waitFor(app.staticTexts["Attic NAS"])
        waitFor(app.staticTexts["Friend's library"])

        // …but the locked ones lead to the offer instead of switching.
        app.staticTexts["Attic NAS"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked server did not open the paywall")
        app.buttons["paywall.close"].tap()
    }

    func testProCanSwitchBetweenServers() {
        let app = launch(servers: 3, pro: true)
        waitFor(app.navigationBars["Self-hosted servers"])

        app.staticTexts["Friend's library"].tap()
        // A subscriber switches libraries silently — no paywall, no reconnect.
        XCTAssertFalse(app.staticTexts["Sonava Pro"].waitForExistence(timeout: 2),
                       "a subscriber was shown the paywall while switching servers")
        waitFor(app.staticTexts["Friend's library"])
    }

    /// The rack states what it knows about each box, and nothing it doesn't.
    ///
    /// This is the assertion the redesign exists for: before it, every row said
    /// "listener" and the only other thing on it was a delete button.
    func testEachServerStatesItsHostAndReachability() {
        let app = launch(servers: 3, pro: true)
        waitFor(app.navigationBars["Self-hosted servers"])

        // The scheme is part of the address on every row now: showing it only
        // on the insecure one asked the reader to read a *missing* prefix as
        // "encrypted", which nothing on the screen teaches.
        waitFor(app.staticTexts["https://navidrome.home.arpa"],
                "the row does not say which box it is")
        waitFor(app.staticTexts["http://nas.local"],
                "an unencrypted connection is not labelled as one")
        waitFor(app.staticTexts["Online"], "the row does not say whether the server answered")
        // The seed makes the third connection unreachable on purpose: a rack
        // that can only draw its happy state has never had its failure state
        // looked at.
        waitFor(app.staticTexts["Unreachable"], "the unreachable server is drawn as if it were fine")
    }

    func testRemovingAServerAsksFirst() {
        let app = launch(servers: 2, pro: true)
        waitFor(app.navigationBars["Self-hosted servers"])

        // Removal lives behind a swipe now — the trash cans that used to sit
        // armed on every row are gone.
        revealRemove(in: app, row: "Home server")
        waitFor(app.staticTexts["Remove this server?"], "removal happened without confirmation")

        app.alerts.buttons["Cancel"].tap()
        waitFor(app.staticTexts["Home server"], "cancelling still removed the server")

        revealRemove(in: app, row: "Home server")
        app.alerts.buttons["Remove"].tap()
        XCTAssertFalse(app.staticTexts["Home server"].waitForExistence(timeout: 2),
                       "the server was not removed")
    }

    /// Swipes a row open and taps its remove action.
    ///
    /// Checks first rather than swiping blindly: after the confirmation is
    /// cancelled the row can still be open, and a second swipe would close it
    /// again — the test would then fail on the UI being in the right state.
    private func revealRemove(in app: XCUIApplication, row: String) {
        if !app.buttons["server.remove"].exists {
            app.staticTexts[row].swipeLeft()
        }
        waitFor(app.buttons["server.remove"], "the swipe did not reveal a way to remove the server")
        app.buttons["server.remove"].tap()
    }

    func testServerScreenIsTranslated() {
        let app = XCUIApplication.launched(
            language: "ru", pro: true,
            extraArguments: ["-seedServers", "2", "-openServers"]
        )
        waitFor(app.navigationBars["Свои серверы"],
                "the servers screen shipped in English on a Russian device")
        waitFor(app.buttons["server.add"])
    }
}
