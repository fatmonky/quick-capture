import XCTest

/// Takes the App Store screenshots. Skipped in the normal run; to take them:
///
///     TEST_RUNNER_SCREENSHOTS=1 xcodebuild test … -only-testing:QuickCaptureUITests/AppStoreScreenshots
///
/// on an iPhone Pro Max simulator, then export the attachments from the result bundle.
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    /// Walden (1854), in the public domain.
    private static let page = """
    > I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not ==learn what it had to teach==, and not, when I came to die, discover that I had not lived.

    Living on purpose rather than by default. What would I keep if I had to choose?

    > ==Our life is frittered away by detail.== An honest man has hardly need to count more than his ten fingers, or in extreme cases he may add his ten toes, and lump the rest.
    >
    > ==Simplicity, simplicity, simplicity!== I say, let your affairs be as two or three, and not a hundred or a thousand.

    Fewer projects, done properly. Try this with next quarter's plan.

    > Time is but the stream I go a-fishing in. I drink at it; but while I drink I see the sandy bottom and detect how shallow it is.
    """

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOTS=1 to take the App Store screenshots")
        }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment["UITEST_SEED_TEXT"] = Self.page
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func addTags() {
        app.buttons["Tags"].tap()
        let field = app.textFields["tagField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("simplicity #walden")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Tags: #simplicity #walden"].waitForExistence(timeout: 3))
    }

    func test1Page() {
        app.launch()
        addTags()
        shot("01_page")
    }

    func test2Export() {
        app.launch()
        addTags()
        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["Share PDF"].waitForExistence(timeout: 3))
        shot("03_export")
    }

    func test3WhatsApp() {
        app.launch()
        app.buttons["Export"].tap()
        app.buttons["Send to WhatsApp"].tap()
        let title = app.textFields["Book or topic"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        let old = (title.value as? String) ?? ""
        if old != "Book or topic" {
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        title.typeText("Walden")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["whatsappText"].waitForExistence(timeout: 3))
        shot("04_whatsapp")
    }

    func test4Snap() throws {
        app.launch()
        app.buttons["Snap"].tap()
        app.buttons["Choose from Photos"].tap()
        guard app.images.firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("No photos in the simulator library")
        }
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.455)).tap()

        let photo = app.otherElements["Photo of the text"]
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        // Pick the first two paragraphs of the page (a 3:4 photo, fitted and centred).
        let area = photo.frame
        let height = min(area.height, area.width * 4 / 3)
        let top = (area.height - height) / 2
        for y in [0.29, 0.43] {
            photo.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: area.width / 2, dy: top + height * y)).tap()
        }
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        shot("02_snap")
    }
}
