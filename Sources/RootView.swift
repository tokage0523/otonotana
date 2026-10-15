import SwiftUI

enum AppTab: String, CaseIterable {
    case library = "ライブラリ", playlists = "プレイリスト", settings = "設定"
    var icon: String { self == .library ? "square.stack" : self == .playlists ? "music.note.list" : "gearshape" }
}

struct RootView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var tab: AppTab = .library

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LibraryView().opacity(tab == .library ? 1 : 0).allowsHitTesting(tab == .library).accessibilityHidden(tab != .library)
                PlaylistsView().opacity(tab == .playlists ? 1 : 0).allowsHitTesting(tab == .playlists).accessibilityHidden(tab != .playlists)
                SettingsView().opacity(tab == .settings ? 1 : 0).allowsHitTesting(tab == .settings).accessibilityHidden(tab != .settings)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(library.importing)
            if let track = library.current { MiniPlayer(track: track).padding(.horizontal, 16).padding(.top, 6) }
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.system(size: 21))
                            Text(item.rawValue).font(.caption2)
                        }.foregroundStyle(tab == item ? Color.indigo : Color.secondary)
                            .frame(minWidth: 0, maxWidth: .infinity).frame(minHeight: 58).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(item.rawValue)")
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(.horizontal, 12)
        }.background(Color(.systemGroupedBackground)).tint(.indigo)
            .confirmationDialog("「\(library.trackPendingDeletion?.title ?? "")」をライブラリから削除しますか？",
                                isPresented: Binding(get: { library.trackPendingDeletion != nil },
                                                     set: { if !$0 { library.trackPendingDeletion = nil } }),
                                titleVisibility: .visible, presenting: library.trackPendingDeletion) { track in
                Button("最近削除した曲へ移す", role: .destructive) {
                    library.trackPendingDeletion = nil
                    library.remove(track)
                }
                Button("キャンセル", role: .cancel) { library.trackPendingDeletion = nil }
            } message: { _ in Text("プレイリストからも外れます。設定の「最近削除した曲」から復元できます。") }
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
            .sheet(isPresented: $library.playerPresented) { PlayerView().environmentObject(library) }
            .alert("お知らせ", isPresented: Binding(get: { library.message != nil && !library.playerPresented },
                                                  set: { if !$0 { library.message = nil } })) {
                Button("OK") { library.message = nil }
            } message: { Text(library.message ?? "") }
            .task {
                library.migrateLegacyAudio(); await library.scanSharedFiles()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--data-integrity-test") { await library.runDataIntegrityChecks() }
                #endif
            }
            .overlay(alignment: .top) {
                #if DEBUG
                if let status = library.verificationStatus { Text(status).padding().background(.regularMaterial).accessibilityIdentifier("data-integrity-result") }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await library.scanSharedFiles() } }
                else { library.savePlaybackState() }
            }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var library: MusicLibrary
    let track: Track
    var body: some View {
        HStack(spacing: 10) {
            Button { library.playerPresented = true } label: {
                HStack(spacing: 10) {
                    CoverView(image: library.artworkImage, cornerRadius: 8).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.subheadline.bold()).lineLimit(1)
                        Text(track.artist?.nonEmpty ?? "アーティスト未設定").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(track.title)の再生画面を開く")
            HStack(spacing: 0) {
                Button(library.playing ? "一時停止" : "再生", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }
                Button("次の曲", systemImage: "forward.end.fill") { library.next() }.disabled(!library.canGoNext)
            }.labelStyle(.iconOnly).font(.title3).buttonStyle(EqualPlayerButtonStyle())
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct EqualPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 44, height: 44).contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @AppStorage("playerTheme") private var theme = PlayerTheme.artwork.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("lyricsTimestamps") private var timestamps = false
    @AppStorage("lyricsPreview") private var preview = true
    @State private var refreshing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("アプリの外観", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.name).tag($0.rawValue).accessibilityIdentifier("appearance-\($0.rawValue)") }
                    }.pickerStyle(.navigationLink).accessibilityIdentifier("settings-appearance")
                    if appearance == AppAppearance.system.rawValue {
                        Text("iPhoneのライト／ダーク設定と連動します。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("再生画面のテーマ", selection: $theme) { ForEach(PlayerTheme.allCases) { Text($0.name).tag($0.rawValue) } }
                    Toggle("ジャケットの下に歌詞を表示", isOn: $preview)
                }
                Section("歌詞") {
                    Toggle("歌詞の秒数を表示", isOn: $timestamps).accessibilityIdentifier("settings-timestamps")
                    Text("文字サイズと自動スクロールは歌詞画面で変更できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("PCから追加") {
                    Text("USB接続後、iTunesまたはAppleデバイスの「ファイル共有」でOtonotanaへ音楽を追加してください。")
                    Text("音楽と同じ名前のLRCを一緒に入れると歌詞も登録します。曲名.jpg／曲名.png、またはcover.jpg／cover.pngでジャケットも追加できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("この保存場所から直接再生し、音楽の追加コピーは作りません。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { refreshing = true; await library.rescanSharedFiles(); refreshing = false }
                    } label: { HStack { Text("共有ファイルを再読み込み"); if refreshing { ProgressView() } } }
                        .disabled(refreshing).accessibilityIdentifier("rescan-shared-files")
                    if !library.sharedImportIssues.isEmpty {
                        NavigationLink("読み込み結果（\(library.sharedImportIssues.count)件）") {
                            List(library.sharedImportIssues) { issue in
                                Section(issue.path) {
                                    Text(issue.reason)
                                    Text(issue.details).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }.navigationTitle("読み込み結果")
                        }.accessibilityIdentifier("shared-import-results")
                    }
                }
                Section("データの管理") {
                    NavigationLink("バックアップと復元") { BackupView() }.accessibilityIdentifier("settings-backup")
                    NavigationLink("最近削除した曲（\(library.deletedTracks.count)曲）") { RecentlyDeletedView() }.accessibilityIdentifier("settings-trash")
                    NavigationLink("音楽が見つからない曲（\(library.missingTrackIDs.count)曲）") { MissingTracksView() }.accessibilityIdentifier("settings-missing")
                }
                Section { Text("音の棚 0.4").foregroundStyle(.secondary) }
            }.navigationTitle("設定")
        }
    }
}
