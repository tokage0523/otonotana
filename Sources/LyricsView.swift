import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var showImporter = false
    @State private var importTarget: UUID?

    private var activeID: UUID? {
        library.current?.lyrics?.last(where: { $0.seconds <= library.position })?.id
    }

    var body: some View {
        Group {
            if let track = library.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text(track.title).font(.title2.bold()).padding(.horizontal)
                    Text("歌詞をタップすると、その位置から再生します。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    if let lines = track.lyrics, !lines.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(lines) { line in
                                        Button { library.playLyric(line, trackID: track.id) } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                                Text(timestamp(line.seconds)).font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary).frame(width: 60)
                                                Text(line.text.isEmpty ? "（間奏）" : line.text)
                                                    .font(.title3.weight(line.id == activeID ? .bold : .regular))
                                                    .foregroundStyle(line.id == activeID ? Color.indigo : Color.primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(14)
                                            .background(line.id == activeID ? Color.indigo.opacity(0.1) : Color.clear,
                                                        in: RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(.plain).id(line.id)
                                    }
                                }.padding(.horizontal)
                            }
                            .onChange(of: activeID) { _, value in
                                if let value { withAnimation { proxy.scrollTo(value, anchor: .center) } }
                            }
                        }
                    } else {
                        ContentUnavailableView("歌詞を追加しよう", systemImage: "text.alignleft",
                            description: Text("PCで保存したLRCファイルを\nこの曲に読み込んでください。"))
                    }
                }
            } else {
                ContentUnavailableView("曲を選んでください", systemImage: "music.note")
            }
        }
        .navigationTitle("歌詞")
        .toolbar {
            Button("LRCを読み込む") {
                importTarget = library.current?.id
                showImporter = true
            }.disabled(library.current == nil)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .plainText]) { result in
            switch result {
            case .success(let url):
                if let target = importTarget { Task { await library.importLyrics(url, for: target) } }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
