//
//  SonavaApp+Testing.swift
//  SonavaUITests
//
//  Launch helpers. UI tests get a deterministic app: onboarding is either
//  explicitly shown or explicitly skipped, never "whatever the last run left
//  behind".
//

import XCTest

extension XCUIApplication {

    enum Onboarding {
        case shown
        case completed
    }

    static func launched(
        onboarding: Onboarding = .completed,
        language: String = "en",
        pro: Bool = false,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-hasOnboarded.v1", onboarding == .completed ? "YES" : "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
        ]
        if pro {
            // The DEBUG developer unlock is a plain default, so a launch
            // argument flips it without needing App Store products.
            app.launchArguments += ["-pro.dev.override.v1", "YES"]
        }
        // Debug-only routes: seeding data, deep-linking to a screen.
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    /// The custom tab bar is plain buttons, not a UITabBar, so tabs are found
    /// by their label.
    func tab(_ name: String) -> XCUIElement {
        buttons[name].firstMatch
    }

    /// Opens Settings from Home's index. The Settings row is the last entry,
    /// and with a restored queue the floating mini-player capsule can rest
    /// exactly over it at launch scroll position — a bare `.tap()` then lands
    /// on the capsule and opens the player instead (XCUITest taps the row's
    /// centre without scrolling, which no human does). One upward swipe first
    /// clears the row; on a short Home it's a harmless rubber-band.
    func openHomeSettings() {
        let row = buttons["home.settings"]
        _ = row.waitForExistence(timeout: 10)
        swipeUp()
        row.tap()
    }
}

extension XCTestCase {

    /// Fails with a useful message instead of hanging for the default timeout.
    @MainActor
    @discardableResult
    func waitFor(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let appeared = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(
            appeared,
            message.isEmpty ? "\(element) never appeared" : message,
            file: file, line: line
        )
        return appeared
    }
}
