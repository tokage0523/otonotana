import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var showImporter = false
    @State private var showPlayer = false
    @State private var search = ""
    @State private var favoritesOnly = false

    private var visibleTracks: [Track] {
        library.tracks.filter {
            (!favoritesOnly || $0.isFavorite) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("あなたの音楽を、あなたのペースで。").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button { favoritesOnly.toggle() } label: {
                            Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                        }.accessibilityLabel(favoritesOnly ? "すべての曲を表示" : "お気に入りだけ表示")
                            .buttonStyle(.borderless)
                    }
                }
                if library.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("音楽を持ち歩こう", systemImage: "music.note.list")
                    } description: {
                        Text("「＋」からm4aの曲を追加。\n歌詞やジャケットも、好きなものを。")
                    } actions: {
                        Button("音楽ファイルを追加") { showImporter = true }
                            .buttonStyle(.borderedProminent).disabled(library.importing)
                    }
                } else if visibleTracks.isEmpty {
                    ContentUnavailableView("曲が見つかりません", systemImage: "magnifyingglass",
                        description: Text("検索やお気に入りの絞り込みを変えてみてください。"))
                } else {
                    Section("\(favoritesOnly ? "お気に入り" : "ライブラリ") · \(visibleTracks.count)曲") {
                        ForEach(visibleTracks) { track in
                            Button {
                                if library.current?.id != track.id { library.select(track) }
                                showPlayer = true
                            } label: {
                                HStack(spacing: 14) {
                                    CoverView(image: library.artwork(for: track), cornerRadius: 9).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(track.title).foregroundStyle(.primary).lineLimit(2)
                                        Text(track.artist?.isEmpty == false ? (track.artist ?? "") : track.filename.split(separator: ".").last?.uppercased() ?? "AUDIO")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if track.isFavorite { Image(systemName: "heart.fill").font(.caption) }
                                    if library.current?.id == track.id { Image(systemName: "waveform").font(.caption) }
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("track-\(track.id.uuidString)").swipeActions {
                                Button("削除", role: .destructive) { library.remove(track) }
                            }.swipeActions(edge: .leading) {
                                Button { library.toggleFavorite(track) } label: {
                                    Label("お気に入り", systemImage: track.isFavorite ? "heart.slash" : "heart")
                                }.tint(.pink)
                            }
                        }
                    }
                }
            }
            .navigationTitle("音の棚")
            .searchable(text: $search, prompt: "曲やアーティストを探す")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if library.importing { ProgressView().accessibilityLabel("音楽を取り込み中") }
                    else { Button("曲を追加", systemImage: "plus") { showImporter = true } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let track = library.current {
                    HStack(spacing: 12) {
                        Button { showPlayer = true } label: {
                            HStack(spacing: 12) {
                                CoverView(image: library.artworkImage, cornerRadius: 8).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.subheadline.bold()).lineLimit(1)
                                    Text(track.artist?.isEmpty == false ? (track.artist ?? "") : "再生中")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("再生画面を開く")
                        Button(library.playing ? "一時停止" : "再生", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }
                            .font(.title3).frame(width: 44, height: 44)
                        Button("次の曲", systemImage: "forward.end.fill") { library.next() }
                            .frame(width: 44, height: 44).disabled(track.id == library.tracks.last?.id)
                    }.labelStyle(.iconOnly).padding(12).background(.regularMaterial)
                }
            }
            .sheet(isPresented: $showPlayer) { PlayerView().environmentObject(library) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await library.importFiles(urls) }
                case .failure(let error): library.message = error.localizedDescription
                }
            }
            .alert("お知らせ", isPresented: Binding(
                get: { library.message != nil && !showPlayer }, set: { if !$0 { library.message = nil } }
            )) { Button("OK") { library.message = nil } } message: { Text(library.message ?? "") }
        }.tint(.indigo)
    }
}
