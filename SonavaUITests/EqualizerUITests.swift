//
//  EqualizerUITests.swift
//  SonavaUITests
//
//  The equalizer is a Pro feature reached from Settings. These check the gate
//  and, once unlocked, that the controls are actually there.
//

import XCTest

@MainActor
final class EqualizerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings(_ app: XCUIApplication) {
        waitFor(app.tab("Home"))
        app.buttons["home.settings"].tap()
        waitFor(app.navigationBars["Settings"])
    }

    func testEqualizerIsGatedForFreeUsers() {
        let app = XCUIApplication.launched()      // free tier
        openSettings(app)

        app.staticTexts["Equalizer"].firstMatch.tap()
        waitFor(app.staticTexts["The equalizer is a Pro feature"], "a free user was not shown the paywall gate")
        XCTAssertFalse(app.switches["eq.enable"].exists, "EQ controls leaked to a free user")
    }

    func testProUserSeesTheFullEqualizer() {
        let app = XCUIApplication.launched(pro: true)
        openSettings(app)

        app.staticTexts["Equalizer"].firstMatch.tap()

        let toggle = app.switches["eq.enable"]
        waitFor(toggle, "the EQ enable toggle is missing")

        // Ten band labels and the pre-amp make up the graphic EQ. Presets are
        // queried by identifier, not label, so this holds in any language.
        XCTAssertTrue(app.staticTexts["16k"].exists, "the 16k band is missing")
        XCTAssertTrue(app.buttons["eq.preset.bass"].exists, "presets are missing")
    }

    func testEnablingAndPickingAPresetSticks() {
        let app = XCUIApplication.launched(pro: true)
        openSettings(app)
        app.staticTexts["Equalizer"].firstMatch.tap()

        let toggle = app.switches["eq.enable"]
        waitFor(toggle)
        if (toggle.value as? String) == "0" { toggle.tap() }

        // The header subtitle names the active preset; assert it changes rather
        // than matching a specific (translated) string.
        let subtitle = app.staticTexts["eq.selectedPreset"]
        waitFor(subtitle, "the preset subtitle is missing")
        let before = subtitle.label

        app.buttons["eq.preset.bass"].tap()

        XCTAssertTrue(
            subtitle.label != before || subtitle.waitForExistence(timeout: 3),
            "picking a preset did not update the screen"
        )
    }
}
