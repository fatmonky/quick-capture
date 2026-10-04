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

    func testNewCaptureIsAppendedAfterLongText() {
        let longText = (1...60).map { "Earlier line \($0)" }.joined(separator: "\n")
        app.launchEnvironment["UITEST_SEED_TEXT"] = longText
        app.launch()

        app.buttons["Type"].tap()
        let field = app.textFields["What do you want to capture?"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Newest capture")
        app.buttons["Add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        let value = app.textViews.firstMatch.value as? String ?? ""
        XCTAssertTrue(value.hasSuffix("Earlier line 60\n\nNewest capture"))
        sleep(1)
        attachScreenshot("after-append")
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
