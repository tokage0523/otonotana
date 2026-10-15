import Foundation

struct PlaylistPosition: Codable {
    let playlistID: UUID
    let index: Int
}

struct DeletedTrack: Identifiable, Codable {
    let id: UUID
    let track: Track
    let removedAt: Date
    let audioName: String?
    let positions: [PlaylistPosition]
}

struct LibraryCatalog: Codable {
    var version = 1
    var tracks: [Track]
    var playlists: [Playlist]
    var albums: [ManualAlbum]
    var deleted: [DeletedTrack]
}

struct PlaybackSnapshot: Codable {
    let order: PlaybackOrder
    let position: Double
}

struct PlaybackLoop: Equatable {
    let trackID: UUID
    let start: Double
    var end: Double?
}

struct BackupManifest: Codable {
    var format = "otonotana-backup"
    var version = 1
    let createdAt: Date
    var tracks: [Track]
    var playlists: [Playlist]
    var albums: [ManualAlbum]
    var audioFiles: [String: String]
    var artworkFiles: [String: String]
    var settings: [String: String]

    func validate() throws {
        guard format == "otonotana-backup", version == 1,
              Set(tracks.map(\.id)).count == tracks.count,
              Set(playlists.map(\.id)).count == playlists.count, Set(albums.map(\.id)).count == albums.count,
              tracks.allSatisfy({ ($0.lyricsOffset ?? 0).isFinite && abs($0.lyricsOffset ?? 0) <= 3600 && ($0.lyrics ?? []).allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds < Double(Int.max / 1000) } }) else {
            throw StorageError.invalidBackup
        }
        let ids = Set(tracks.map(\.id))
        guard playlists.allSatisfy({ Set($0.trackIDs).isSubset(of: ids) && Set($0.trackIDs).count == $0.trackIDs.count }),
              Set(artworkFiles.keys) == Set(tracks.compactMap(\.artworkFilename)),
              audioFiles.keys.allSatisfy({ UUID(uuidString: $0).map { ids.contains($0) } ?? false }) else { throw StorageError.invalidBackup }
    }
}

enum StorageError: LocalizedError {
    case invalidBackup, unsafePath, fileConflict, busy
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "音の棚のバックアップとして読み込めません。"
        case .unsafePath: return "保存先の場所を確認できません。"
        case .fileConflict: return "同じ場所に別のファイルがあります。ファイルを移動してから、もう一度試してください。"
        case .busy: return "読み込み中です。完了してから、もう一度試してください。"
        }
    }
}
