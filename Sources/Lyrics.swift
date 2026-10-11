import Foundation

struct LyricLine: Codable, Identifiable, Equatable {
    let id: UUID
    let seconds: Double
    let text: String
}

enum Lyrics {
    // UTF-8 LRC: [mm:ss.xx]text; repeated timestamps and millisecond offsets supported.
    static func parse(_ source: String) throws -> [LyricLine] {
        let pattern = try NSRegularExpression(pattern: #"\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]"#)
        let offsetPattern = try NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let fullRange = NSRange(source.startIndex..., in: source)
        var offset = 0.0
        if let match = offsetPattern.firstMatch(in: source, range: fullRange),
           let range = Range(match.range(at: 1), in: source), let ms = Double(source[range]) {
            offset = ms / 1000
        }
        var lines: [LyricLine] = []
        for raw in source.components(separatedBy: .newlines) {
            let matches = pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            guard let last = matches.last, let lastRange = Range(last.range, in: raw) else { continue }
            let text = String(raw[lastRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: raw),
                      let secondRange = Range(match.range(at: 2), in: raw),
                      let minutes = Double(raw[minuteRange]), let seconds = Double(raw[secondRange]) else { continue }
                var fraction = 0.0
                if let range = Range(match.range(at: 3), in: raw) {
                    fraction = Double("0." + raw[range]) ?? 0
                }
                let value = minutes * 60 + seconds + fraction + offset
                guard value.isFinite else { continue }
                lines.append(LyricLine(id: UUID(), seconds: max(0, value), text: text))
            }
        }
        guard !lines.isEmpty else {
            throw NSError(domain: "Lyrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "時刻付きの歌詞が見つかりません。PCの編集画面でLRCを保存してください。"])
        }
        return lines.enumerated().sorted {
            $0.element.seconds == $1.element.seconds ? $0.offset < $1.offset : $0.element.seconds < $1.element.seconds
        }.map(\.element)
    }
}
