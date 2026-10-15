import Foundation

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("Failed: \(name)") }
}
let source = "[ar:artist]\n[offset:-500]\n[00:01.25][01:02.003]日本語\n[00:00.1]"
let lines = try Lyrics.parse(source)
check(lines.count == 3, "multiple timestamps")
check(lines[0].seconds == 0 && lines[0].text.isEmpty, "negative offset clamps to zero; instrumental line")
check(abs(lines[1].seconds - 0.75) < 0.00001, "centisecond fraction")
check(abs(lines[2].seconds - 61.503) < 0.00001, "millisecond fraction")
check(lines[1].text == "日本語", "UTF-8 text")
do {
    _ = try Lyrics.parse("[00:60.00]invalid\nplain lyrics")
    fatalError("Failed: invalid timestamps must be rejected")
} catch {}
print("Swift LRC parser checks passed.")

let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","title":"既存の曲","filename":"legacy.m4a"}"#
let oldTrack = try JSONDecoder().decode(Track.self, from: Data(legacy.utf8))
check(oldTrack.title == "既存の曲" && oldTrack.lyrics == nil, "legacy library migration")
check(oldTrack.artist == nil && oldTrack.artworkFilename == nil && !oldTrack.isFavorite, "missing optional metadata defaults")
var edited = oldTrack
edited.artist = "アーティスト"
edited.album = "アルバム"
edited.artworkFilename = "cover.jpg"
edited.favorite = true
edited.lyrics = lines
edited.discNumber = 2
edited.genre = "Game"
edited.releaseYear = 2026
edited.composer = "Composer"
edited.notes = "My notes"
let restored = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(edited))
check(restored == edited && restored.isFavorite, "artwork metadata and lyrics round trip")
print("Library compatibility and metadata checks passed.")

check(oldTrack.sharedPath == nil && oldTrack.trackNumber == nil, "legacy audio keeps original storage and optional order")
let a = UUID(), b = UUID(), c = UUID()
var queue = PlaybackOrder()
queue.start(a, in: [a, b, c])
check(queue.advance() == b && queue.advance() == c, "ordered queue advances")
check(queue.advance() == nil, "repeat off stops at end")
check(queue.retreat() == b && queue.advance() == c, "previous and next preserve actual history")
queue.repeatMode = .one
check(queue.advance(automatic: true) == c, "one repeat only on natural completion")
check(queue.advance() == nil, "one repeat does not trap manual next")
queue.repeatMode = .all
check(queue.advance() == a && queue.retreat() == c, "repeat all wraps and keeps history")
queue.setShuffle(true)
let shuffledNext = queue.advance()!
check(shuffledNext != c, "shuffle does not repeat current immediately")
check(queue.retreat() == c && queue.advance() == shuffledNext, "shuffle previous replays the actual previous song")
queue.remove(shuffledNext)
check(!queue.order.contains(shuffledNext), "deleted song removed from queue")
queue.start(a, in: [a, b])
queue.setShuffle(false); queue.repeatMode = .off
check(queue.advance() == b && queue.advance() == nil, "album context excludes other library songs")
let root = URL(fileURLWithPath: "/app/Documents", isDirectory: true)
check(SharedFiles.safeURL("Album/song.m4a", under: root)?.path == "/app/Documents/Album/song.m4a", "shared audio uses original file path")
check(SharedFiles.safeURL("../library.json", under: root) == nil, "shared path cannot escape root")
check(SharedFiles.safeURL("/outside.m4a", under: root) == nil, "absolute shared path rejected")
check(SharedFiles.safeURL("", under: root) == nil, "empty shared path rejected")

// Reproduce the device-only failure: an enumerator can return the physical URL
// while the Documents URL uses a shorter alias. Character slicing is invalid.
let pathFixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let actualRoot = pathFixture.appendingPathComponent("ActualContainer/Documents", isDirectory: true)
let aliasRoot = pathFixture.appendingPathComponent("d", isDirectory: true)
try FileManager.default.createDirectory(at: actualRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: pathFixture) }
try FileManager.default.createSymbolicLink(at: aliasRoot, withDestinationURL: actualRoot)
let relative = "日本語 Album/ギフト (Instrumental) 100%.m4a"
let physicalFile = actualRoot.appendingPathComponent(relative)
try FileManager.default.createDirectory(at: physicalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("path fixture".utf8).write(to: physicalFile)
let aliasFile = aliasRoot.appendingPathComponent(relative)
let oldSlicedPath = String(physicalFile.path.dropFirst(aliasRoot.path.count + 1))
check(oldSlicedPath != relative, "old character slicing reproduces a malformed shared path")
check(SharedFiles.relativePath(for: physicalFile, under: aliasRoot) == relative, "physical file relative to aliased root")
check(SharedFiles.relativePath(for: aliasFile, under: actualRoot) == relative, "aliased file relative to physical root")
let recovered = SharedFiles.safeURL(relative, under: aliasRoot)!
let recoveredData = try Data(contentsOf: recovered)
check(recoveredData == Data("path fixture".utf8), "rebuilt shared path opens the original bytes")
check(SharedFiles.canonicalURL(recovered) == SharedFiles.canonicalURL(physicalFile), "alias path points to one original file")
let outside = pathFixture.appendingPathComponent("Outside", isDirectory: true)
try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
try FileManager.default.createSymbolicLink(at: actualRoot.appendingPathComponent("Escape"), withDestinationURL: outside)
check(SharedFiles.safeURL("Escape/song.m4a", under: actualRoot) == nil, "symlink cannot escape the shared root")
let realRoot = SharedFiles.canonicalURL(actualRoot)
if realRoot.path.hasPrefix("/private/var/") || realRoot.path.hasPrefix("/var/") {
    let shortRoot = URL(fileURLWithPath: realRoot.path.replacingOccurrences(of: "/private/var/", with: "/var/"), isDirectory: true)
    let longRoot = URL(fileURLWithPath: "/private" + shortRoot.path, isDirectory: true)
    if FileManager.default.fileExists(atPath: longRoot.path) {
        check(SharedFiles.relativePath(for: longRoot.appendingPathComponent(relative), under: shortRoot) == relative,
              "iOS-style private-var and var aliases produce the same shared path")
    }
}
print("Shared path alias regression checks passed.")
var song1 = Track(id: a, title: "Two", filename: "a.m4a")
var song2 = Track(id: b, title: "One", filename: "b.m4a")
song1.album = "Album"; song2.album = "Album"
song1.artist = "Singer 1"; song2.artist = "Singer 2"
song1.albumArtist = "Various"; song2.albumArtist = "Various"
song1.trackNumber = 2; song2.trackNumber = 1
let groups = AlbumGroup.groups(tracks: [song1, song2], manual: [])
check(groups.count == 1 && groups[0].tracks.map(\.id) == [b, a], "album artist groups mixed singers in track order")
let manualID = UUID()
song1.albumID = manualID; song2.albumID = manualID
let manual = AlbumGroup.groups(tracks: [song1, song2], manual: [ManualAlbum(id: manualID, title: "Manual", artist: "Edited")])
check(manual[0].title == "Manual" && manual[0].artist == "Edited", "manual album metadata overrides tags")
let playlist = Playlist(id: UUID(), title: "Set", trackIDs: [b, a])
let restoredPlaylist = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(playlist))
check(restoredPlaylist == playlist, "playlist order persists as references")
print("Queue, album grouping, playlist persistence and shared path checks passed.")
