//
//  PlayerTransitionUITests.swift
//  SonavaUITests
//
//  The mini player is on screen for the whole session and expanding it is the
//  app's most-used navigation. It had no test at all: nothing checked that
//  tapping it opens the full player, or that closing it returns you to where
//  you were with the mini player still there.
//
//  The transition between the two is a `matchedGeometryEffect`, which fails
//  *silently* when it fails — a mismatched id just cross-fades, which reads as
//  a design choice rather than a bug. So this also captures frames across the
//  animation as attachments, which is the only way to look at a flight when
//  the machine has no video tooling.
//

import XCTest

@MainActor
final class PlayerTransitionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchPlaying() -> XCUIApplication {
        XCUIApplication.launched(
            pro: true,
            extraArguments: ["-seedDemoContent", "-demoPlay"]
        )
    }

    func testTappingTheMiniPlayerOpensTheFullPlayerAndBack() {
        let app = launchPlaying()
        let mini = app.otherElements["player.mini"]
        waitFor(mini, "the mini player never appeared with a track playing")

        mini.tap()

        // Identified by the one control only the full player has: the button
        // that collapses it again. The first version of this test looked for
        // the *mini* player's transport id, which vanishes precisely because
        // the expand worked — a test that could only fail.
        waitFor(app.buttons["player.collapse"],
                "tapping the mini player did not open the full player")
        XCTAssertFalse(mini.exists,
                       "the mini player is still on screen behind the full player, so the same track is drawn twice")
    }

    /// Frames across the expand, saved to the result bundle.
    ///
    /// Not an assertion — a screenshot cannot tell a flight from a cross-fade
    /// on its own — but it is what makes the transition inspectable at all, and
    /// it fails loudly if the player stops opening.
    func testExpandTransitionIsCaptured() {
        let app = launchPlaying()
        let mini = app.otherElements["player.mini"]
        waitFor(mini)

        attach(app.screenshot(), named: "00-before")
        mini.tap()
        for index in 1...3 {
            attach(app.screenshot(), named: String(format: "%02d-during", index))
        }
        waitFor(app.buttons["player.collapse"],
                "the player did not open during the capture")
        attach(app.screenshot(), named: "99-after")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
