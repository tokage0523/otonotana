import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @AppStorage("lyricsAutoScroll") private var autoScroll = true
    @AppStorage("lyricsTimestamps") private var timestamps = false
    @AppStorage("lyricsSize") private var size = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var standardSize: CGFloat = 24
    let palette: PlayerPalette
    let importLyrics: () -> Void

    private var activeID: UUID? { library.current?.lyrics?.last { $0.seconds <= library.position }?.id }
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
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background(size == index ? palette.text.opacity(0.18) : .clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("lyrics-size-\(index)")
                            .accessibilityLabel("歌詞の文字サイズ \(["小", "標準", "大"][index])")
                            .accessibilityAddTraits(size == index ? .isSelected : [])
                    }
                }.background(palette.text.opacity(0.07), in: Capsule())
                Button("LRCを読み込む", systemImage: "doc.badge.plus", action: importLyrics).labelStyle(.iconOnly).frame(width: 44, height: 44)
            }.foregroundStyle(palette.text)
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
                                            Text(timestamp(line.seconds)).font(.caption.monospacedDigit()).foregroundStyle(palette.secondary)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 6)
                                }.buttonStyle(.plain).id(line.id).accessibilityIdentifier("lyric-\(line.seconds)")
                                    .accessibilityHint("この歌詞の時刻から再生")
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
        }
    }
    private func scroll(_ proxy: ScrollViewProxy, to id: UUID) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { proxy.scrollTo(id, anchor: .center) }
    }
    private func timestamp(_ seconds: Double) -> String {
        let value = Int(seconds); return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
