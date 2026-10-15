#if DEBUG
import Foundation
import UIKit
import AVFoundation

extension MusicLibrary {
    func prepareUITestFixture() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-preferences") {
            UserDefaults.standard.removeObject(forKey: "lyricsAutoScroll")
            UserDefaults.standard.removeObject(forKey: "playerTheme")
            UserDefaults.standard.removeObject(forKey: "appAppearance")
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
            let layoutFixture = ProcessInfo.processInfo.arguments.contains("--album-layout-fixture")
            let albumName = layoutFixture ? "A very long album title that must occupy two full lines" : "A little light"
            if tracks.first(where: { $0.id == id })?.album != albumName {
                updateDetails(for: id, title: "Afterglow", artist: "Sample Artist", album: albumName)
            }
            if layoutFixture {
                let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
                if !tracks.contains(where: { $0.id == otherID }) { try createUITestTrack(id: otherID) }
                updateDetails(for: otherID, title: "Other sample", artist: "Sample Artist", album: "Short")
            }
            if ProcessInfo.processInfo.arguments.contains("--swipe-delete-fixture") {
                for (suffix, title) in [("004", "Swipe check A"), ("005", "Swipe check B")] {
                    let swipeID = UUID(uuidString: "00000000-0000-0000-0000-000000000" + suffix)!
                    if !tracks.contains(where: { $0.id == swipeID }) { try createUITestTrack(id: swipeID) }
                    updateDetails(for: swipeID, title: title, artist: "Swipe test", album: "Swipe test")
                }
            } else if !ProcessInfo.processInfo.arguments.contains("--restore-playback-test"), let track = tracks.first(where: { $0.id == id }) { select(track); pause(); seek(42) }
            if ProcessInfo.processInfo.arguments.contains("--shared-test-fixture"), let track = tracks.first(where: { $0.id == id }) {
                let target = sharedDirectory.appendingPathComponent("Shared test.wav")
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: audioURL(for: track), to: target) }
                try "[00:00.000]共有ファイルの歌詞\n[00:12.000]次の行".write(to: target.deletingPathExtension().appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
            }
            if ProcessInfo.processInfo.arguments.contains("--m4a-test-fixture") {
                let folder = sharedDirectory.appendingPathComponent("共有 テスト", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (name, codec) in [("直接AAC (Instrumental)", kAudioFormatMPEG4AAC), ("直接ALAC", kAudioFormatAppleLossless)] {
                    try makeM4AFixture(at: folder.appendingPathComponent(name).appendingPathExtension("m4a"), codec: codec)
                }
                if ProcessInfo.processInfo.arguments.contains("--broken-test-fixture") {
                    try Data("invalid audio".utf8).write(to: folder.appendingPathComponent("Broken.m4a"))
                }
            }
        } catch { message = error.localizedDescription }
    }

    private func makeM4AFixture(at url: URL, codec: AudioFormatID) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        var settings: [String: Any] = [AVFormatIDKey: codec, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1]
        if codec == kAudioFormatMPEG4AAC { settings[AVEncoderBitRateKey] = 64000 }
        else { settings[AVEncoderBitDepthHintKey] = 16 }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100)!
        buffer.frameLength = 44100
        for frame in 0..<44100 { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.1) }
        for _ in 0..<12 { try file.write(from: buffer) }
    }
}
#endif
