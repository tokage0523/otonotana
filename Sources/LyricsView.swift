import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var library: MusicLibrary
    let clock: PlaybackClock
    @AppStorage("lyricsAutoScroll") private var autoScroll = true
    @AppStorage("lyricsTimestamps") private var timestamps = false
    @AppStorage("lyricsSize") private var size = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var standardSize: CGFloat = 24
    let palette: PlayerPalette
    let importLyrics: () -> Void

    @State private var activeID: UUID?
    @State private var showTiming = false
    @State private var deletionTarget: Track?
    @State private var exportURL: URL?
    @State private var showExport = false
    private var fontSize: CGFloat { standardSize * (size == 0 ? 0.83 : size == 2 ? 1.21 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { autoScroll.toggle() } label: {
                    Label(autoScroll ? "自動 ON" : "自動 OFF", systemImage: autoScroll ? "arrow.up.and.down" : "hand.draw")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 44)
                        .background(palette.text.opacity(autoScroll ? 0.15 : 0.07), in: Capsule())
                }.accessibilityLabel("歌詞の自動スクロール").accessibilityIdentifier("lyrics-follow-toggle")
                    .accessibilityValue(autoScroll ? "オン" : "オフ")
                HStack(spacing: 0) {
                    ForEach(0..<3) { index in
                        Button { size = index } label: {
                            Text(["小", "標準", "大"][index]).font(.caption.weight(.semibold))
                                .frame(minWidth: 0, maxWidth: .infinity).frame(minHeight: 44)
                                .background(size == index ? palette.text.opacity(0.18) : .clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("lyrics-size-\(index)")
                            .accessibilityLabel("歌詞の文字サイズ \(["小", "標準", "大"][index])")
                            .accessibilityAddTraits(size == index ? .isSelected : [])
                    }
                }.background(palette.text.opacity(0.07), in: Capsule())
                Menu {
                    Button("歌詞のタイミングを調整", systemImage: "slider.horizontal.3") { showTiming = true }
                        .disabled(library.current?.hasLyrics != true)
                    Button(library.current?.hasLyrics == true ? "LRCを読み込んで差し替え" : "LRCを読み込む",
                           systemImage: "doc.badge.plus", action: importLyrics)
                    if library.current?.hasLyrics == true {
                        Button("LRCを書き出す", systemImage: "square.and.arrow.up") { exportLyrics() }
                            .accessibilityIdentifier("lyrics-export")
                        Button("歌詞を削除", systemImage: "trash", role: .destructive) { deletionTarget = library.current }
                            .accessibilityIdentifier("lyrics-delete")
                    }
                    if library.lyricLoop != nil { Button("範囲リピートを解除") { library.clearLyricLoop() } }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("歌詞の設定").accessibilityIdentifier("lyrics-options")
            }.foregroundStyle(palette.text)
            if let range = library.lyricLoop {
                HStack {
                    Label(range.end == nil ? "開始を設定済み · 終了の歌詞を長押し" : "歌詞の範囲をリピート中", systemImage: "repeat")
                        .font(.caption)
                    Spacer()
                    Button("解除") { library.clearLyricLoop() }.font(.caption.bold())
                }.foregroundStyle(palette.text).padding(.horizontal, 6).accessibilityIdentifier("lyrics-loop-status")
            }
            if let lines = library.current?.lyrics, !lines.isEmpty, let trackID = library.current?.id {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(lines) { line in
                                Button { library.playLyric(line, trackID: trackID) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(line.text.nonEmpty ?? "• • •").font(.system(size: fontSize, weight: .bold))
                                            .foregroundStyle(palette.text.opacity(line.id == activeID ? 1 : 0.58))
                                        if timestamps {
                                            Text(timestamp(library.current?.lyricTime(line) ?? line.seconds)).font(.caption.monospacedDigit()).foregroundStyle(palette.secondary)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 6)
                                }.buttonStyle(.plain).id(line.id).accessibilityIdentifier("lyric-\(line.seconds)")
                                    .accessibilityHint("この歌詞の時刻から再生")
                                    .contextMenu {
                                        Button("ここから繰り返す", systemImage: "a.circle") { library.setLoopStart(line) }
                                        Button("ここまで繰り返す", systemImage: "b.circle") { library.setLoopEnd(line) }.disabled(library.lyricLoop == nil)
                                    }
                            }
                        }.padding(.vertical, 30)
                    }.scrollIndicators(.hidden)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.08),
                                                    .init(color: .white, location: 0.88), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        .onChange(of: activeID) { _, id in if autoScroll, let id { scroll(proxy, to: id) } }
                        .onChange(of: autoScroll) { _, enabled in if enabled, let id = activeID { scroll(proxy, to: id) } }
                        .onChange(of: size) { _, _ in if autoScroll, let id = activeID { scroll(proxy, to: id) } }
                        .onAppear { if autoScroll, let id = activeID { proxy.scrollTo(id, anchor: .center) } }
                }.id(trackID)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble").font(.system(size: 44))
                    Text("この曲に歌詞を添えよう").font(.headline)
                    Text("PCで作ったLRCを読み込むと、\n歌詞をタップしてその位置から再生できます。")
                        .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(palette.secondary)
                    Button("LRCを読み込む", action: importLyrics).buttonStyle(.bordered).tint(palette.text)
                }.foregroundStyle(palette.text).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onReceive(clock.$position) { position in
            let next = library.current?.lyrics?.last { (library.current?.lyricTime($0) ?? $0.seconds) <= position }?.id
            if next != activeID { activeID = next }
        }
        .onChange(of: library.current?.lyricsOffset) { _, _ in
            activeID = library.current?.lyrics?.last { (library.current?.lyricTime($0) ?? $0.seconds) <= clock.position }?.id
        }
        .onChange(of: library.current?.lyrics) { _, _ in
            activeID = library.current?.lyrics?.last { (library.current?.lyricTime($0) ?? $0.seconds) <= clock.position }?.id
        }
        .sheet(isPresented: $showTiming) { LyricsTimingView().environmentObject(library) }
        .confirmationDialog("「\(deletionTarget?.title ?? "")」の歌詞を削除しますか？",
                            isPresented: Binding(get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }),
                            titleVisibility: .visible, presenting: deletionTarget) { track in
            Button("歌詞を削除", role: .destructive) { library.removeLyrics(for: track.id); deletionTarget = nil }
                .accessibilityIdentifier("lyrics-delete-confirm")
            Button("キャンセル", role: .cancel) { deletionTarget = nil }
        } message: { _ in
            Text("曲と音楽ファイルは残ります。元のLRCファイルも削除しません。歌詞を戻すにはLRCを読み込み直してください。")
        }
        .sheet(isPresented: $showExport, onDismiss: cleanExport) {
            if let exportURL { FolderExporter(url: exportURL, initialDirectory: library.sharedDirectory) { showExport = false } }
        }
        .onDisappear { if !showExport { cleanExport() } }
    }
    private func exportLyrics() {
        guard let track = library.current, let lines = track.lyrics, !lines.isEmpty else { return }
        cleanExport()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lyrics-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = String(track.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|\n\r"))
                .joined(separator: "_").prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = folder.appendingPathComponent(name.isEmpty ? "歌詞" : name).appendingPathExtension("lrc")
            try Lyrics.export(lines, offset: track.lyricsOffset ?? 0).write(to: url, atomically: true, encoding: .utf8)
            exportURL = url; showExport = true
        } catch {
            try? FileManager.default.removeItem(at: folder)
            library.message = "歌詞を書き出せませんでした：\(error.localizedDescription)"
        }
    }
    private func cleanExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
        exportURL = nil
    }
    private func scroll(_ proxy: ScrollViewProxy, to id: UUID) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { proxy.scrollTo(id, anchor: .center) }
    }
    private func timestamp(_ seconds: Double) -> String {
        let value = Int(seconds); return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
