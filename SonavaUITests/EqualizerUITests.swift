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

    /// The equalizer ships **off**, so the switch is the only way into the
    /// feature. It once sat inside a subtree that the off state disabled —
    /// and `disabled` is additive, so nothing below could re-enable itself.
    /// The result was a headline Pro feature that could never be switched on.
    func testTheEqualizerCanActuallyBeSwitchedOn() {
        let app = XCUIApplication.launched(pro: true)
        openSettings(app)
        app.staticTexts["Equalizer"].firstMatch.tap()

        let toggle = app.switches["eq.enable"]
        waitFor(toggle, "the EQ enable toggle is missing")

        XCTAssertTrue(toggle.isEnabled, "the enable switch is not interactive — the EQ cannot be turned on")

        // The equalizer setting persists, so the state at launch depends on
        // whatever ran before. Drive it to off first, then assert the direction
        // that was actually broken: off → on.
        if (toggle.value as? String) == "1" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "0", "could not switch the equalizer off")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "an off equalizer could not be switched back on")
    }

    func testEnablingAndPickingAPresetSticks() {
        let app = XCUIApplication.launched(pro: true)
        openSettings(app)
        app.staticTexts["Equalizer"].firstMatch.tap()

        let toggle = app.switches["eq.enable"]
        waitFor(toggle)
        if (toggle.value as? String) == "0" { toggle.tap() }

        // The header subtitle names the active preset. Assert that it *changes*
        // rather than matching a translated string — but wait on the change
        // properly: the previous version was `changed || elementExists`, whose
        // right-hand side is true whenever the element is on screen, so the
        // assertion could never fail and the broken switch above sailed past it.
        let subtitle = app.staticTexts["eq.selectedPreset"]
        waitFor(subtitle, "the preset subtitle is missing")

        // The chosen preset persists between launches, so start from a known
        // one rather than assuming a fresh install — otherwise this passes or
        // fails depending on what the previous test happened to leave behind.
        app.buttons["eq.preset.flat"].tap()
        let before = subtitle.label

        app.buttons["eq.preset.bass"].tap()

        let changed = expectation(for: NSPredicate(format: "label != %@", before),
                                  evaluatedWith: subtitle)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed,
                       "picking a preset did not change the named preset")
    }
}
