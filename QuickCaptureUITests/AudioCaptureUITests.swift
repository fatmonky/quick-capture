import XCTest

/// Exercises the Speak flow's screens. The simulator's microphone may pick up
/// nothing (or room noise), so these tests don't assert on recognized words.
/// Starting can be slow on a fresh simulator (first-time speech setup), hence the long waits.
final class AudioCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// Accepts the speech-recognition and microphone permission prompts if they appear.
    private func allowPermissionPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 3) else { return }
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
        }
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRecordStopAndReturn() {
        app.buttons["Speak"].tap()
        allowPermissionPrompts()

        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "Expected to be recording")
        attachScreenshot("recording")
        stop.tap()

        XCTAssertTrue(app.buttons["Record More"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add"].exists)
        attachScreenshot("review")

        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 1) { discard.tap() }
        XCTAssertTrue(app.buttons["Speak"].waitForExistence(timeout: 3))
    }

    func testRecordMoreResumesRecording() {
        app.buttons["Speak"].tap()
        allowPermissionPrompts()

        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 20))
        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Record More"].waitForExistence(timeout: 3))
        app.buttons["Record More"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 3))
    }
}
