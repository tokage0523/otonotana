import XCTest

final class PlayerUITests: XCTestCase {
    func testLyricsExportDeletionCancelAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--lyrics-management-fixture", "--reset-ui-preferences"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lyrics management,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(row.label.contains("歌詞あり"))
        row.tap()
        if app.buttons["player-play-pause"].label == "一時停止" { app.buttons["player-play-pause"].tap() }
        app.buttons["lyrics-toggle"].tap()
        func menu() {
            let options = app.buttons["lyrics-options"]
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        menu()
        app.buttons["lyrics-delete"].tap()
        XCTAssertTrue(app.buttons["lyrics-delete-confirm"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["lyric-0.001"].exists)
        menu()
        app.buttons["lyrics-delete"].tap()
        app.buttons["lyrics-delete-confirm"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["この曲に歌詞を添えよう"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player-play-pause"].label, "再生")
        capture(app, "29-lyrics-removed")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(row.label.contains("歌詞あり"))
        // The LRC remains alongside the audio; relaunch triggers a fresh shared scan.
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        if app.buttons["player-play-pause"].label == "一時停止" { app.buttons["player-play-pause"].tap() }
        app.buttons["lyrics-toggle"].tap()
        XCTAssertTrue(app.staticTexts["この曲に歌詞を添えよう"].waitForExistence(timeout: 5))
        app.buttons["player-play-pause"].tap()
        XCTAssertEqual(app.buttons["player-play-pause"].label, "一時停止")
        app.buttons["player-play-pause"].tap()
        app.buttons["player-options"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["曲の情報を編集"].tap()
        let location = app.staticTexts["track-file-location"]
        for _ in 0..<6 { if location.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(location.isHittable)
        XCTAssertEqual(location.label, "音の棚 / Lyrics management.wav")
        let size = app.descendants(matching: .any).matching(identifier: "track-file-size").firstMatch
        XCTAssertTrue(size.exists)
        XCTAssertFalse(size.label.contains("確認できません"))
        capture(app, "30-file-and-storage-information")
        app.buttons["キャンセル"].tap()
        app.buttons["閉じる"].tap()
        app.buttons["track-00000000-0000-0000-0000-000000000002"].tap()
        if app.buttons["player-play-pause"].label == "一時停止" { app.buttons["player-play-pause"].tap() }
        app.buttons["lyrics-toggle"].tap()
        menu()
        app.buttons["lyrics-export"].tap()
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "保存"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 60)
        capture(app, "28-lrc-export")
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["lyrics-options"])
        waitForExpectations(timeout: 60)
    }

    func testModePaddingAndSeekBarTapAndDrag() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        let albums = app.buttons["mode-アルバム"]
        XCTAssertTrue(albums.waitForExistence(timeout: 15))
        // These physical taps are in empty padding, outside the glyphs.
        albums.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["A little light"].waitForExistence(timeout: 5))
        app.buttons["mode-曲"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let row = app.buttons["track-00000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let seek = app.descendants(matching: .any).matching(identifier: "seek-bar").firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player-play-pause"].label, "再生")
        // A 120-second fixture: the center is exactly 60 seconds.
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["1:00"].exists)
        XCTAssertEqual(app.buttons["player-play-pause"].label, "再生")
        // Pick up the thumb and drag it towards the right, then back left.
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: seek.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^1:3[0-3]$")).firstMatch.exists)
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: seek.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^0:2[6-9]$")).firstMatch.exists)
        // A tap during playback seeks without pausing it.
        app.buttons["player-play-pause"].tap()
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["player-play-pause"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^1:0[0-5]$")).firstMatch.exists)
        capture(app, "12-seek-bar")
    }

    func testAppAppearanceChangesAndPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        func choose(_ name: String) {
            app.buttons["tab-設定"].tap()
            app.buttons["settings-appearance"].tap()
            let key = name == "ダーク" ? "dark" : name == "ライト" ? "light" : "system"
            let option = app.buttons["appearance-\(key)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            if !app.buttons["settings-appearance"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
            app.buttons["tab-ライブラリ"].tap()
            XCTAssertTrue(app.buttons["mode-曲"].waitForExistence(timeout: 5))
        }
        func backgroundPixels() -> Data? {
            guard let image = app.screenshot().image.cgImage else { return nil }
            let region = CGRect(x: CGFloat(image.width) * 0.45, y: CGFloat(image.height) * 0.58, width: 10, height: 10)
            guard let cropped = image.cropping(to: region) else { return nil }
            var pixels = [UInt8](repeating: 0, count: 400)
            let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 10, height: 10, bitsPerComponent: 8,
                                              bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: 10, height: 10))
                return true
            }
            return rendered ? Data(pixels) : nil
        }
        choose("ダーク")
        let dark = backgroundPixels()
        XCTAssertNotNil(dark)
        capture(app, "13-dark-library")
        choose("ライト")
        let light = backgroundPixels()
        XCTAssertNotNil(light)
        XCTAssertNotEqual(dark, light)
        capture(app, "14-light-library")
        app.terminate(); app.launchArguments = ["--ui-test-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["mode-曲"].waitForExistence(timeout: 15))
        XCTAssertEqual(backgroundPixels(), light)
        choose("システム設定に従う")
        app.buttons["tab-設定"].tap()
        let picker = app.buttons["settings-appearance"]
        XCTAssertTrue((picker.label + " " + (picker.value as? String ?? "")).contains("システム設定に従う"))
        capture(app, "15-appearance-settings")
    }

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

    func testDirectM4AAACAndALACRegisterAndDecode() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--m4a-test-fixture"]
        app.launch()
        for name in ["直接AAC (Instrumental)", "直接ALAC"] {
            let search = app.textFields["library-search"]
            search.tap()
            if let value = search.value as? String, value.contains("直接") {
                app.buttons["検索を消す"].tap(); search.tap()
            }
            search.typeText(name)
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            row.tap()
            XCTAssertTrue(app.staticTexts["player-track-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["player-track-title"].label, name)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.buttons["閉じる"].tap()
        }
        capture(app, "16-direct-m4a")
    }

    func testTrackInformationLabelsAndNewFieldsPersist() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        func openDetails() {
            let row = app.buttons["track-00000000-0000-0000-0000-000000000002"]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.press(forDuration: 1)
            app.buttons["曲の情報を編集"].tap()
            XCTAssertTrue(app.textFields["曲名"].waitForExistence(timeout: 5))
        }
        func field(_ name: String) -> XCUIElement {
            let result = app.textFields[name]
            for _ in 0..<5 {
                if result.isHittable { break }
                let above = result.exists && result.frame.midY < app.frame.height * 0.25
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.4 : 0.7))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.45)))
            }
            return result
        }
        openDetails()
        XCTAssertTrue(app.staticTexts["曲名"].exists)
        XCTAssertTrue(app.staticTexts["アーティスト"].exists)
        XCTAssertEqual(app.textFields["曲名"].value as? String, "Afterglow")
        capture(app, "17-labeled-track-information")
        // Leave the old title/artist intact and add information that was absent.
        let genre = field("ジャンル"); genre.tap(); genre.typeText("Test Genre")
        app.buttons["information-keyboard-done"].tap()
        let year = field("発売年"); year.tap(); year.typeText("2026")
        app.buttons["information-keyboard-done"].tap()
        let composer = field("作曲者"); composer.tap(); composer.typeText("Test Composer")
        app.buttons["information-keyboard-done"].tap()
        app.buttons["保存"].tap()
        app.terminate(); app.launchArguments = ["--ui-test-fixture"]; app.launch()
        openDetails()
        XCTAssertEqual(field("ジャンル").value as? String, "Test Genre")
        XCTAssertEqual(field("発売年").value as? String, "2026")
        XCTAssertEqual(field("作曲者").value as? String, "Test Composer")
        capture(app, "18-extra-track-information")
        app.buttons["キャンセル"].tap()
    }

    func testUnreadableSharedFileReportsDetailsWithoutBlockingValidFiles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--m4a-test-fixture", "--broken-test-fixture"]
        app.launch()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 20))
        app.alerts.buttons["OK"].tap()
        app.buttons["tab-設定"].tap()
        let results = app.buttons["shared-import-results"]
        for _ in 0..<5 { if results.isHittable { break }; app.swipeUp() }
        results.tap()
        XCTAssertTrue(app.staticTexts["音楽ファイルを開けませんでした。ファイルの内容や転送状態の確認が必要です。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "エラー：")).firstMatch.exists)
        capture(app, "19-shared-import-details")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlaylistRemovalKeepsMusicAndTrashRestoresIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        let rowID = "track-00000000-0000-0000-0000-000000000002"
        app.buttons["tab-プレイリスト"].tap()
        app.buttons["add-playlist"].tap()
        app.textFields["collection-title"].tap(); app.textFields["collection-title"].typeText("Removal check")
        app.buttons["collection-add-00000000-0000-0000-0000-000000000002"].tap()
        app.buttons["collection-save"].tap()
        app.staticTexts["Removal check"].tap()
        app.buttons["playlist-track-00000000-0000-0000-0000-000000000002"].press(forDuration: 1)
        app.buttons["プレイリストから外す"].tap()
        XCTAssertTrue(app.staticTexts["曲がありません"].waitForExistence(timeout: 5))
        app.buttons["tab-ライブラリ"].tap()
        XCTAssertTrue(app.buttons[rowID].waitForExistence(timeout: 5))
        app.buttons[rowID].press(forDuration: 1)
        app.buttons["ライブラリから削除"].tap()
        let confirm = app.buttons["最近削除した曲へ移す"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons[rowID])
        waitForExpectations(timeout: 5)
        app.buttons["tab-設定"].tap()
        let trash = app.buttons["settings-trash"]
        for _ in 0..<4 { if trash.isHittable { break }; app.swipeUp() }
        trash.tap()
        let restore = app.buttons["trash-restore-00000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        capture(app, "20-recently-deleted")
        restore.tap()
        app.buttons["tab-ライブラリ"].tap()
        XCTAssertTrue(app.buttons[rowID].waitForExistence(timeout: 5))
    }

    func testLyricsTimingControlsAndRangeMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences"]
        app.launch()
        app.buttons["track-00000000-0000-0000-0000-000000000002"].tap()
        app.buttons["lyrics-toggle"].tap()
        app.buttons["lyrics-options"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["歌詞のタイミングを調整"].tap()
        app.buttons["lyrics-offset-later"].tap()
        app.buttons["lyrics-offset-later"].tap()
        XCTAssertTrue(app.staticTexts["lyrics-offset-value"].label.contains("0.2"))
        capture(app, "21-lyrics-timing")
        app.buttons["補正をリセット"].tap()
        app.buttons["lyrics-timing-close"].tap()
        let line = app.buttons["lyric-42.0"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.press(forDuration: 1)
        app.buttons["ここから繰り返す"].tap()
        line.press(forDuration: 1)
        app.buttons["ここまで繰り返す"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "lyrics-loop-status").firstMatch.waitForExistence(timeout: 5))
        capture(app, "22-lyrics-range-loop")
        app.buttons["解除"].tap()
        app.buttons["player-play-pause"].tap()
    }

    func testSwipeDeleteCancelAndConsecutiveRowsStayConsistent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--reset-ui-preferences", "--swipe-delete-fixture"]
        app.launch()
        let a = "track-00000000-0000-0000-0000-000000000004"
        let b = "track-00000000-0000-0000-0000-000000000005"
        let search = app.textFields["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap(); search.typeText("Swipe check\n")
        let count = app.staticTexts["library-song-count"]
        XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "2曲 · 名前順")
        func request(_ row: String) {
            app.buttons[row].swipeLeft()
            app.buttons["ライブラリから削除"].tap()
            XCTAssertTrue(app.buttons["最近削除した曲へ移す"].waitForExistence(timeout: 5))
        }
        request(a)
        // The swipe must not optimistically remove a row before confirmation.
        XCTAssertTrue(app.buttons[a].exists)
        XCTAssertTrue(app.buttons[b].exists)
        capture(app, "25-swipe-before-confirmation")
        app.buttons["キャンセル"].tap()
        XCTAssertEqual(count.label, "2曲 · 名前順")
        XCTAssertTrue(app.buttons[a].isHittable)
        XCTAssertTrue(app.buttons[b].isHittable)
        request(b)
        XCTAssertTrue(app.staticTexts["「Swipe check B」をライブラリから削除しますか？"].exists)
        app.buttons["最近削除した曲へ移す"].tap()
        XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[b].exists)
        XCTAssertEqual(count.label, "1曲 · 名前順")
        capture(app, "26-swipe-after-deleting-second-row")
        request(a)
        app.buttons["キャンセル"].tap()
        XCTAssertEqual(count.label, "1曲 · 名前順")
        request(a)
        app.buttons["最近削除した曲へ移す"].tap()
        XCTAssertTrue(app.staticTexts["曲が見つかりません"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[a].exists)
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["tab-設定"].tap()
        let trash = app.buttons["settings-trash"]
        for _ in 0..<4 { if trash.isHittable { break }; app.swipeUp() }
        trash.tap()
        for id in ["004", "005"] {
            let restore = app.buttons["trash-restore-00000000-0000-0000-0000-000000000" + id]
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            restore.tap()
        }
        app.buttons["tab-ライブラリ"].tap()
        XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[b].exists)
        XCTAssertEqual(count.label, "2曲 · 名前順")
        capture(app, "27-swipe-deleted-rows-restored")
    }

    func testZBackupTrashRelinkAndPlaybackRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--data-integrity-test"]
        app.launch()
        let status = app.staticTexts["data-integrity-result"]
        XCTAssertTrue(status.waitForExistence(timeout: 45))
        let completed = NSPredicate(format: "label == %@", "データの確認が完了しました")
        expectation(for: completed, evaluatedWith: status)
        waitForExpectations(timeout: 45)
        capture(app, "23-data-integrity-complete")
        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "--restore-playback-test"]
        app.launch()
        let row = app.buttons["track-00000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertEqual(app.buttons["player-play-pause"].label, "再生")
        XCTAssertTrue(app.staticTexts["0:34"].exists)
        capture(app, "24-restored-playback-position")
    }
}
