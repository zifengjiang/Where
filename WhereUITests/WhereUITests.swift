import XCTest

final class WhereUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testAddAccessoryPresentsSceneDraft() {
        let app = XCUIApplication()
        app.launch()
        let addButton = app.buttons["添加场景"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let cancelChoice = app.buttons["取消"]
        if cancelChoice.waitForExistence(timeout: 3) {
            let sourceAttachment = XCTAttachment(screenshot: app.screenshot())
            sourceAttachment.name = "Where direct system photo source"
            sourceAttachment.lifetime = .keepAlways
            add(sourceAttachment)
            cancelChoice.tap()
        }
        XCTAssertTrue(app.navigationBars["场景"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["场景名称"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Where scene capture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
