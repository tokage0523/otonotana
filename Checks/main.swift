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
