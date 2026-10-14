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
let restored = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(edited))
check(restored == edited && restored.isFavorite, "artwork metadata and lyrics round trip")
print("Library compatibility and metadata checks passed.")
