import SwiftUI

/// Inspect the one file used by playback; do not scan folders or copy audio.
struct TrackFileInfoView: View {
    @EnvironmentObject private var library: MusicLibrary
    let track: Track
    @State private var size: Int?
    @State private var exists = false
    private var location: String {
        if let path = SharedFiles.relativePath(for: library.audioURL(for: track), under: library.sharedDirectory) {
            return "音の棚 / " + path
        }
        return "音の棚（アプリ内） / " + track.filename
    }
    var body: some View {
        Section("ファイルと容量") {
            LabeledContent("ファイル名") {
                Text(track.filename).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
            LabeledContent("ファイル形式", value: library.audioURL(for: track).pathExtension.uppercased().nonEmpty ?? "不明")
            LabeledContent("音楽ファイルの容量", value: size.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "確認できません")
                .accessibilityIdentifier("track-file-size")
            VStack(alignment: .leading, spacing: 5) {
                Text("保存場所").font(.caption).foregroundStyle(.secondary)
                Text(location).font(.subheadline).textSelection(.enabled)
                    .accessibilityIdentifier("track-file-location")
            }.padding(.vertical, 3)
            if !exists {
                Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("設定の「音楽の保存場所」から指定し直せます。").font(.footnote).foregroundStyle(.secondary)
            }
            Text("再生には、この場所の音楽ファイルを直接使います。再生用の追加コピーは作りません。容量は音楽ファイル1つ分で、歌詞やジャケットは含みません。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("曲情報の編集内容は音の棚に保存されます。").font(.footnote).foregroundStyle(.secondary)
        }.onAppear {
            let url = library.audioURL(for: track)
            exists = FileManager.default.fileExists(atPath: url.path)
            size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        }
    }
}
