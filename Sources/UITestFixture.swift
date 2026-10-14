#if DEBUG
import Foundation
import UIKit

extension MusicLibrary {
    func prepareUITestFixture() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-preferences") {
            UserDefaults.standard.removeObject(forKey: "lyricsAutoScroll")
            UserDefaults.standard.removeObject(forKey: "playerTheme")
        }
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        do {
            if !tracks.contains(where: { $0.id == id }) {
                try createUITestTrack(id: id)
            }
            if let track = tracks.first(where: { $0.id == id }) { select(track); pause(); seek(42) }
        } catch { message = error.localizedDescription }
    }
}
#endif
