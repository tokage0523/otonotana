import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @AppStorage("lyricsAutoScroll") private var autoScroll = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: PlayerPalette
    let importLyrics: () -> Void

    private var activeID: UUID? {
        library.current?.lyrics?.last(where: { $0.seconds <= library.position })?.id
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { autoScroll.toggle() } label: {
                    Label(autoScroll ? "自動スクロール ON" : "自動スクロール OFF",
                          systemImage: autoScroll ? "arrow.up.and.down.circle.fill" : "hand.draw")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 10)
                        .background(palette.text.opacity(autoScroll ? 0.15 : 0.07), in: Capsule())
                }.accessibilityLabel("歌詞の自動スクロール")
                .accessibilityIdentifier("lyrics-follow-toggle")
                    .accessibilityValue(autoScroll ? "オン" : "オフ")
                    .accessibilityHint("オフにすると好きな位置を読めます")
                Spacer()
                Button("LRCを読み込む", systemImage: "doc.badge.plus", action: importLyrics)
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
            }.foregroundStyle(palette.text)
            if let lines = library.current?.lyrics, !lines.isEmpty, let trackID = library.current?.id {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(lines) { line in
                                Button { library.playLyric(line, trackID: trackID) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(line.text.isEmpty ? "• • •" : line.text)
                                            .font(.system(.title2, design: .rounded, weight: .bold))
                                            .foregroundStyle(line.id == activeID ? palette.text : palette.secondary)
                                        Text(timestamp(line.seconds)).font(.caption.monospacedDigit())
                                            .foregroundStyle(palette.secondary.opacity(0.7))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16).padding(.vertical, 12)
                                        .background(line.id == activeID ? palette.text.opacity(0.1) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain).id(line.id).accessibilityIdentifier("lyric-\(line.seconds)")
                                    .accessibilityHint("この歌詞の時刻から再生")
                            }
                        }.padding(.vertical, 70)
                    }.scrollIndicators(.hidden)
                        .onChange(of: activeID) { _, id in
                            guard autoScroll, let id else { return }
                            scroll(proxy, to: id)
                        }
                        .onChange(of: autoScroll) { _, enabled in
                            guard enabled, let id = activeID else { return }
                            scroll(proxy, to: id)
                        }
                        .onAppear {
                            if autoScroll, let id = activeID { proxy.scrollTo(id, anchor: .center) }
                        }
                }
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
        if reduceMotion { proxy.scrollTo(id, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) } }
    }

    private func timestamp(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
