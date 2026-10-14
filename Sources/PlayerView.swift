import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

struct PlayerView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @AppStorage("playerTheme") private var themeName = PlayerTheme.artwork.rawValue
    @AppStorage("lyricsPreview") private var lyricsPreview = true
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var detailsTrack: Track?
    @State private var showImporter = false
    @State private var importingArtwork = false
    @State private var importTarget: UUID?
    @State private var showPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    @ScaledMetric(relativeTo: .subheadline) private var previewHeight: CGFloat = 44

    private var theme: PlayerTheme { PlayerTheme(rawValue: themeName) ?? .artwork }
    private var palette: PlayerPalette { PlayerPalette(theme: theme, tint: library.artworkTint) }
    private var activeLine: String? { library.current?.lyrics?.last(where: { $0.seconds <= library.position })?.text }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 18) {
                header
                if let track = library.current {
                    if showLyrics {
                        LyricsView(palette: palette) { beginImport(artwork: false) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        artworkContent(track).frame(maxHeight: .infinity)
                    }
                    heading(track)
                    progress
                    transport
                    footer
                } else {
                    ContentUnavailableView("曲を選んでください", systemImage: "music.note")
                }
            }
            .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(palette.text)
        }
        .preferredColorScheme(theme == .paper ? .light : .dark)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showQueue) { queue }
        .sheet(item: $detailsTrack) { TrackDetailsView(track: $0).environmentObject(library) }
        .photosPicker(isPresented: $showPhotos, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item, let target = importTarget else { return }
            Task {
                photoLoading = true
                defer { photoLoading = false; selectedPhoto = nil }
                do {
                    if let data = try await item.loadTransferable(type: Data.self) { library.setArtwork(data, for: target) }
                    else { library.message = "画像を読み込めませんでした。" }
                } catch { library.message = "画像を読み込めませんでした：\(error.localizedDescription)" }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importingArtwork ? [.image] : [.data, .plainText]) { result in
            guard let target = importTarget else { return }
            let artwork = importingArtwork
            switch result {
            case .success(let url):
                Task {
                    if artwork {
                        do {
                            let data = try await Task.detached {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                return try Data(contentsOf: url)
                            }.value
                            library.setArtwork(data, for: target)
                        } catch { library.message = error.localizedDescription }
                    } else { await library.importLyrics(url, for: target) }
                }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .alert("お知らせ", isPresented: Binding(
            get: { library.message != nil && detailsTrack == nil && !showQueue },
            set: { if !$0 { library.message = nil } }
        )) { Button("OK") { library.message = nil } } message: { Text(library.message ?? "") }
        .onChange(of: library.current?.id) { _, _ in scrubbing = false }
    }

    private func artworkContent(_ track: Track) -> some View {
        GeometryReader { available in
            let line = lyricsPreview ? activeLine : nil
            let hasLine = line?.isEmpty == false
            let reservedHeight = hasLine ? previewHeight + 36 : 16
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                CoverView(image: library.artworkImage)
                    .frame(width: min(available.size.width - 16, max(40, available.size.height - reservedHeight)))
                    .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
                    .accessibilityLabel("\(track.title)のジャケット")
                    .accessibilityIdentifier("player-cover")
                if hasLine, let line {
                    Text(line).font(.subheadline).multilineTextAlignment(.center)
                        .foregroundStyle(palette.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity).frame(height: previewHeight)
                        .accessibilityIdentifier("lyrics-preview")
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            Button("閉じる", systemImage: "chevron.down") { dismiss() }
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
            Spacer()
            VStack(spacing: 3) {
                Text(showLyrics ? "歌詞" : "再生中").font(.caption.weight(.semibold))
                if let album = library.current?.album, !album.isEmpty {
                    Text(album).font(.caption2).foregroundStyle(palette.secondary).lineLimit(1)
                }
            }
            Spacer()
            if photoLoading { ProgressView().tint(palette.text).frame(width: 44) }
            else {
                Menu {
                    Button("写真からジャケットを選ぶ", systemImage: "photo") {
                        importTarget = library.current?.id; showPhotos = true
                    }
                    Button("画像ファイルからジャケットを選ぶ", systemImage: "folder") { beginImport(artwork: true) }
                    if library.current?.artworkFilename != nil {
                        Button("ジャケットを外す", systemImage: "photo.badge.minus", role: .destructive) {
                            if let id = library.current?.id { library.removeArtwork(for: id) }
                        }
                    }
                    Button("曲の情報を編集", systemImage: "pencil") { detailsTrack = library.current }
                    Button("LRCを読み込む", systemImage: "doc.badge.plus") { beginImport(artwork: false) }
                    Divider()
                    Picker("画面の色", selection: $themeName) {
                        ForEach(PlayerTheme.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    Toggle("ジャケット下に歌詞を表示", isOn: $lyricsPreview)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("曲と表示の設定")
                    .accessibilityIdentifier("player-options")
            }
        }
    }

    private func heading(_ track: Track) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("player-track-title")
                if let artist = track.artist, !artist.isEmpty {
                    Text(artist).font(.subheadline).foregroundStyle(palette.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(track.isFavorite ? "お気に入りを解除" : "お気に入りに追加",
                   systemImage: track.isFavorite ? "heart.fill" : "heart") { library.toggleFavorite(track) }
                .labelStyle(.iconOnly).font(.title2).frame(width: 44, height: 44)
                .foregroundStyle(track.isFavorite ? palette.accent : palette.text)
                .accessibilityIdentifier("favorite-toggle")
        }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { scrubbing ? scrubPosition : library.position }, set: { scrubPosition = $0 }),
                   in: 0...max(library.duration, 0.01), onEditingChanged: { editing in
                if editing { scrubPosition = library.position; scrubbing = true }
                else { scrubbing = false; library.seek(scrubPosition) }
            }).tint(palette.accent).accessibilityLabel("再生位置")
            HStack {
                Text(time(scrubbing ? scrubPosition : library.position))
                Spacer()
                Text("−" + time(max(0, library.duration - (scrubbing ? scrubPosition : library.position))))
            }.font(.caption.monospacedDigit()).foregroundStyle(palette.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Button("前の曲", systemImage: "backward.end.fill") { library.previous() }
                .font(.system(size: 26)).frame(width: 52, height: 52)
            Button(library.playing ? "一時停止" : "再生", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }
                .font(.system(size: 42)).frame(width: 64, height: 64)
                .accessibilityIdentifier("player-play-pause")
            Button("次の曲", systemImage: "forward.end.fill") { library.next() }
                .font(.system(size: 26)).frame(width: 52, height: 52)
                .disabled(library.current?.id == library.tracks.last?.id)
        }.labelStyle(.iconOnly).padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showLyrics.toggle() } } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble").font(.title2)
                    .frame(width: 52, height: 44)
                    .background(showLyrics ? palette.text.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel(showLyrics ? "ジャケットを表示" : "歌詞を表示")
                .accessibilityIdentifier("lyrics-toggle")
                .accessibilityValue(showLyrics ? "歌詞表示中" : "ジャケット表示中")
            Spacer()
            AirPlayButton(tint: UIColor(palette.text)).frame(width: 44, height: 44).accessibilityLabel("再生先を選択")
            Spacer()
            Button("曲一覧", systemImage: "list.bullet") { showQueue = true }
                .labelStyle(.iconOnly).font(.title2).frame(width: 52, height: 44)
        }
    }

    private var queue: some View {
        NavigationStack {
            List(library.tracks) { track in
                Button { library.select(track); showQueue = false } label: {
                    HStack(spacing: 12) {
                        CoverView(image: library.artwork(for: track), cornerRadius: 8).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).foregroundStyle(.primary)
                            if let artist = track.artist, !artist.isEmpty { Text(artist).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if library.current?.id == track.id { Image(systemName: "waveform") }
                    }
                }
            }.navigationTitle("曲一覧").toolbar { Button("閉じる") { showQueue = false } }
        }.tint(.indigo)
    }

    private func beginImport(artwork: Bool) {
        importTarget = library.current?.id; importingArtwork = artwork; showImporter = true
    }
    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct TrackDetailsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("曲の情報") {
                    TextField("曲名", text: $title)
                    TextField("アーティスト", text: $artist)
                    TextField("アルバム", text: $album)
                }
            }.navigationTitle("曲の情報")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            library.updateDetails(for: track.id, title: title, artist: artist, album: album)
                            if library.message == nil { dismiss() }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { title = track.title; artist = track.artist ?? ""; album = track.album ?? "" }
                .alert("保存できませんでした", isPresented: Binding(
                    get: { library.message != nil }, set: { if !$0 { library.message = nil } }
                )) { Button("OK") { library.message = nil } } message: { Text(library.message ?? "") }
        }
    }
}

struct AirPlayButton: UIViewRepresentable {
    let tint: UIColor
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.prioritizesVideoDevices = false; return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint; view.activeTintColor = tint
    }
}
