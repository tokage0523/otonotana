import Foundation

struct PreparedRestore {
    let manifest: BackupManifest
    let staging: URL
    let audioFolder: URL
    let finalAudioFolder: URL
    let artwork: [String: URL]
    let replaces: [UUID: UUID]
}

enum BackupFiles {
    static let manifestName = "otonotana-backup.json"
    static let settingsKeys = ["appAppearance", "playerTheme", "lyricsTimestamps", "lyricsPreview", "lyricsAutoScroll", "lyricsSize"]

    static func export(manifest original: BackupManifest, audio: [UUID: URL], artworkRoot: URL, includeAudio: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("音の棚バックアップ-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var manifest = original
            if includeAudio {
                let target = folder.appendingPathComponent("Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                for track in original.tracks {
                    guard let source = audio[track.id], FileManager.default.fileExists(atPath: source.path) else {
                        throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "音楽が見つからない曲があります。保存場所を指定し直すか、音楽を含めずにバックアップしてください。"])
                    }
                    let name = track.id.uuidString + "." + source.pathExtension
                    try FileManager.default.copyItem(at: source, to: target.appendingPathComponent(name))
                    manifest.audioFiles[track.id.uuidString] = "Audio/" + name
                }
            }
            let images = Set(original.tracks.compactMap(\.artworkFilename))
            if !images.isEmpty { try FileManager.default.createDirectory(at: folder.appendingPathComponent("Artwork"), withIntermediateDirectories: true) }
            for name in images {
                guard let source = SharedFiles.safeURL(name, under: artworkRoot), FileManager.default.fileExists(atPath: source.path) else { throw StorageError.invalidBackup }
                let destination = "Artwork/" + UUID().uuidString + ".jpg"
                try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(destination))
                manifest.artworkFiles[name] = destination
            }
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(manifestName), options: .atomic)
            return folder
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func readManifest(at folder: URL) throws -> BackupManifest {
        guard let path = SharedFiles.safeURL(manifestName, under: folder) else { throw StorageError.invalidBackup }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: path))
        try manifest.validate()
        return manifest
    }

    static func prepareRestore(at folder: URL, existing: [Track], sharedRoot: URL, supportRoot: URL) throws -> PreparedRestore {
        var manifest = try readManifest(at: folder)
        let staging = supportRoot.appendingPathComponent("RestoreStaging-" + UUID().uuidString, isDirectory: true)
        let audioFolder = staging.appendingPathComponent("Audio", isDirectory: true)
        let finalAudioFolder = sharedRoot.appendingPathComponent("Restored/" + UUID().uuidString, isDirectory: true)
        var artwork: [String: URL] = [:], names: [String: String] = [:], replaces: [UUID: UUID] = [:]
        do {
            try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
            var archivedAudio: [String: URL] = [:]
            for (id, path) in manifest.audioFiles {
                guard let source = SharedFiles.safeURL(path, under: folder),
                      FileManager.default.fileExists(atPath: source.path), SharedFiles.audioExtensions.contains(source.pathExtension.lowercased()) else { throw StorageError.invalidBackup }
                archivedAudio[id] = source
            }
            for (oldName, archivedPath) in manifest.artworkFiles {
                guard let source = SharedFiles.safeURL(archivedPath, under: folder) else { throw StorageError.invalidBackup }
                let name = UUID().uuidString + ".jpg", target = staging.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: target)
                artwork[name] = target; names[oldName] = name
            }
            for index in manifest.tracks.indices {
                var track = manifest.tracks[index]
                if let art = track.artworkFilename {
                    guard let name = names[art] else { throw StorageError.invalidBackup }
                    track.artworkFilename = name
                }
                let matching = existing.first { $0.id == track.id } ?? existing.first { $0.sharedPath != nil && $0.sharedPath == track.sharedPath }
                if let matching, let path = matching.sharedPath, let file = SharedFiles.safeURL(path, under: sharedRoot), FileManager.default.fileExists(atPath: file.path),
                   archivedAudio[track.id.uuidString].map({ FileManager.default.contentsEqual(atPath: file.path, andPath: $0.path) }) ?? true {
                    track.sharedPath = path; track.filename = matching.filename
                    if matching.id != track.id { replaces[matching.id] = track.id }
                } else if let source = archivedAudio[track.id.uuidString] {
                    let name = track.id.uuidString + "." + source.pathExtension
                    try FileManager.default.copyItem(at: source, to: audioFolder.appendingPathComponent(name))
                    guard let path = SharedFiles.relativePath(for: finalAudioFolder.appendingPathComponent(name), under: sharedRoot) else { throw StorageError.unsafePath }
                    track.sharedPath = path
                    if let matching, matching.id != track.id { replaces[matching.id] = track.id }
                } else {
                    guard let path = track.sharedPath, SharedFiles.safeURL(path, under: sharedRoot) != nil else { throw StorageError.invalidBackup }
                }
                manifest.tracks[index] = track
            }
            return PreparedRestore(manifest: manifest, staging: staging, audioFolder: audioFolder,
                                   finalAudioFolder: finalAudioFolder, artwork: artwork, replaces: replaces)
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }
}
