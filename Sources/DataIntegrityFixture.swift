#if DEBUG
import Foundation

extension MusicLibrary {
    func runDataIntegrityChecks() async {
        verificationStatus = "確認中"
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "DataIntegrity", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var temporary: [URL] = []
        defer { for url in temporary { try? FileManager.default.removeItem(at: url) } }
        do {
            message = nil
            let brokenFixture = sharedDirectory.appendingPathComponent("共有 テスト/Broken.m4a")
            if FileManager.default.fileExists(atPath: brokenFixture.path) { try FileManager.default.removeItem(at: brokenFixture) }
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            guard let initial = tracks.first(where: { $0.id == id }) else { throw StorageError.invalidBackup }
            let originalBytes = try Data(contentsOf: audioURL(for: initial))
            let listID = UUID()
            savePlaylist(id: listID, title: "Data check", trackIDs: [id])
            removeFromPlaylist(id, playlistID: listID)
            try require(FileManager.default.fileExists(atPath: audioURL(for: initial).path), "Removing from playlist deleted the audio")
            savePlaylist(id: listID, title: "Data check", trackIDs: [id])
            select(initial); pause(); setLyricsOffset(0.2)
            let edited = tracks.first { $0.id == id }!
            remove(edited)
            try require(!FileManager.default.fileExists(atPath: audioURL(for: edited).path), "Deleted song still present in shared scan")
            let deleted = deletedTracks.first { $0.track.id == id }!
            restoreDeleted(deleted)
            try require(playlists.first { $0.id == listID }?.trackIDs == [id], "Restore did not preserve playlist order")
            let restoredBytes = try Data(contentsOf: audioURL(for: tracks.first { $0.id == id }!))
            try require(restoredBytes == originalBytes, "Trash restore changed audio bytes")
            let metadataBackup = try await createBackup(includeAudio: false); temporary.append(metadataBackup)
            let metadata = try BackupFiles.readManifest(at: metadataBackup)
            try require(metadata.audioFiles.isEmpty, "Metadata backup contains duplicated music")
            let fullBackup = try await createBackup(includeAudio: true); temporary.append(fullBackup)
            updateDetails(for: id, title: "Changed temporarily", artist: "Changed", album: "Changed")
            removePlaylist(playlists.first { $0.id == listID }!)
            try await restoreBackup(from: metadataBackup)
            try require(tracks.first { $0.id == id }?.title == edited.title, "Metadata restore lost original title")
            try require(tracks.first { $0.id == id }?.lyrics == edited.lyrics && tracks.first { $0.id == id }?.lyricsOffset == 0.2, "Lyrics/offset did not restore")
            try require(playlists.first { $0.id == listID }?.trackIDs == [id], "Backup restore lost playlist references")
            let active = tracks.first { $0.id == id }!
            remove(active)
            let trashedAgain = deletedTracks.first { $0.track.id == id }!
            try await restoreBackup(from: fullBackup)
            let recovered = tracks.first { $0.id == id }!
            let bytes = try Data(contentsOf: audioURL(for: recovered))
            try require(bytes == originalBytes, "Full backup did not restore original audio")
            permanentlyDelete(trashedAgain)
            let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            temporary.append(invalid)
            try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
            var badManifest = metadata; badManifest.version = 999
            try JSONEncoder().encode(badManifest).write(to: invalid.appendingPathComponent(BackupFiles.manifestName))
            let before = tracks
            var rejected = false
            do { try await restoreBackup(from: invalid) } catch { rejected = true }
            try require(rejected && tracks == before, "Invalid backup changed the live catalog")
            // Simulate a PC-side move, scan the new name, then reconnect the old
            // entry. Its ID and manually entered lyrics must survive the merge.
            let oldURL = audioURL(for: recovered)
            let newURL = sharedDirectory.appendingPathComponent("Moved-" + UUID().uuidString + ".wav")
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            refreshMissingTracks()
            try require(missingTrackIDs.contains(id), "Moved file was not detected")
            await scanSharedFiles()
            await relink(id, to: newURL)
            try require(!missingTrackIDs.contains(id), "Reconnected file is still missing")
            try require(tracks.first { $0.id == id }?.lyrics == edited.lyrics, "Reconnecting lost lyric editing")
            let matches = tracks.filter { SharedFiles.canonicalURL(audioURL(for: $0)) == SharedFiles.canonicalURL(newURL) }
            try require(matches.count == 1, "Reconnecting produced duplicate entries")
            let final = tracks.first { $0.id == id }!
            select(final); pause(); setLyricsOffset(0)
            let lines = final.lyrics!
            setLoopStart(lines[0]); setLoopEnd(lines[0])
            let end = lyricLoop!.end!
            seek(end - 0.1); resume()
            try await Task.sleep(nanoseconds: 900_000_000)
            pause()
            try require(position < 3 && lyricLoop != nil, "Lyric range did not loop")
            clearLyricLoop(); seek(34); pause(); savePlaybackState()
            verificationStatus = "データの確認が完了しました"
        } catch { verificationStatus = "確認に失敗：" + error.localizedDescription }
    }
}
#endif
