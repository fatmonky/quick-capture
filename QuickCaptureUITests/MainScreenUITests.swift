import XCTest

final class MainScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTypingDirectlyIntoTextSpace() {
        app.launch()

        XCTAssertFalse(app.buttons["Type"].exists)
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("Typed straight in")
        app.buttons["Done"].tap()

        XCTAssertEqual(editor.value as? String, "Typed straight in")
        attachScreenshot("typed-directly")
    }

    func testScrollsToNewlyAddedCapture() {
        let longText = (1...60).map { "Earlier line \($0)" }.joined(separator: "\n")
        app.launchEnvironment["UITEST_SEED_TEXT"] = longText
        app.launchEnvironment["UITEST_APPEND_TEXT"] = "Newest capture"
        app.launch()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let appended = NSPredicate(format: "value ENDSWITH %@", "Newest capture")
        wait(for: [expectation(for: appended, evaluatedWith: editor)], timeout: 5)
        sleep(1)
        attachScreenshot("after-append")

        // Tapping the bottom of the text area puts the cursor in whatever text is
        // shown there. It only lands after the newest capture if the view scrolled to the end.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        editor.typeText("!")

        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.hasSuffix("Earlier line 60\n\nNewest capture!"),
                      "Cursor wasn't at the end, so the view didn't scroll to the newest capture")
    }

    func testEditingShowsDoneInsteadOfShareButtons() {
        app.launchEnvironment["UITEST_SEED_TEXT"] = "Some text"
        app.launch()

        XCTAssertTrue(app.buttons["Export"].exists)
        app.textViews.firstMatch.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Export"].exists)
        done.tap()

        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
}
