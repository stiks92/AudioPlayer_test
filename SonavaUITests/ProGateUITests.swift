//
//  ProGateUITests.swift
//  SonavaUITests
//
//  The gates the paid zone gained in 2026-08: Crate Mix and headphone
//  correction. One free/pro pair per feature — free hits a paywall it can
//  close, pro walks straight in. Everything is asserted by identifier or by
//  the untranslated brand mark "Sonava Pro", so the pairs hold in Russian.
//

import XCTest

@MainActor
final class CrateMixGateUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// `-demoPlay` fills the queue (demo catalogue on an empty install),
    /// `-openQueue` deep-links to the sheet the button lives on.
    private func openQueue(pro: Bool) -> XCUIApplication {
        let app = XCUIApplication.launched(
            pro: pro, extraArguments: ["-demoPlay", "-openQueue"])
        waitFor(app.buttons["queue.crateMix"], "the Crate Mix button never appeared")
        return app
    }

    func testFreeUserGetsThePaywallAndNoMix() {
        let app = openQueue(pro: false)

        app.buttons["queue.crateMix"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a free user tapped Crate Mix and no paywall came")
        app.buttons["paywall.close"].tap()

        // Declining leaves the queue exactly as it was: the button is back
        // and the mix never switched on (the active state carries .isSelected).
        waitFor(app.buttons["queue.crateMix"], "closing the paywall lost the queue")
        XCTAssertFalse(app.buttons["queue.crateMix"].isSelected,
                       "declining the paywall still activated Crate Mix")
    }

    func testProUserActivatesTheMixWithNoPaywall() {
        let app = openQueue(pro: true)

        app.buttons["queue.crateMix"].tap()

        let activated = expectation(for: NSPredicate(format: "isSelected == true"),
                                    evaluatedWith: app.buttons["queue.crateMix"])
        XCTAssertEqual(XCTWaiter().wait(for: [activated], timeout: 5), .completed,
                       "a Pro user's tap did not activate Crate Mix")
        XCTAssertFalse(app.buttons["paywall.close"].exists,
                       "a paying user was shown the paywall")
    }
}

@MainActor
final class HeadphoneCorrectionGateUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testFreeUserSeesTheLockAndCanReachThePaywall() {
        let app = XCUIApplication.launched(extraArguments: ["-openCorrection"])

        waitFor(app.buttons["correction.unlock"], "the locked state never appeared for a free user")
        XCTAssertFalse(app.buttons["correction.apply"].exists,
                       "the import controls leaked to a free user")

        app.buttons["correction.unlock"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "the unlock button did not open the paywall")
        app.buttons["paywall.close"].tap()

        // Declining leaves the door where it was — locked, not broken.
        waitFor(app.buttons["correction.unlock"], "closing the paywall lost the screen")
    }

    func testProUserGetsTheImporter() {
        let app = XCUIApplication.launched(pro: true, extraArguments: ["-openCorrection"])

        // The importer (or, if a profile was left installed by an earlier
        // run, the installed state's controls) — either way, no lock. Both
        // queried by identifier so the pair holds in any language.
        let importVisible = app.buttons["correction.apply"].waitForExistence(timeout: 10)
            || app.switches["correction.toggle"].exists
        XCTAssertTrue(importVisible, "a Pro user did not get the correction controls")
        XCTAssertFalse(app.buttons["correction.unlock"].exists,
                       "the Pro screen still shows the lock")
    }
}
