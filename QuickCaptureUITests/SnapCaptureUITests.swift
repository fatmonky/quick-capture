import XCTest

/// The simulator has no document camera, so Snap falls back to picking a photo.
/// The pick test expects the newest photo in the simulator's library to be a
/// photo of text (add one with `xcrun simctl addmedia booted page.png`).
final class SnapCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testCancelReturnsToMainScreen() {
        app.buttons["Snap"].tap()
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Snap"].waitForExistence(timeout: 3))
    }

    func testPickingPhotoAddsQuoteAndNote() throws {
        app.buttons["Snap"].tap()
        app.buttons["Choose from Photos"].tap()

        let photo = app.images.firstMatch
        guard photo.waitForExistence(timeout: 10) else {
            throw XCTSkip("No photos in the simulator library")
        }
        // The picker runs out of process and its elements are unstable to query,
        // so tap the first (newest) grid cell by position.
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.455)).tap()

        // The photo comes back to pick from; with nothing picked, Add All adds it all.
        let addAll = app.buttons["Add All"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 20))
        let note = app.textFields["snapNote"]
        note.tap()
        note.typeText("My note")
        let review = XCTAttachment(screenshot: app.screenshot())
        review.name = "snap-review"
        review.lifetime = .keepAlways
        add(review)
        addAll.tap()

        XCTAssertTrue(app.buttons["Speak"].waitForExistence(timeout: 5))
        let editor = app.textViews.firstMatch
        let filled = NSPredicate(format: "value != ''")
        wait(for: [expectation(for: filled, evaluatedWith: editor)], timeout: 5)
        let recognized = editor.value as? String ?? ""
        let textAttachment = XCTAttachment(string: recognized)
        textAttachment.name = "recognized-text"
        textAttachment.lifetime = .keepAlways
        add(textAttachment)
        XCTAssertTrue(recognized.hasPrefix("> "), "The passage is added as a quote")
        XCTAssertTrue(recognized.hasSuffix("\n\nMy note"), "The note goes under the passage")
    }
}
