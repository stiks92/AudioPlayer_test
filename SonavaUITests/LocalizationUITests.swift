//
//  LocalizationUITests.swift
//  SonavaUITests
//
//  The Russian build shipped English onboarding copy once. These run the app
//  in Russian and assert on what is actually rendered, which is the only
//  check that would have caught it.
//

import XCTest

final class LocalizationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTabBarIsTranslated() {
        let app = XCUIApplication.launched(language: "ru")

        for russian in ["Главная", "Поиск", "Радио", "Подкасты", "Медиатека"] {
            XCTAssertTrue(
                app.buttons[russian].waitForExistence(timeout: 10),
                "the tab \"\(russian)\" is not translated"
            )
        }
        XCTAssertFalse(app.buttons["Home"].exists, "the tab bar is still English")
    }

    func testOnboardingBodyCopyIsTranslated() {
        let app = XCUIApplication.launched(onboarding: .shown, language: "ru")

        waitFor(app.staticTexts["Вся музыка в одном плеере"], "the onboarding title is not translated")

        // This subtitle is the string that actually shipped in English.
        XCTAssertTrue(
            app.staticTexts["Стриминг, интернет-радио, подкасты и твой сервер — вместе в одном красивом плеере."].exists,
            "the onboarding subtitle is not translated"
        )
    }

    func testSettingsAreTranslated() {
        let app = XCUIApplication.launched(language: "ru")
        waitFor(app.buttons["Главная"])

        app.buttons["home.settings"].tap()
        waitFor(app.navigationBars["Настройки"], "the settings screen is not translated")

        XCTAssertTrue(app.staticTexts["ВОСПРОИЗВЕДЕНИЕ"].exists)
        XCTAssertTrue(app.staticTexts["ИСТОЧНИКИ"].exists)
    }

    func testEmptyLibraryIsTranslated() {
        let app = XCUIApplication.launched(language: "ru")
        app.buttons["Медиатека"].tap()
        waitFor(app.staticTexts["Твоя медиатека"])

        app.staticTexts["Песни"].tap()
        waitFor(app.buttons["library.import"], "the import affordance is missing")
        XCTAssertTrue(app.staticTexts["Пока нет файлов"].exists, "the empty library is not translated")
    }
}
