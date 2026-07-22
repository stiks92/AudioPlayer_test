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
        language: String = "en"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-hasOnboarded.v1", onboarding == .completed ? "YES" : "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
        ]
        app.launch()
        return app
    }

    /// The custom tab bar is plain buttons, not a UITabBar, so tabs are found
    /// by their label.
    func tab(_ name: String) -> XCUIElement {
        buttons[name].firstMatch
    }
}

extension XCTestCase {

    /// Fails with a useful message instead of hanging for the default timeout.
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
