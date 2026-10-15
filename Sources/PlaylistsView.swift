import SwiftUI
import PhotosUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TrackCollectionView(source: .favorites) } label: { Label("お気に入り", systemImage: "heart.fill") }
                    NavigationLink { TrackCollectionView(source: .recent) } label: { Label("最近追加した曲", systemImage: "clock") }
                }
                Section("自分のプレイリスト") {
                    if library.playlists.isEmpty { Text("「＋」から好きな曲をまとめられます。").foregroundStyle(.secondary) }
                    ForEach(library.playlists) { playlist in
                        NavigationLink { TrackCollectionView(source: .playlist(playlist.id)) } label: {
                            HStack(spacing: 14) {
                                CoverView(image: playlist.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }.first.flatMap { library.artwork(for: $0) }, cornerRadius: 10)
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(playlist.title).font(.headline)
                                    Text("\(playlist.trackIDs.count)曲").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("削除", role: .destructive) { library.removePlaylist(playlist) } }
                    }
                }
            }.navigationTitle("プレイリスト")
                .toolbar { Button("プレイリストを作成", systemImage: "plus") { adding = true }.accessibilityIdentifier("add-playlist") }
                .sheet(isPresented: $adding) { CollectionEditor(kind: .playlist).environmentObject(library) }
        }
    }
}

enum CollectionSource {
    case favorites, recent, playlist(UUID)
}

struct TrackCollectionView: View {
    @EnvironmentObject private var library: MusicLibrary
    let source: CollectionSource
    @State private var editing = false
    private var playlist: Playlist? {
        if case .playlist(let id) = source { return library.playlists.first { $0.id == id } }
        return nil
    }
    private var title: String {
        switch source { case .favorites: return "お気に入り"; case .recent: return "最近追加した曲"; case .playlist: return playlist?.title ?? "プレイリスト" }
    }
    private var tracks: [Track] {
        switch source {
        case .favorites: return library.tracks.filter(\.isFavorite)
        case .recent: return library.tracks.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .playlist: return (playlist?.trackIDs ?? []).compactMap { id in library.tracks.first { $0.id == id } }
        }
    }
    var body: some View {
        List {
            if tracks.isEmpty { Text("曲がありません").foregroundStyle(.secondary) }
            else {
                Section {
                    HStack(spacing: 12) {
                        Button("再生", systemImage: "play.fill") { start(shuffled: false) }.frame(maxWidth: .infinity)
                        Button("シャッフル", systemImage: "shuffle") { start(shuffled: true) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                Section("\(tracks.count)曲") {
                    ForEach(tracks) { TrackRow(track: $0, context: tracks, playlistID: playlist?.id, removeFavoriteOnly: isFavorites) }
                }
            }
        }.navigationTitle(title)
            .toolbar { if playlist != nil { Button("編集") { editing = true } } }
            .sheet(isPresented: $editing) {
                if let playlist { CollectionEditor(kind: .playlist, id: playlist.id, initialTitle: playlist.title, initialIDs: playlist.trackIDs).environmentObject(library) }
            }
    }
    private func start(shuffled: Bool) {
        if library.shuffleEnabled != shuffled { library.toggleShuffle() }
        if let first = shuffled ? tracks.randomElement() : tracks.first {
            library.select(first, context: tracks); library.resume(); library.playerPresented = true
        }
    }
    private var isFavorites: Bool { if case .favorites = source { return true }; return false }
}

enum CollectionKind { case album, playlist }

struct CollectionEditor: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    private func collectionTrackLabel(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title).lineLimit(2)
            Text("\(track.artist?.nonEmpty ?? "アーティスト未設定") · \(track.album?.nonEmpty ?? "アルバム未設定")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    let kind: CollectionKind
    let id: UUID?
    @State private var title: String
    @State private var artist: String
    @State private var ids: [UUID]
    @State private var photo: PhotosPickerItem?
    @State private var artwork: Data?
    @State private var loading = false

    init(kind: CollectionKind, id: UUID? = nil, initialTitle: String = "", initialArtist: String = "", initialIDs: [UUID] = []) {
        self.kind = kind; self.id = id
        _title = State(initialValue: initialTitle); _artist = State(initialValue: initialArtist); _ids = State(initialValue: initialIDs)
    }
    private var selected: [Track] { ids.compactMap { id in library.tracks.first { $0.id == id } } }
    private var available: [Track] { library.tracks.filter { !ids.contains($0.id) } }
    var body: some View {
        NavigationStack {
            List {
                Section("情報") {
                    TextField(kind == .album ? "アルバム名" : "プレイリスト名", text: $title).accessibilityIdentifier("collection-title")
                    if kind == .album {
                        TextField("アルバムアーティスト", text: $artist)
                        PhotosPicker(selection: $photo, matching: .images) {
                            HStack { Label(artwork == nil ? "共通ジャケットを選ぶ" : "共通ジャケットを変更", systemImage: "photo"); if loading { ProgressView() } }
                        }
                    }
                }
                Section("曲順 · 右側のつまみで並べ替え") {
                    ForEach(selected) { track in
                        HStack {
                            Button("外す", systemImage: "minus.circle.fill") { ids.removeAll { $0 == track.id } }.labelStyle(.iconOnly).tint(.red)
                            collectionTrackLabel(track)
                        }
                    }.onMove { from, to in ids.move(fromOffsets: from, toOffset: to) }
                }
                Section("曲を追加") {
                    ForEach(available) { track in
                        Button { ids.append(track.id) } label: { HStack { Image(systemName: "plus.circle"); collectionTrackLabel(track) } }
                            .accessibilityIdentifier("collection-add-\(track.id.uuidString)")
                    }.moveDisabled(true)
                }
                if let message = library.message { Section { Text(message).foregroundStyle(.red) } }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle(kind == .album ? "アルバムの編集" : "プレイリストの編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            library.message = nil
                            if kind == .album { library.saveAlbum(id: id, title: title, artist: artist, trackIDs: ids, artwork: artwork) }
                            else { library.savePlaylist(id: id, title: title, trackIDs: ids) }
                            if library.message == nil { dismiss() }
                        }.disabled(title.nonEmpty == nil || loading || (kind == .album && ids.isEmpty)).accessibilityIdentifier("collection-save")
                    }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    Task {
                        loading = true; defer { loading = false }
                        do { artwork = try await item.loadTransferable(type: Data.self) }
                        catch { library.message = "画像を読み込めませんでした。" }
                    }
                }
        }
    }
}
