#if DEBUG
import Foundation
import UIKit

extension MusicLibrary {
    func prepareUITestFixture() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-preferences") {
            UserDefaults.standard.removeObject(forKey: "lyricsAutoScroll")
            UserDefaults.standard.removeObject(forKey: "playerTheme")
            UserDefaults.standard.removeObject(forKey: "lyricsTimestamps")
            UserDefaults.standard.removeObject(forKey: "lyricsSize")
            if shuffleEnabled { toggleShuffle() }
            while repeatMode != .off { cycleRepeat() }
        }
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        do {
            if !tracks.contains(where: { $0.id == id }) {
                try createUITestTrack(id: id)
            }
            if let track = tracks.first(where: { $0.id == id }) { select(track); pause(); seek(42) }
            if ProcessInfo.processInfo.arguments.contains("--shared-test-fixture"), let track = tracks.first(where: { $0.id == id }) {
                let target = sharedDirectory.appendingPathComponent("Shared test.wav")
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: audioURL(for: track), to: target) }
                try "[00:00.000]共有ファイルの歌詞\n[00:12.000]次の行".write(to: target.deletingPathExtension().appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
            }
        } catch { message = error.localizedDescription }
    }
}
#endif
