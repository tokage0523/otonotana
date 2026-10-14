import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var trackIDs: [UUID]
}

struct ManualAlbum: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
}

struct AlbumGroup: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
    var artworkTrack: Track? { tracks.first(where: { $0.artworkFilename != nil }) ?? tracks.first }

    static func groups(tracks: [Track], manual: [ManualAlbum]) -> [AlbumGroup] {
        let grouped = Dictionary(grouping: tracks) { track -> String in
            if let id = track.albumID { return "manual:\(id.uuidString)" }
            let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if album.isEmpty { return "single:\(track.id.uuidString)" }
            let artist = track.albumArtist?.isEmpty == false ? track.albumArtist! : track.artist ?? ""
            return "tag:\(album.lowercased())\u{1f}\(artist.lowercased())"
        }
        return grouped.map { key, values in
            let ordered = values.sorted {
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                if ($0.trackNumber ?? Int.max) != ($1.trackNumber ?? Int.max) { return ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let record = manual.first { $0.id == ordered[0].albumID }
            return AlbumGroup(id: key, title: record?.title ?? ordered[0].album?.nonEmpty ?? ordered[0].title,
                              artist: record?.artist.nonEmpty ?? ordered[0].albumArtist?.nonEmpty ?? ordered[0].artist?.nonEmpty ?? "アーティスト未設定", tracks: ordered)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var label: String { self == .off ? "リピート OFF" : self == .all ? "全曲リピート" : "1曲リピート" }
}

struct PlaybackOrder {
    private(set) var source: [UUID] = []
    private(set) var order: [UUID] = []
    private(set) var current: UUID?
    private(set) var history: [UUID] = []
    private(set) var future: [UUID] = []
    var shuffled = false
    var repeatMode: RepeatMode = .off

    mutating func start(_ id: UUID, in ids: [UUID]) {
        source = Array(ids.enumerated().filter { ids.firstIndex(of: $0.element) == $0.offset }.map(\.element))
        if !source.contains(id) { source.append(id) }
        current = id; history = []; future = []
        rebuild()
    }
    mutating func setShuffle(_ enabled: Bool) { shuffled = enabled; future = []; rebuild() }
    private mutating func rebuild() {
        order = shuffled ? source.filter { $0 != current }.shuffled() : source
        if shuffled, let current { order.insert(current, at: 0) }
    }
    func canAdvance(automatic: Bool = false) -> Bool {
        if automatic && repeatMode == .one { return current != nil }
        guard let current, let index = order.firstIndex(of: current) else { return false }
        return !future.isEmpty || index + 1 < order.count || repeatMode == .all
    }
    mutating func advance(automatic: Bool = false) -> UUID? {
        guard let current else { return nil }
        if automatic && repeatMode == .one { return current }
        let next: UUID
        if let revisit = future.popLast() { next = revisit }
        else if let index = order.firstIndex(of: current), index + 1 < order.count { next = order[index + 1] }
        else if repeatMode == .all, !order.isEmpty {
            if shuffled && order.count > 1 {
                order.shuffle()
                if order.first == current { order.swapAt(0, 1) }
            }
            next = order[0]
        } else { return nil }
        history.append(current); self.current = next; return next
    }
    mutating func retreat() -> UUID? {
        guard let previous = history.popLast() else { return nil }
        if let current { future.append(current) }
        current = previous; return previous
    }
    mutating func remove(_ id: UUID) {
        source.removeAll { $0 == id }; order.removeAll { $0 == id }
        history.removeAll { $0 == id }; future.removeAll { $0 == id }
        if current == id { current = nil }
    }
}

enum SharedFiles {
    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf"]
    static func safeURL(_ relativePath: String, under root: URL) -> URL? {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else { return nil }
        let target = root.appendingPathComponent(relativePath).standardizedFileURL
        let base = root.standardizedFileURL.path + "/"
        return target.path.hasPrefix(base) ? target : nil
    }
}
