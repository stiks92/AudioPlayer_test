//
//  AppearanceUITests.swift
//  SonavaUITests
//
//  Personalisation is a Pro pillar, so both halves of it are driven here: the
//  accent palette and the home-screen icon. The icon test is the one that
//  matters most — `setAlternateIconName` fails silently if the asset never made
//  it into the bundle, and only the running system can tell us it worked.
//

import XCTest

@MainActor
final class AppearanceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// The selected icon is system state that survives relaunch, so every test
    /// starts by putting it back — otherwise one failure poisons the next test.
    private func launch(pro: Bool, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication.launched(
            language: language, pro: pro,
            extraArguments: ["-openSettings", "-resetAppIcon"]
        )
        // Resetting the icon raises the system alert, which would otherwise
        // swallow the first tap of the test. It only appears when an alternate
        // icon really was applied, so its absence is normal.
        dismissIconAlert(app, timeout: 6)
        return app
    }

    /// Same launch, without the reset — for asserting that a chosen icon
    /// survived being relaunched.
    private func launchKeepingIcon(pro: Bool, language: String = "en") -> XCUIApplication {
        XCUIApplication.launched(language: language, pro: pro, extraArguments: ["-openSettings"])
    }

    /// Changing the app icon raises a system alert; dismiss it if it appears.
    private func dismissIconAlert(_ app: XCUIApplication, timeout: TimeInterval = 4) {
        let ok = app.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: timeout) { ok.tap() }
    }

    /// `isSelected` is read from a snapshot, and applying an icon is
    /// asynchronous — so wait on the property rather than sampling it once.
    @discardableResult
    private func waitUntilSelected(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"),
                                   evaluatedWith: element)
        let result = XCTWaiter().wait(for: [selected], timeout: 8)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
        return result == .completed
    }

    func testAccentPaletteCanBeChanged() {
        let app = launch(pro: true)
        waitFor(app.staticTexts["APPEARANCE"], "the appearance section is missing")

        app.buttons["palette.ocean"].tap()
        waitUntilSelected(app.buttons["palette.ocean"], "the palette did not change")
        XCTAssertFalse(app.buttons["palette.aurora"].isSelected)

        app.buttons["palette.aurora"].tap()   // leave the next test a clean slate
        waitUntilSelected(app.buttons["palette.aurora"], "the palette did not change back")
    }

    /// The whole round trip, because the two directions fail differently: an
    /// alternate that was never bundled won't apply, and returning to the
    /// primary icon is its own code path. Ends on the default, so the simulator
    /// carries no state into the next test.
    func testAppIconRoundTripSurvivesRelaunch() {
        var app = launch(pro: true)
        waitFor(app.staticTexts["App icon"], "the icon picker is missing")

        app.buttons["icon.rose"].tap()
        dismissIconAlert(app)
        waitUntilSelected(app.buttons["icon.rose"], "the alternate icon was not applied")
        app.terminate()

        app = launchKeepingIcon(pro: true)
        waitFor(app.staticTexts["App icon"])
        waitUntilSelected(app.buttons["icon.rose"], "the chosen icon did not survive a relaunch")

        app.buttons["icon.aurora"].tap()
        dismissIconAlert(app)
        waitUntilSelected(app.buttons["icon.aurora"], "could not go back to the default icon")
        app.terminate()

        app = launchKeepingIcon(pro: true)
        waitFor(app.staticTexts["App icon"])
        waitUntilSelected(app.buttons["icon.aurora"], "the default icon did not survive a relaunch")
    }

    func testPaidPersonalisationIsLockedForFreeListeners() {
        let app = launch(pro: false)
        waitFor(app.staticTexts["APPEARANCE"])

        // A free listener never keeps a paid icon: launching resets it.
        waitUntilSelected(app.buttons["icon.aurora"], "a lapsed listener kept a paid icon")

        app.buttons["palette.sunset"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked palette did not open the paywall")
        app.buttons["paywall.close"].tap()

        app.buttons["icon.mono"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked icon did not open the paywall")
        app.buttons["paywall.close"].tap()

        // Declining changes nothing.
        XCTAssertTrue(app.buttons["palette.aurora"].isSelected)
        XCTAssertTrue(app.buttons["icon.aurora"].isSelected)
        XCTAssertFalse(app.buttons["palette.sunset"].isSelected)
        XCTAssertFalse(app.buttons["icon.mono"].isSelected)
    }

    func testAppearanceIsTranslated() {
        let app = launch(pro: true, language: "ru")
        waitFor(app.staticTexts["ОФОРМЛЕНИЕ"], "the appearance section shipped in English")
        waitFor(app.staticTexts["Иконка приложения"])
    }
}
