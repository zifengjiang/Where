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
        let addButton = app.buttons["add-scene-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let cancelChoice = app.buttons["取消"]
        if cancelChoice.waitForExistence(timeout: 2) { cancelChoice.tap() }
        XCTAssertTrue(app.navigationBars["添加场景"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["添加场景照片"].exists)
        XCTAssertTrue(app.buttons["下一步：标记物品"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Where scene capture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
