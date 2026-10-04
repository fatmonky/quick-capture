import XCTest

final class TypeCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func typeCapture(_ text: String) {
        app.buttons["Type"].tap()
        let field = app.textFields["What do you want to capture?"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(text)
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    func testTypedCapturesAreAppendedWithBlankLine() {
        typeCapture("First thought")
        typeCapture("Second thought")

        let editor = app.textViews.firstMatch
        XCTAssertEqual(editor.value as? String, "First thought\n\nSecond thought")
    }

    func testAddIsDisabledUntilTextIsEntered() {
        app.buttons["Type"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
    }

    func testCancelWithTextAsksBeforeDiscarding() {
        app.buttons["Type"].tap()
        let field = app.textFields["What do you want to capture?"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Draft")
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()

        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "")
    }
}
