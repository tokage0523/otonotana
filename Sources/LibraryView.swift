import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var showImporter = false
    @State private var search = ""
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false

    private var visibleTracks: [Track] {
        library.tracks.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("ファイルをそのまま、あなたの音楽を。", systemImage: "waveform")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if library.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("音楽を持ち歩こう", systemImage: "music.note.list")
                    } description: {
                        Text("「＋」からm4aの曲を追加。\nAAC・Apple Losslessに対応しています。")
                    } actions: {
                        Button("音楽ファイルを追加") { showImporter = true }
                            .buttonStyle(.borderedProminent).disabled(library.importing)
                    }
                } else if visibleTracks.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    Section("ライブラリ · \(library.tracks.count)曲") {
                        ForEach(visibleTracks) { track in
                            Button { library.select(track) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: library.current?.id == track.id ? "waveform" : "music.note")
                                        .frame(width: 42, height: 42)
                                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(track.title).foregroundStyle(.primary).lineLimit(2)
                                        Text(track.filename.split(separator: ".").last?.uppercased() ?? "AUDIO")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill").font(.caption)
                                }.padding(.vertical, 4)
                            }
                            .swipeActions {
                                Button("削除", role: .destructive) { library.remove(track) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("音の棚")
            .searchable(text: $search, prompt: "曲を探す")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if library.importing { ProgressView().accessibilityLabel("音楽を取り込み中") }
                    else {
                        Button("曲を追加", systemImage: "plus") { showImporter = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let track = library.current {
                    VStack(spacing: 12) {
                        Text(track.title).font(.headline).lineLimit(1)
                        NavigationLink {
                            LyricsView()
                        } label: {
                            Label("歌詞を表示・タップして再生", systemImage: "text.alignleft")
                        }.font(.subheadline)
                        Slider(value: Binding(
                            get: { scrubbing ? scrubPosition : library.position },
                            set: { scrubPosition = $0 }
                        ), in: 0...max(library.duration, 0.01), onEditingChanged: { editing in
                            if editing { scrubPosition = library.position; scrubbing = true }
                            else { scrubbing = false; library.seek(scrubPosition) }
                        }).accessibilityLabel("再生位置")
                        HStack {
                            Text(time(scrubbing ? scrubPosition : library.position))
                            Spacer()
                            Text(time(library.duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 40) {
                            Button("前の曲", systemImage: "backward.end.fill") { library.previous() }
                            Button(library.playing ? "一時停止" : "再生",
                                   systemImage: library.playing ? "pause.circle.fill" : "play.circle.fill") {
                                library.toggle()
                            }.font(.system(size: 52))
                            Button("次の曲", systemImage: "forward.end.fill") { library.next() }
                                .disabled(library.current == library.tracks.last)
                        }.labelStyle(.iconOnly).font(.title2)
                    }
                    .padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await library.importFiles(urls) }
                case .failure(let error): library.message = error.localizedDescription
                }
            }
            .alert("お知らせ", isPresented: Binding(
                get: { library.message != nil },
                set: { if !$0 { library.message = nil } }
            )) {
                Button("OK") { library.message = nil }
            } message: { Text(library.message ?? "") }
        }.tint(.indigo)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
