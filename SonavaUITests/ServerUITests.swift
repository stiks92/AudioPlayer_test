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
        waitFor(app.staticTexts["Server 2"])
        waitFor(app.staticTexts["Server 3"])

        // …but the locked ones lead to the offer instead of switching.
        app.staticTexts["Server 2"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked server did not open the paywall")
        app.buttons["paywall.close"].tap()
    }

    func testProCanSwitchBetweenServers() {
        let app = launch(servers: 3, pro: true)
        waitFor(app.navigationBars["Self-hosted servers"])

        app.staticTexts["Server 3"].tap()
        // A subscriber switches libraries silently — no paywall, no reconnect.
        XCTAssertFalse(app.staticTexts["Sonava Pro"].waitForExistence(timeout: 2),
                       "a subscriber was shown the paywall while switching servers")
        waitFor(app.staticTexts["Server 3"])
    }

    func testRemovingAServerAsksFirst() {
        let app = launch(servers: 2, pro: true)
        waitFor(app.navigationBars["Self-hosted servers"])

        app.buttons["server.remove"].firstMatch.tap()
        waitFor(app.staticTexts["Remove this server?"], "removal happened without confirmation")

        app.buttons["Cancel"].tap()
        waitFor(app.staticTexts["Home server"], "cancelling still removed the server")

        app.buttons["server.remove"].firstMatch.tap()
        app.buttons["Remove"].tap()
        XCTAssertFalse(app.staticTexts["Home server"].waitForExistence(timeout: 2),
                       "the server was not removed")
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
