import SwiftUI

struct TimedLyricsPreview: View {
    @EnvironmentObject private var library: MusicLibrary
    @ObservedObject var clock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: PlayerPalette
    private var activeID: UUID? { library.current?.lyrics?.last { (library.current?.lyricTime($0) ?? $0.seconds) <= clock.position }?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(library.current?.lyrics ?? []) { line in
                        Button {
                            if let id = library.current?.id { library.playLyric(line, trackID: id) }
                        } label: {
                            Text(line.text.nonEmpty ?? "• • •").font(.subheadline.weight(line.id == activeID ? .semibold : .regular))
                                .foregroundStyle(palette.text.opacity(line.id == activeID ? 1 : 0.45))
                                .lineLimit(1).frame(maxWidth: .infinity).frame(height: 24)
                        }.buttonStyle(.plain).id(line.id)
                    }
                }.padding(.vertical, 24)
            }.scrollDisabled(true).scrollIndicators(.hidden).frame(height: 72)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.22),
                                            .init(color: .white, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onChange(of: activeID) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear { if let id = activeID { proxy.scrollTo(id, anchor: .center) } }
        }.id(library.current?.id).accessibilityIdentifier("lyrics-preview")
    }
}
