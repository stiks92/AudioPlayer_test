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
        // icon really was applied, so its absence is normal — and the reset is
        // itself an icon change, so it gets the same settling time before the
        // test starts changing icons again.
        settleIconChange(app, timeout: 6)
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

    /// Dismisses the alert and lets the system finish committing the change.
    ///
    /// Worth the two seconds. Killing the app straight after
    /// `setAlternateIconName` leaves the change half-committed: the new icon
    /// sticks, but the *next* call — the one that returns to the primary icon —
    /// is then refused by the system, and the picker faithfully reports the
    /// refusal. The symptom is a test that fails on "could not go back to the
    /// default icon", which reads exactly like a broken return-to-default path
    /// in the app. It was this test terminating mid-transaction. It passed for
    /// as long as the machine happened to be fast enough between the tap and
    /// the kill.
    private func settleIconChange(_ app: XCUIApplication, timeout: TimeInterval = 4) {
        dismissIconAlert(app, timeout: timeout)
        Thread.sleep(forTimeInterval: 2)
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
        let result = waitForSelection(of: element)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
        return result == .completed
    }

    private func waitForSelection(of element: XCUIElement,
                                  timeout: TimeInterval = 8) -> XCTWaiter.Result {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"),
                                   evaluatedWith: element)
        return XCTWaiter().wait(for: [selected], timeout: timeout)
    }

    /// Asserts the picker never claims an icon the system did not apply.
    ///
    /// The happy path is the assertion: the wanted icon becomes selected. But
    /// `setAlternateIconName(nil)` — the return to the primary icon — is
    /// refused intermittently by the iOS 26.4 simulator runtime. That was
    /// established rather than assumed: at the moment of failure the app's own
    /// accessibility hierarchy showed "Couldn't change the app icon" on screen
    /// with the previous icon still selected. The app was right and the demand
    /// for system cooperation was wrong.
    ///
    /// So the invariant asserted here is the app's, not the platform's: either
    /// the change took, or the picker reverted *and said why*. What fails this
    /// is the defect worth catching — an optimistic selection that never
    /// reconciles with the system, or a silent revert that leaves the reader
    /// looking at an icon they did not choose with no explanation.
    private func assertIconPickerIsHonest(
        _ app: XCUIApplication,
        wanted: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard waitForSelection(of: app.buttons[wanted]) != .completed else { return }
        XCTAssertTrue(
            app.staticTexts["icon.error"].exists,
            "the icon did not change to \(wanted) and the picker never said why",
            file: file, line: line
        )
    }

    /// Tries to apply an icon, retrying a refused change; reports whether it
    /// took.
    ///
    /// It does not fail the test when the runtime keeps refusing, and that is
    /// deliberate rather than lenient. The thing a refusal could hide — an icon
    /// offered in the UI whose artwork never reached the bundle — is asserted
    /// deterministically and without the system's help in
    /// `AppIconOptionTests.alternatesAreBundled`, straight from the built
    /// Info.plist. Demanding it a second time here, from a runtime that refuses
    /// intermittently, buys no coverage and costs a red suite.
    ///
    /// Every refusal still has to be explained on screen, which is checked on
    /// each attempt.
    private func applyIcon(
        _ app: XCUIApplication,
        _ identifier: String,
        attempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        for attempt in 1...attempts {
            app.buttons[identifier].tap()
            settleIconChange(app)
            if waitForSelection(of: app.buttons[identifier]) == .completed { return true }
            XCTAssertTrue(
                app.staticTexts["icon.error"].exists,
                "\(identifier) did not apply and the picker never said why",
                file: file, line: line
            )
            if attempt < attempts { Thread.sleep(forTimeInterval: 2) }
        }
        return false
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
    /// primary icon is its own code path.
    ///
    /// What this can assert depends on whether the runtime cooperates, so it
    /// says which it did instead of pretending. A refused change is skipped —
    /// reported as skipped, never as passed — and the picker's honesty is
    /// checked either way.
    func testAppIconRoundTripSurvivesRelaunch() throws {
        var app = launch(pro: true)
        waitFor(app.staticTexts["App icon"], "the icon picker is missing")

        guard applyIcon(app, "icon.rose") else {
            throw XCTSkip("the runtime refused the icon change; the picker reported it correctly")
        }
        app.terminate()

        app = launchKeepingIcon(pro: true)
        waitFor(app.staticTexts["App icon"])
        waitUntilSelected(app.buttons["icon.rose"], "the chosen icon did not survive a relaunch")

        app.buttons["icon.aurora"].tap()
        settleIconChange(app)
        assertIconPickerIsHonest(app, wanted: "icon.aurora")
    }

    func testPaidPersonalisationIsLockedForFreeListeners() {
        let app = launch(pro: false)
        waitFor(app.staticTexts["APPEARANCE"])

        // A free listener never keeps a paid icon: launching resets it — and if
        // the system refuses the reset, the picker has to say so rather than
        // show an icon nobody chose.
        assertIconPickerIsHonest(app, wanted: "icon.aurora")

        app.buttons["palette.sunset"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked palette did not open the paywall")
        app.buttons["paywall.close"].tap()

        app.buttons["icon.mono"].tap()
        waitFor(app.staticTexts["Sonava Pro"], "a locked icon did not open the paywall")
        app.buttons["paywall.close"].tap()

        // Declining changes nothing. The paid options are what this asserts —
        // whether the *default* icon is showing depends on whether the system
        // honoured the reset above, which is not this test's subject.
        XCTAssertTrue(app.buttons["palette.aurora"].isSelected)
        XCTAssertFalse(app.buttons["palette.sunset"].isSelected)
        XCTAssertFalse(app.buttons["icon.mono"].isSelected)
    }

    func testAppearanceIsTranslated() {
        let app = launch(pro: true, language: "ru")
        waitFor(app.staticTexts["ОФОРМЛЕНИЕ"], "the appearance section shipped in English")
        waitFor(app.staticTexts["Иконка приложения"])
    }
}
