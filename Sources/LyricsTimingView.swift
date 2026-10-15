import SwiftUI

struct LyricsTimingView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    private var offset: Double { library.current?.lyricsOffset ?? 0 }
    var body: some View {
        NavigationStack {
            Form {
                Section("歌詞全体のタイミング") {
                    Text(library.current?.title ?? "").font(.headline)
                    Text("歌詞の表示・タップで移動する時刻を、曲ごとにまとめて調整します。")
                    Text(offset == 0 ? "補正なし" : String(format: "%@ %.1f秒", offset > 0 ? "遅らせる" : "早める", abs(offset)))
                        .font(.title3.monospacedDigit()).accessibilityIdentifier("lyrics-offset-value")
                    HStack {
                        Button("0.1秒早める") { library.setLyricsOffset(offset - 0.1) }.accessibilityIdentifier("lyrics-offset-earlier")
                        Spacer()
                        Button("0.1秒遅らせる") { library.setLyricsOffset(offset + 0.1) }.accessibilityIdentifier("lyrics-offset-later")
                    }.buttonStyle(.bordered)
                    Button("補正をリセット") { library.setLyricsOffset(0) }
                }
                Section {
                    Text("繰り返して確認したいときは、歌詞を長押しして開始と終了を選べます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("歌詞のタイミング")
                .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
