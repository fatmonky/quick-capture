import XCTest

final class HighlightUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHighlightAWordThenAddANoteUnderIt() {
        app.launchEnvironment["UITEST_SEED_TEXT"] = "> Adaptability is a dynamic process\n>\n> Second paragraph"
        app.launch()

        let textView = app.textViews.firstMatch
        textView.tap()
        // Select a word, then highlight it from the edit menu.
        let word = textView.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 80, dy: 22))
        word.doubleTap()
        let highlight = app.menuItems["Highlight & Note"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 3))
        attachScreenshot("edit-menu")
        highlight.tap()

        app.typeText("My note")
        attachScreenshot("after-note")
        let text = textView.value as? String ?? ""
        XCTAssertTrue(text.contains("=="), text)
        XCTAssertTrue(text.contains("process\n\nMy note\n\n> Second paragraph"), text)
    }
}
