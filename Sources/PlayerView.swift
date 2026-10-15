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

    private var theme: PlayerTheme { PlayerTheme(rawValue: themeName) ?? .artwork }
    private var palette: PlayerPalette { PlayerPalette(theme: theme, tint: library.artworkTint) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                header
                if let track = library.current {
                    if showLyrics {
                        HStack(spacing: 12) {
                            CoverView(image: library.artworkImage, cornerRadius: 9).frame(width: 48, height: 48)
                            heading(track)
                        }
                        LyricsView(clock: library.clock, palette: palette) { beginImport(artwork: false) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        artworkContent(track).frame(maxHeight: .infinity)
                    }
                    if !showLyrics { heading(track) }
                    PlayerProgressView(library: library, clock: library.clock, palette: palette)
                    transport
                    footer
                } else {
                    ContentUnavailableView("曲を選んでください", systemImage: "music.note")
                }
            }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(palette.text)
        }
        .environment(\.colorScheme, theme == .paper ? .light : .dark)
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
    }

    private func artworkContent(_ track: Track) -> some View {
        GeometryReader { available in
            let hasLines = lyricsPreview && library.current?.lyrics?.isEmpty == false
            let reservedHeight: CGFloat = hasLines ? 96 : 16
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                CoverView(image: library.artworkImage)
                    .frame(width: min(available.size.width - 12, max(40, available.size.height - reservedHeight)))
                    .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
                    .accessibilityLabel("\(track.title)のジャケット")
                    .accessibilityIdentifier("player-cover")
                if hasLines { TimedLyricsPreview(clock: library.clock, palette: palette) }
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
                PlayerOptionsMenu(trackID: library.current?.id, hasArtwork: library.current?.artworkFilename != nil) { action in
                    switch action {
                    case .photo: importTarget = library.current?.id; showPhotos = true
                    case .imageFile: beginImport(artwork: true)
                    case .removeArtwork: if let id = library.current?.id { library.removeArtwork(for: id) }
                    case .details: detailsTrack = library.current
                    case .lyrics: beginImport(artwork: false)
                    }
                }.equatable()
            }
        }
    }

    private func heading(_ track: Track) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(showLyrics ? .headline : .title2.bold()).lineLimit(2).minimumScaleFactor(0.8)
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

    private var transport: some View {
        HStack(spacing: 0) {
            Button { library.toggleShuffle() } label: {
                Image(systemName: "shuffle").font(.system(size: 20))
                    .foregroundStyle(palette.text.opacity(library.shuffleEnabled ? 1 : 0.45))
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
            }.accessibilityLabel("シャッフル").accessibilityValue(library.shuffleEnabled ? "オン" : "オフ").accessibilityIdentifier("player-shuffle")
            Button { library.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 27)).frame(minWidth: 0, maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
            }.accessibilityLabel("前の曲")
            Button { library.toggle() } label: {
                Image(systemName: library.playing ? "pause.fill" : "play.fill").font(.system(size: 40))
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
            }.accessibilityLabel(library.playing ? "一時停止" : "再生").accessibilityIdentifier("player-play-pause")
            Button { library.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 27)).frame(minWidth: 0, maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
            }.accessibilityLabel("次の曲").disabled(!library.canGoNext)
            Button { library.cycleRepeat() } label: {
                Image(systemName: library.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 20))
                    .foregroundStyle(palette.text.opacity(library.repeatMode == .off ? 0.45 : 1))
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
            }.accessibilityLabel(library.repeatMode.label).accessibilityIdentifier("player-repeat")
        }.buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showLyrics.toggle() } } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble").font(.title2)
                    .frame(width: 48, height: 44)
                    .background(showLyrics ? palette.text.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minWidth: 0, maxWidth: .infinity).contentShape(Rectangle())
            }.accessibilityLabel(showLyrics ? "ジャケットを表示" : "歌詞を表示")
                .accessibilityIdentifier("lyrics-toggle").accessibilityValue(showLyrics ? "歌詞表示中" : "ジャケット表示中")
            AirPlayButton(tint: UIColor(palette.text)).frame(width: 44, height: 44).frame(minWidth: 0, maxWidth: .infinity).accessibilityLabel("再生先を選択")
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.title2).frame(width: 48, height: 44).frame(minWidth: 0, maxWidth: .infinity).contentShape(Rectangle())
            }.accessibilityLabel("再生する曲一覧")
        }.buttonStyle(.plain)
    }

    private var queue: some View {
        NavigationStack {
            List(library.queueTracks) { track in
                Button { library.select(track, context: library.queueTracks); showQueue = false } label: {
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

}

// This view deliberately does not observe MusicLibrary. Playback ticks must not
// recreate an open UIKit menu. Only changes to the selected track or artwork do.
private struct PlayerOptionsMenu: View, Equatable {
    enum Action { case photo, imageFile, removeArtwork, details, lyrics }
    let trackID: UUID?
    let hasArtwork: Bool
    let action: (Action) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.trackID == rhs.trackID && lhs.hasArtwork == rhs.hasArtwork }
    var body: some View {
        Menu {
            Button("写真からジャケットを選ぶ", systemImage: "photo") { action(.photo) }
            Button("画像ファイルからジャケットを選ぶ", systemImage: "folder") { action(.imageFile) }
            if hasArtwork { Button("ジャケットを外す", systemImage: "photo.badge.minus", role: .destructive) { action(.removeArtwork) } }
            Button("曲の情報を編集", systemImage: "pencil") { action(.details) }
            Button("LRCを読み込む", systemImage: "doc.badge.plus") { action(.lyrics) }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("曲と表示の設定").accessibilityIdentifier("player-options")
    }
}

struct TrackDetailsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: String?
    let track: Track
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var trackNumber = ""
    @State private var discNumber = ""
    @State private var genre = ""
    @State private var releaseYear = ""
    @State private var composer = ""
    @State private var notes = ""
    private var validNumbers: Bool {
        [trackNumber, discNumber, releaseYear].allSatisfy { $0.isEmpty || (Int($0).map { $0 > 0 } ?? false) }
            && (releaseYear.isEmpty || (Int(releaseYear).map { $0 <= 9999 } ?? false))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("曲の情報") {
                    informationField("曲名", text: $title)
                    informationField("アーティスト", text: $artist)
                    informationField("アルバム", text: $album)
                    informationField("アルバムアーティスト", text: $albumArtist)
                }
                Section("収録情報") {
                    informationField("収録順", text: $trackNumber, numeric: true)
                    informationField("ディスク番号", text: $discNumber, numeric: true)
                    informationField("ジャンル", text: $genre)
                    informationField("発売年", text: $releaseYear, numeric: true)
                    informationField("作曲者", text: $composer)
                    if !validNumbers { Text("収録順・ディスク番号は1以上、発売年は1〜9999で入力してください。").font(.footnote).foregroundStyle(.red) }
                }
                Section("メモ") {
                    TextField("自由に記入", text: $notes, axis: .vertical).lineLimit(3...6).accessibilityLabel("メモ")
                        .focused($focusedField, equals: "メモ")
                }
                Section("ファイル") {
                    LabeledContent("ファイル名") { Text(track.filename).textSelection(.enabled).multilineTextAlignment(.trailing) }
                    LabeledContent("ファイル形式", value: track.filename.split(separator: ".").last.map { String($0).uppercased() } ?? "不明")
                    if let size = (try? library.audioURL(for: track).resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        LabeledContent("サイズ", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    Text("編集内容は音の棚に保存されます。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("曲の情報").scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完了") { focusedField = nil }.accessibilityIdentifier("information-keyboard-done")
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            library.updateDetails(for: track.id, title: title, artist: artist, album: album,
                                                  albumArtist: albumArtist, trackNumber: Int(trackNumber), discNumber: Int(discNumber),
                                                  genre: genre, releaseYear: Int(releaseYear), composer: composer, notes: notes)
                            if library.message == nil { dismiss() }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validNumbers)
                    }
                }
                .onAppear {
                    title = track.title; artist = track.artist ?? ""; album = track.album ?? ""
                    albumArtist = track.albumArtist ?? ""; trackNumber = track.trackNumber.map(String.init) ?? ""
                    discNumber = track.discNumber.map(String.init) ?? ""; genre = track.genre ?? ""
                    releaseYear = track.releaseYear.map(String.init) ?? ""; composer = track.composer ?? ""; notes = track.notes ?? ""
                }
                .alert("保存できませんでした", isPresented: Binding(
                    get: { library.message != nil }, set: { if !$0 { library.message = nil } }
                )) { Button("OK") { library.message = nil } } message: { Text(library.message ?? "") }
        }
    }

    private func informationField(_ name: String, text: Binding<String>, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(name, text: text).keyboardType(numeric ? .numberPad : .default)
                .accessibilityLabel(name).focused($focusedField, equals: name)
                .submitLabel(.done).onSubmit { focusedField = nil }
        }.padding(.vertical, 3)
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


private struct PlayerProgressView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var clock: PlaybackClock
    let palette: PlayerPalette
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    var body: some View {
        VStack(spacing: 2) {
            SeekBar(value: Binding(get: { scrubbing ? scrubPosition : clock.position }, set: { scrubPosition = $0 }),
                    duration: library.duration, tint: palette.accent, onEditingChanged: { editing in
                if editing { scrubPosition = clock.position; scrubbing = true }
                else { scrubbing = false; library.seek(scrubPosition) }
            })
            HStack {
                Text(time(scrubbing ? scrubPosition : clock.position))
                Spacer()
                Text("−" + time(max(0, library.duration - (scrubbing ? scrubPosition : clock.position))))
            }.font(.caption.monospacedDigit()).foregroundStyle(palette.secondary)
        }.onChange(of: library.current?.id) { _, _ in scrubbing = false }
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
