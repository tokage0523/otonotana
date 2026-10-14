import XCTest

final class PlayerUITests: XCTestCase {
    func testArtworkLyricsControlsAndPreferencesPersist() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        let rowID = "track-00000000-0000-0000-0000-000000000002"
        XCTAssertTrue(app.buttons[rowID].waitForExistence(timeout: 15))
        app.buttons[rowID].tap()
        XCTAssertTrue(app.buttons["lyrics-toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-track-title"].exists)
        capture(app, "01-artwork-player")

        app.buttons["lyrics-toggle"].tap()
        let follow = app.buttons["lyrics-follow-toggle"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertEqual(follow.value as? String, "オン")
        capture(app, "02-lyrics-follow-on")
        follow.tap()
        XCTAssertEqual(follow.value as? String, "オフ")
        app.buttons["lyric-42.0"].tap()
        XCTAssertTrue(app.buttons["player-play-pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player-play-pause"].label, "一時停止")
        XCTAssertTrue(app.staticTexts["0:42"].exists)
        app.buttons["player-play-pause"].tap()
        capture(app, "03-lyrics-follow-off")

        // Browsing earlier lyrics must stay possible when auto-scroll is disabled.
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(follow.value as? String, "オフ")
        app.buttons["favorite-toggle"].tap()
        XCTAssertEqual(app.buttons["favorite-toggle"].label, "お気に入りを解除")
        app.terminate()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons[rowID].waitForExistence(timeout: 15))
        app.buttons[rowID].tap()
        XCTAssertTrue(app.buttons["lyrics-toggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["favorite-toggle"].label, "お気に入りを解除")
        app.buttons["lyrics-toggle"].tap()
        XCTAssertEqual(app.buttons["lyrics-follow-toggle"].value as? String, "オフ")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
