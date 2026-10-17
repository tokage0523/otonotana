import SwiftUI
import UniformTypeIdentifiers

enum LibraryMode: Int, CaseIterable {
    case songs, albums, artists
    var title: String { self == .songs ? "曲" : self == .albums ? "アルバム" : "アーティスト" }
}

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: LibraryMode = .songs
    @State private var forward = true
    @State private var search = ""
    @State private var showImporter = false
    @State private var showAlbumEditor = false

    private var visibleTracks: [Track] {
        library.tracks.filter { track in
            search.isEmpty || [track.title, track.artist ?? "", track.album ?? "", track.albumArtist ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var visibleAlbums: [AlbumGroup] {
        library.albums.filter { album in search.isEmpty || album.title.localizedCaseInsensitiveContains(search)
            || album.artist.localizedCaseInsensitiveContains(search) || album.tracks.contains { visibleTracks.contains($0) } }
    }
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading), removal: .move(edge: forward ? .leading : .trailing))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("曲・アーティスト・アルバムを検索", text: $search).font(.subheadline)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("library-search")
                    if !search.isEmpty { Button("検索を消す", systemImage: "xmark.circle.fill") { search = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary) }
                }.padding(12).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 4) {
                    ForEach(LibraryMode.allCases, id: \.self) { item in
                        Button {
                            forward = item.rawValue > mode.rawValue
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { mode = item }
                        } label: {
                            Text(item.title).font(.subheadline.weight(.semibold)).frame(minWidth: 0, maxWidth: .infinity).padding(.vertical, 11)
                                .background(mode == item ? Color(.secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 11))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(mode == item ? Color.indigo : .secondary)
                            .accessibilityIdentifier("mode-\(item.title)").accessibilityAddTraits(mode == item ? .isSelected : [])
                    }
                }.padding(4).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                ZStack {
                    modeContent.id(mode).transition(transition)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
            }.padding(.horizontal, 20).padding(.top, 8).background(Color(.systemGroupedBackground))
                .navigationTitle("音の棚")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if library.importing { ProgressView() }
                        else {
                            Menu {
                                Button("音楽ファイルを追加", systemImage: "music.note") { showImporter = true }
                                Button("アルバムを作成", systemImage: "square.stack.badge.plus") { showAlbumEditor = true }
                            } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("追加")
                        }
                    }
                }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): Task { await library.importFiles(urls) }
                    case .failure(let error): library.message = error.localizedDescription
                    }
                }
                .sheet(isPresented: $showAlbumEditor) { CollectionEditor(kind: .album).environmentObject(library) }
        }
    }

    @ViewBuilder private var modeContent: some View {
        if library.tracks.isEmpty {
            ContentUnavailableView { Label("音楽を持ち歩こう", systemImage: "music.note.list") }
            description: { Text("「＋」またはPCのファイル共有から\n音楽を追加できます。") }
            actions: { Button("音楽ファイルを追加") { showImporter = true }.buttonStyle(.borderedProminent) }
        } else if visibleTracks.isEmpty && visibleAlbums.isEmpty {
            ContentUnavailableView("曲が見つかりません", systemImage: "magnifyingglass")
        } else {
            switch mode {
            case .songs:
                List {
                    Section {
                        ForEach(visibleTracks) { TrackRow(track: $0, context: visibleTracks) }
                    } header: {
                        Text("\(visibleTracks.count)曲 · 名前順").accessibilityIdentifier("library-song-count")
                    }.id("library-songs")
                }.listStyle(.plain).scrollContentBackground(.hidden)
            case .albums:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(visibleAlbums.count)アルバム").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .top), GridItem(.flexible(), spacing: 18, alignment: .top)], spacing: 22) {
                            ForEach(visibleAlbums) { album in
                                NavigationLink { AlbumDetailView(albumID: album.id) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        CoverView(image: album.artworkTrack.flatMap { library.artwork(for: $0) }, cornerRadius: 15)
                                            .accessibilityElement(children: .ignore).accessibilityLabel("\(album.title)のジャケット")
                                            .accessibilityIdentifier("album-cover-\(album.id)")
                                        Text(album.title).font(.subheadline.bold()).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("album-title-\(album.id)")
                                        Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1, reservesSpace: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("album-\(album.id)")
                            }
                        }
                    }.padding(.bottom, 16)
                }
            case .artists:
                let artists = Dictionary(grouping: visibleTracks) { $0.artist?.nonEmpty ?? "アーティスト未設定" }
                List(artists.keys.sorted(), id: \.self) { name in
                    NavigationLink {
                        ArtistDetailView(artist: name)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "person.fill").font(.title3).foregroundStyle(.indigo).frame(width: 44, height: 44)
                                .background(.indigo.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline)
                                Text("\(artists[name]?.count ?? 0)曲").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: MusicLibrary
    let track: Track
    let context: [Track]
    var playlistID: UUID? = nil
    var removeFavoriteOnly = false
    var accessibilityPrefix = "track"
    @State private var editing = false
    var body: some View {
        Button {
            library.select(track, context: context); library.playerPresented = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Text("\(track.artist?.nonEmpty ?? "アーティスト未設定") · \(track.album?.nonEmpty ?? "アルバム未設定")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if library.missingTrackIDs.contains(track.id) {
                        Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if track.hasLyrics {
                    Image(systemName: "quote.bubble").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("歌詞あり").accessibilityIdentifier("lyrics-available-\(track.id)")
                }
                if track.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.indigo) }
                if library.current?.id == track.id { Image(systemName: "waveform").foregroundStyle(.indigo) }
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("\(accessibilityPrefix)-\(track.id.uuidString)")
            .swipeActions(allowsFullSwipe: false) {
                if let playlistID { Button("プレイリストから外す", role: .destructive) { library.removeFromPlaylist(track.id, playlistID: playlistID) } }
                else if removeFavoriteOnly { Button("お気に入りから外す") { library.toggleFavorite(track) }.tint(.orange) }
                // This action only requests confirmation. A destructive swipe role would
                // optimistically remove the UIKit row before the catalogue changes.
                else { Button("ライブラリから削除") { library.trackPendingDeletion = track }.tint(.red) }
            }
            .contextMenu {
                Button("曲の情報を編集", systemImage: "pencil") { editing = true }
                Button(track.isFavorite ? "お気に入りを解除" : "お気に入りに追加", systemImage: "heart") { library.toggleFavorite(track) }
                if library.current?.id != track.id {
                    Button("次に再生", systemImage: "text.line.first.and.arrowtriangle.forward") { library.enqueue(track, next: true) }
                    Button("最後に再生", systemImage: "text.append") { library.enqueue(track, next: false) }
                }
                if let playlistID { Button("プレイリストから外す", systemImage: "minus.circle") { library.removeFromPlaylist(track.id, playlistID: playlistID) } }
                Button("ライブラリから削除", systemImage: "trash", role: .destructive) { library.trackPendingDeletion = track }
            }
            .sheet(isPresented: $editing) { TrackDetailsView(track: track).environmentObject(library) }
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    let albumID: String
    @State private var editing = false
    @State private var anchorTrackID: UUID?
    private var album: AlbumGroup? {
        library.albums.first { $0.id == albumID } ?? library.albums.first { group in
            if let anchorTrackID { return group.tracks.contains { $0.id == anchorTrackID } }
            return false
        }
    }
    var body: some View {
        Group {
            if let album {
                List {
                    Section {
                        HStack(spacing: 18) {
                            CoverView(image: album.artworkTrack.flatMap { library.artwork(for: $0) }).frame(width: 120, height: 120)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(album.title).font(.title3.bold())
                                Text(album.artist).foregroundStyle(.secondary)
                                Text("\(album.tracks.count)曲").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 10)
                        HStack(spacing: 12) {
                            Button("再生", systemImage: "play.fill") { start(album, shuffled: false) }.frame(minWidth: 0, maxWidth: .infinity)
                            Button("シャッフル", systemImage: "shuffle") { start(album, shuffled: true) }.frame(minWidth: 0, maxWidth: .infinity)
                        }.buttonStyle(.bordered).padding(.vertical, 4)
                    }
                    Section("収録曲") { ForEach(album.tracks) { TrackRow(track: $0, context: album.tracks) } }
                }.navigationTitle("アルバム").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("アルバムを編集", systemImage: "pencil") { editing = true } }
                    .sheet(isPresented: $editing) {
                        CollectionEditor(kind: .album, id: album.tracks.first?.albumID, initialTitle: album.title,
                                         initialArtist: album.artist, initialIDs: album.tracks.map(\.id)).environmentObject(library)
                    }
            } else { ContentUnavailableView("アルバムがありません", systemImage: "square.stack") }
        }
        .onAppear { if anchorTrackID == nil { anchorTrackID = album?.tracks.first?.id } }
    }
    private func start(_ album: AlbumGroup, shuffled: Bool) {
        if library.shuffleEnabled != shuffled { library.toggleShuffle() }
        if let track = shuffled ? album.tracks.randomElement() : album.tracks.first {
            library.select(track, context: album.tracks); library.resume(); library.playerPresented = true
        }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    let artist: String
    private var tracks: [Track] { library.tracks.filter { ($0.artist?.nonEmpty ?? "アーティスト未設定") == artist } }
    var body: some View {
        List {
            Section("アルバム") {
                ForEach(library.albums.filter { $0.tracks.contains { tracks.contains($0) } }) { album in
                    NavigationLink(album.title) { AlbumDetailView(albumID: album.id) }
                }
            }
            Section("曲") { ForEach(tracks) { TrackRow(track: $0, context: tracks) } }
        }.navigationTitle(artist)
    }
}
