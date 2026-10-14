import XCTest

final class PlayerUITests: XCTestCase {
    func testAlbumCoversAndTitlesAlignForDifferentTitleLengths() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--album-layout-fixture"]
        app.launch()
        app.buttons["mode-アルバム"].tap()
        let covers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "album-cover-"))
        XCTAssertEqual(covers.count, 2)
        XCTAssertEqual(covers.element(boundBy: 0).frame.minY, covers.element(boundBy: 1).frame.minY, accuracy: 1)
        XCTAssertEqual(covers.element(boundBy: 0).frame.height, covers.element(boundBy: 1).frame.height, accuracy: 1)
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "album-title-"))
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles.element(boundBy: 0).frame.minY, titles.element(boundBy: 1).frame.minY, accuracy: 1)
        XCTAssertEqual(titles.element(boundBy: 0).frame.height, titles.element(boundBy: 1).frame.height, accuracy: 1)
        capture(app, "10-album-alignment")
    }

    func testPlayerMenuRemainsStableDuringPlaybackAndActionsWork() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        app.buttons["track-00000000-0000-0000-0000-000000000002"].tap()
        app.buttons["player-play-pause"].tap()
        // Native popover buttons can refuse XCTest's scroll-to-visible action
        // during playback. Use a physical tap at the button's displayed center.
        let options = app.buttons["player-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let action = app.buttons["曲の情報を編集"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        let before = action.frame
        let first = action.screenshot().image.cgImage?.dataProvider?.data
        Thread.sleep(forTimeInterval: 0.8)
        let later = action.screenshot().image.cgImage?.dataProvider?.data
        XCTAssertEqual(action.frame, before)
        XCTAssertNotNil(first); XCTAssertNotNil(later)
        XCTAssertEqual(first as Data?, later as Data?)
        capture(app, "11-player-menu")
        action.tap()
        XCTAssertTrue(app.textFields["曲名"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["lyrics-toggle"].waitForExistence(timeout: 5))
    }

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
        let preview = app.descendants(matching: .any).matching(identifier: "lyrics-preview").firstMatch
        XCTAssertTrue(preview.exists)
        XCTAssertLessThanOrEqual(preview.frame.maxY, app.staticTexts["player-track-title"].frame.minY)
        capture(app, "01-artwork-player")

        app.buttons["lyrics-toggle"].tap()
        let follow = app.buttons["lyrics-follow-toggle"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertEqual(follow.value as? String, "オン")
        capture(app, "02-lyrics-follow-on")
        app.buttons["lyrics-size-0"].tap()
        app.buttons["lyrics-size-2"].tap()
        app.buttons["lyrics-size-1"].tap()
        follow.tap()
        XCTAssertEqual(follow.value as? String, "オフ")
        app.buttons["lyric-28.0"].tap()
        XCTAssertTrue(app.buttons["player-play-pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player-play-pause"].label, "一時停止")
        app.buttons["player-play-pause"].tap()
        // Playback keeps advancing while XCTest queries the screen. Verify the
        // selected section after pausing instead of expecting an exact second.
        let selectedSectionTime = NSPredicate(format: "label MATCHES %@", "^0:(2[89]|3[0-9]|4[01])$")
        XCTAssertTrue(app.staticTexts.matching(selectedSectionTime).firstMatch.exists)
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

    func testLibraryModesEqualSpacingAndPlaylistPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        let modes = ["曲", "アルバム", "アーティスト"].map { app.buttons["mode-\($0)"] }
        XCTAssertTrue(modes[0].waitForExistence(timeout: 15))
        XCTAssertEqual(modes[1].frame.midX - modes[0].frame.midX, modes[2].frame.midX - modes[1].frame.midX, accuracy: 1.5)
        let tabs = ["ライブラリ", "プレイリスト", "設定"].map { app.buttons["tab-\($0)"] }
        XCTAssertEqual(tabs[1].frame.midX - tabs[0].frame.midX, tabs[2].frame.midX - tabs[1].frame.midX, accuracy: 1.5)
        capture(app, "04-songs-library")
        modes[1].tap()
        XCTAssertTrue(app.staticTexts["A little light"].waitForExistence(timeout: 5))
        capture(app, "05-albums-library")
        app.staticTexts["A little light"].tap()
        XCTAssertTrue(app.buttons["アルバムを編集"].waitForExistence(timeout: 5))
        capture(app, "06-album-detail")
        tabs[1].tap()
        app.buttons["add-playlist"].tap()
        let name = "My test set"
        app.textFields["collection-title"].tap(); app.textFields["collection-title"].typeText(name)
        app.buttons["collection-add-00000000-0000-0000-0000-000000000002"].tap()
        app.buttons["collection-save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        capture(app, "07-playlists")
        tabs[2].tap()
        XCTAssertTrue(app.switches["settings-timestamps"].waitForExistence(timeout: 5))
        capture(app, "08-settings")
        app.terminate(); app.launchArguments = ["--ui-test-fixture"]; app.launch()
        app.buttons["tab-プレイリスト"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    func testSharedAudioAndMatchingLyricsAreRegistered() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--shared-test-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Shared test"].waitForExistence(timeout: 20))
        app.staticTexts["Shared test"].tap()
        app.buttons["lyrics-toggle"].tap()
        XCTAssertTrue(app.buttons["lyric-0.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lyric-0.0"].label.contains("共有ファイルの歌詞"))
        app.buttons["lyric-12.0"].tap()
        app.buttons["player-play-pause"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^0:1[2-9]$")).firstMatch.exists)
        capture(app, "09-shared-lyrics")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
