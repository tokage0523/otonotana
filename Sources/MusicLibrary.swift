import AVFoundation
import Combine
import MediaPlayer
import Foundation
import UIKit

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
}

@MainActor
final class MusicLibrary: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var playing = false
    let clock = PlaybackClock()
    private(set) var position: Double {
        get { clock.position }
        set { clock.position = newValue }
    }
    @Published private(set) var duration: Double = 0
    @Published private(set) var importing = false
    @Published private(set) var sharedImportIssues: [SharedImportIssue] = []
    @Published private(set) var deletedTracks: [DeletedTrack] = []
    @Published private(set) var missingTrackIDs: Set<UUID> = []
    @Published private(set) var lyricLoop: PlaybackLoop?
    @Published var message: String?
    @Published var playerPresented = false
    @Published private(set) var artworkImage: UIImage?
    @Published private(set) var artworkTint = UIColor(red: 0.28, green: 0.23, blue: 0.38, alpha: 1)

    private var artworkCache: [String: UIImage] = [:]
    private var nowPlayingArtwork: MPMediaItemArtwork?

    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var manualAlbums: [ManualAlbum] = []
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    private var playbackOrder = PlaybackOrder()
    private var scanning = false
    private var failedStamps: [String: String] = [:]
    let sharedDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var albums: [AlbumGroup] { AlbumGroup.groups(tracks: tracks, manual: manualAlbums) }
    var queueTracks: [Track] { playbackOrder.order.compactMap { id in tracks.first { $0.id == id } } }
    var upcomingTracks: [Track] { playbackOrder.upcoming.compactMap { id in tracks.first { $0.id == id } } }
    var canGoNext: Bool { playbackOrder.canAdvance() }

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("library.json") }
    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    private var pendingPlayback: PlaybackSnapshot?
    private var lastPlaybackSave = Date.distantPast
    private var catalogReadable = true
    #if DEBUG
    @Published var verificationStatus: String?
    #endif

    override init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        super.init()
        if let data = try? Data(contentsOf: directory.appendingPathComponent("import-issues.json")),
           let issues = try? JSONDecoder().decode([SharedImportIssue].self, from: data) { sharedImportIssues = issues }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: indexURL))
            }
        } catch { message = "曲一覧を読み込めませんでした：\(error.localizedDescription)" }
        do {
            try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            let playlistURL = directory.appendingPathComponent("playlists.json")
            if FileManager.default.fileExists(atPath: playlistURL.path) {
                playlists = try JSONDecoder().decode([Playlist].self, from: Data(contentsOf: playlistURL))
            }
            let albumsURL = directory.appendingPathComponent("albums.json")
            if FileManager.default.fileExists(atPath: albumsURL.path) {
                manualAlbums = try JSONDecoder().decode([ManualAlbum].self, from: Data(contentsOf: albumsURL))
            }
        } catch { message = "保存した一覧を読み込めませんでした：\(error.localizedDescription)" }
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            do {
                let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: Data(contentsOf: catalogURL))
                guard catalog.version == 1 else { throw StorageError.invalidBackup }
                tracks = catalog.tracks; playlists = catalog.playlists; manualAlbums = catalog.albums; deletedTracks = catalog.deleted
            } catch {
                tracks = []; playlists = []; manualAlbums = []; catalogReadable = false
                message = "保存したデータを読み込めませんでした。バックアップから復元できます。元のデータは上書きしません。"
            }
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("playback.json")) {
            pendingPlayback = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        }
        shuffleEnabled = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeatMode") ?? "off") ?? .off
        playbackOrder.shuffled = shuffleEnabled; playbackOrder.repeatMode = repeatMode
        configureCommands()
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.playing
                    self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let shouldResume = self.resumeAfterInterruption &&
                        AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if shouldResume { self.resume() }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-fixture") {
            if !ProcessInfo.processInfo.arguments.contains("--restore-playback-test") { pendingPlayback = nil }
            prepareUITestFixture()
        }
        #endif
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        commands.forEach { $0.0.removeTarget($0.1) }
    }

    #if DEBUG
    func createUITestTrack(id: UUID) throws {
        let sampleRate: UInt32 = 8000
        let byteCount: UInt32 = sampleRate * 120 * 2
        var wav = Data()
        func ascii(_ string: String) { wav.append(contentsOf: string.utf8) }
        func u32(_ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        func u16(_ number: UInt16) { var value = number.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        ascii("RIFF"); u32(byteCount + 36); ascii("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16); ascii("data"); u32(byteCount)
        wav.append(Data(repeating: 0, count: Int(byteCount)))
        let filename = "ui-test-\(id.uuidString).wav"
        try wav.write(to: directory.appendingPathComponent(filename))
        var track = Track(id: id, title: "Afterglow", filename: filename)
        track.artist = "Sample Artist"
        track.album = "A little light"
        let text = ["ひとつずつ、歩いていこう", "風の音を聴きながら", "立ち止まる日があっても", "夜の向こうに、小さな灯り", "この音を、持ち帰ろう", "明日へ続く道の途中", "ゆっくりでいいから", "またここから始めよう"]
        let times: [Double] = [0, 12, 28, 42, 56, 70, 84, 98]
        track.lyrics = zip(times, text).map { LyricLine(id: UUID(), seconds: $0.0, text: $0.1) }
        let updated = tracks + [track]
        try save(updated)
        tracks = updated
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { renderer in
            let context = renderer.cgContext
            let colors = [UIColor(red: 0.89, green: 0.68, blue: 0.51, alpha: 1).cgColor,
                          UIColor(red: 0.71, green: 0.45, blue: 0.52, alpha: 1).cgColor,
                          UIColor(red: 0.33, green: 0.34, blue: 0.48, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 600), options: [])
            UIColor.white.withAlphaComponent(0.18).setFill()
            context.fillEllipse(in: CGRect(x: 235, y: -60, width: 410, height: 410))
            UIColor(red: 0.3, green: 0.25, blue: 0.4, alpha: 0.2).setFill()
            context.fillEllipse(in: CGRect(x: -90, y: 200, width: 420, height: 420))
            ("AFTERGLOW" as NSString).draw(at: CGPoint(x: 42, y: 440), withAttributes: [
                .font: UIFont(name: "Georgia", size: 61) ?? UIFont.systemFont(ofSize: 61), .foregroundColor: UIColor.white])
            ("A LITTLE LIGHT TO TAKE HOME" as NSString).draw(at: CGPoint(x: 46, y: 520), withAttributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: UIColor.white, .kern: 2])
        }
        if let data = image.jpegData(compressionQuality: 0.9) { try storeArtwork(data, for: id) }
    }
    #endif

    func importFiles(_ urls: [URL]) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        while scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        var failures: [String] = []
        for source in urls {
            let destinationDirectory = SharedFiles.canonicalURL(sharedDirectory)
            do {
                let track = try await Task.detached(priority: .userInitiated) {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let ext = source.pathExtension.lowercased()
                    guard ["m4a", "mp3", "wav", "aif", "aiff", "caf"].contains(ext) else {
                        throw NSError(domain: "MusicImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "未対応の形式です"])
                    }
                    let id = UUID()
                    let alreadyShared = SharedFiles.relativePath(for: source, under: destinationDirectory) != nil
                    var filename = source.lastPathComponent
                    if !alreadyShared && FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(filename).path) {
                        filename = "\(id.uuidString)-\(filename)"
                    }
                    let target = alreadyShared ? SharedFiles.canonicalURL(source) : destinationDirectory.appendingPathComponent(filename)
                    if !alreadyShared { try FileManager.default.copyItem(at: source, to: target) }
                    do {
                        // Decode before committing the library entry; no conversion is performed.
                        _ = try await AudioImportValidator.duration(at: target)
                        var value = Track(id: id, title: source.deletingPathExtension().lastPathComponent, filename: filename)
                        guard let path = SharedFiles.relativePath(for: target, under: destinationDirectory) else {
                            throw NSError(domain: "MusicImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "保存先の場所を確認できませんでした。"])
                        }
                        value.sharedPath = path
                        value.addedAt = Date()
                        return value
                    } catch {
                        if !alreadyShared { try? FileManager.default.removeItem(at: target) }
                        throw error
                    }
                }.value
                do {
                    if let path = track.sharedPath {
                        failedStamps[path] = nil
                        sharedImportIssues.removeAll { $0.path == path }
                    }
                    if tracks.contains(where: { $0.sharedPath == track.sharedPath }) { continue }
                    let updated = tracks + [track]
                    try save(updated)
                    tracks = updated
                    await readMetadata(for: track.id, replaceTitle: true)
                } catch {
                    // Keep the received audio available for retry if the index cannot be saved.
                    throw error
                }
            } catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !failures.isEmpty { message = failures.joined(separator: "\n") }
        importing = false
        await scanSharedFiles()
    }

    func audioURL(for track: Track) -> URL {
        if let path = track.sharedPath, let url = SharedFiles.safeURL(path, under: sharedDirectory) { return url }
        let legacy = directory.appendingPathComponent(track.filename)
        let migrated = sharedDirectory.appendingPathComponent("Music").appendingPathComponent(track.filename)
        // Recover the narrow window between moving an old file and saving its index.
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : migrated
    }

    func migrateLegacyAudio() {
        let folder = sharedDirectory.appendingPathComponent("Music", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for original in tracks where original.sharedPath == nil {
                let source = directory.appendingPathComponent(original.filename)
                let target = folder.appendingPathComponent(original.filename)
                let shouldMove = FileManager.default.fileExists(atPath: source.path)
                guard shouldMove || FileManager.default.fileExists(atPath: target.path) else { continue }
                if shouldMove { try FileManager.default.moveItem(at: source, to: target) }
                var track = original; track.sharedPath = "Music/\(original.filename)"
                do { try commitTrack(track) }
                catch {
                    if shouldMove { try? FileManager.default.moveItem(at: target, to: source) }
                    throw error
                }
            }
        } catch { message = "以前の音楽の移動を完了できませんでした。音楽は元の保存場所から引き続き再生できます。" }
    }

    private func removeUnusedArtwork(_ filename: String) {
        guard !tracks.contains(where: { $0.artworkFilename == filename }), !deletedTracks.contains(where: { $0.track.artworkFilename == filename }) else { return }
        artworkCache.removeValue(forKey: filename)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    private func persistPlaylists() throws {
        try writeCatalog(tracks: tracks, playlists: playlists, albums: manualAlbums, deleted: deletedTracks)
    }

    func savePlaylist(id: UUID? = nil, title: String, trackIDs: [UUID]) {
        guard let clean = title.nonEmpty else { return }
        let value = Playlist(id: id ?? UUID(), title: clean, trackIDs: trackIDs.filter { id in tracks.contains { $0.id == id } })
        var updated = playlists
        if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
        else { updated.append(value) }
        do {
            try writeCatalog(tracks: tracks, playlists: updated, albums: manualAlbums, deleted: deletedTracks)
            playlists = updated
        } catch { message = "プレイリストを保存できませんでした：\(error.localizedDescription)" }
    }

    func removePlaylist(_ playlist: Playlist) {
        let updated = playlists.filter { $0.id != playlist.id }
        do {
            try writeCatalog(tracks: tracks, playlists: updated, albums: manualAlbums, deleted: deletedTracks)
            playlists = updated
        } catch { message = error.localizedDescription }
    }

    func saveAlbum(id: UUID? = nil, title: String, artist: String, trackIDs: [UUID], artwork: Data? = nil) {
        guard let clean = title.nonEmpty else { return }
        let album = ManualAlbum(id: id ?? UUID(), title: clean, artist: artist)
        var records = manualAlbums
        if let index = records.firstIndex(where: { $0.id == album.id }) { records[index] = album }
        else { records.append(album) }
        var updated = tracks
        for i in updated.indices {
            if let number = trackIDs.firstIndex(of: updated[i].id) {
                updated[i].albumID = album.id; updated[i].album = clean
                updated[i].albumArtist = artist; updated[i].trackNumber = number + 1; updated[i].discNumber = 1
            } else if updated[i].albumID == album.id { updated[i].albumID = nil; updated[i].album = nil; updated[i].albumArtist = nil }
        }
        do {
            // Save the tracks last: until they reference this record, an extra album record is harmless.
            try writeCatalog(tracks: updated, playlists: playlists, albums: records, deleted: deletedTracks)
            manualAlbums = records; tracks = updated
            if let current { self.current = updated.first { $0.id == current.id }; updateNowPlaying() }
            if let artwork, let first = trackIDs.first {
                try storeArtwork(artwork, for: first)
                if let filename = tracks.first(where: { $0.id == first })?.artworkFilename {
                    var withArtwork = tracks
                    let old = withArtwork.filter { trackIDs.contains($0.id) }.compactMap(\.artworkFilename)
                    for i in withArtwork.indices where trackIDs.contains(withArtwork[i].id) { withArtwork[i].artworkFilename = filename }
                    try save(withArtwork); tracks = withArtwork
                    if let current { self.current = tracks.first { $0.id == current.id }; loadCurrentArtwork(); updateNowPlaying() }
                    for filename in Set(old) { removeUnusedArtwork(filename) }
                }
            }
        } catch { message = "アルバムを保存できませんでした：\(error.localizedDescription)" }
    }

    func scanSharedFiles() async {
        guard !scanning, !importing else { return }
        scanning = true
        defer { scanning = false }
        let root = SharedFiles.canonicalURL(sharedDirectory)
        do {
            let files = try await Task.detached(priority: .utility) { () -> [(String, String)] in
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
                guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
                var found: [(String, String)] = []
                for case let url as URL in walker {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    if values.isDirectory == true, FileManager.default.fileExists(atPath: url.appendingPathComponent(BackupFiles.manifestName).path) {
                        walker.skipDescendants(); continue
                    }
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          SharedFiles.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                    guard let path = SharedFiles.relativePath(for: url, under: root) else { continue }
                    let stamp = "\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                    found.append((path, stamp))
                }
                return found.sorted { $0.0 < $1.0 }
            }.value
            sharedImportIssues.removeAll { issue in !files.contains { $0.0 == issue.path } }
            var newFailures = 0
            for (path, stamp) in files {
                guard let url = SharedFiles.safeURL(path, under: root) else { continue }
                if failedStamps[path] == stamp { continue }
                var stage = "音楽ファイルの読み込み"
                do {
                    let id: UUID
                    if let existing = tracks.first(where: { $0.sharedPath == path }) {
                        id = existing.id
                        if existing.fileStamp != stamp {
                            _ = try await AudioImportValidator.duration(at: url)
                            stage = "曲一覧の保存"
                            guard var latest = tracks.first(where: { $0.id == id }) else { continue }
                            latest.fileStamp = stamp; try commitTrack(latest)
                        }
                    } else {
                        _ = try await AudioImportValidator.duration(at: url)
                        stage = "曲一覧の保存"
                        var track = Track(id: UUID(), title: url.deletingPathExtension().lastPathComponent, filename: url.lastPathComponent)
                        track.sharedPath = path; track.fileStamp = stamp; track.addedAt = Date(); id = track.id
                        let updated = tracks + [track]; try save(updated); tracks = updated
                        await readMetadata(for: id, replaceTitle: true)
                    }
                    if tracks.first(where: { $0.id == id })?.metadataVersion != 4 { await readMetadata(for: id) }
                    await updateSidecars(audio: url, id: id)
                    sharedImportIssues.removeAll { $0.path == path }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--m4a-test-fixture"), path.hasSuffix(".m4a") {
                        let registered = tracks.filter { $0.sharedPath == path }
                        assert(registered.count == 1)
                        assert(audioURL(for: registered[0]).standardizedFileURL == url.standardizedFileURL)
                        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(url.lastPathComponent).path))
                    }
                    if ProcessInfo.processInfo.arguments.contains("--shared-test-fixture"), path == "Shared test.wav" {
                        let registered = tracks.filter { $0.sharedPath == path }
                        assert(registered.count == 1, "Repeated shared scans must not duplicate tracks")
                        assert(audioURL(for: registered[0]).standardizedFileURL == url.standardizedFileURL,
                               "Shared playback must use the received file directly")
                        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Shared test.wav").path),
                               "Shared registration must not make a private audio copy")
                        assert(registered[0].lyrics?.count == 2, "Matching LRC should be registered")
                    }
                    #endif
                } catch {
                    failedStamps[path] = stamp
                    sharedImportIssues.removeAll { $0.path == path }
                    sharedImportIssues.append(SharedImportIssue(path: path, stage: stage, url: url, error: error))
                    newFailures += 1
                }
            }
            if let data = try? JSONEncoder().encode(sharedImportIssues) {
                try? data.write(to: directory.appendingPathComponent("import-issues.json"), options: .atomic)
            }
            if newFailures > 0 { message = "\(newFailures)件の音楽を登録できませんでした。設定の「読み込み結果」で原因を確認できます。" }
            refreshMissingTracks()
            restorePlaybackIfNeeded()
        } catch { message = "共有ファイルを確認できませんでした：\(error.localizedDescription)" }
    }

    func rescanSharedFiles() async { failedStamps = [:]; await scanSharedFiles() }

    private func updateSidecars(audio: URL, id: UUID) async {
        let base = audio.deletingPathExtension()
        func stamp(_ url: URL) -> String? {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { return nil }
            return "\(url.lastPathComponent):\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        let lrc = base.appendingPathExtension("lrc")
        if let value = stamp(lrc), tracks.first(where: { $0.id == id })?.lyricsStamp != value {
            do {
                let lines = try await Task.detached { try Lyrics.parse(String(contentsOf: lrc, encoding: .utf8)) }.value
                if var latest = tracks.first(where: { $0.id == id }) { latest.lyrics = lines; latest.lyricsStamp = value; try commitTrack(latest) }
            } catch { message = "\(lrc.lastPathComponent)：\(error.localizedDescription)" }
        }
        let images = [base.appendingPathExtension("jpg"), base.appendingPathExtension("png"),
                      audio.deletingLastPathComponent().appendingPathComponent("cover.jpg"),
                      audio.deletingLastPathComponent().appendingPathComponent("cover.png")]
        if let image = images.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           let value = stamp(image), tracks.first(where: { $0.id == id })?.imageStamp != value {
            do {
                let data = try await Task.detached { try Data(contentsOf: image) }.value
                try storeArtwork(data, for: id)
                if var latest = tracks.first(where: { $0.id == id }) { latest.imageStamp = value; try commitTrack(latest) }
            } catch { message = "ジャケットを読み込めませんでした：\(error.localizedDescription)" }
        }
    }

    private func save(_ value: [Track]) throws {
        try writeCatalog(tracks: value, playlists: playlists, albums: manualAlbums, deleted: deletedTracks)
    }

    private func writeCatalog(tracks: [Track], playlists: [Playlist], albums: [ManualAlbum], deleted: [DeletedTrack], allowRecovery: Bool = false) throws {
        guard catalogReadable || allowRecovery else { throw NSError(domain: "Catalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "保存データを読み込めないため上書きを止めています。バックアップから復元してください。"]) }
        try JSONEncoder().encode(LibraryCatalog(tracks: tracks, playlists: playlists, albums: albums, deleted: deleted))
            .write(to: catalogURL, options: .atomic)
    }

    private func commitTrack(_ track: Track) throws {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        var updated = tracks
        updated[index] = track
        try save(updated)
        tracks = updated
        if current?.id == track.id {
            current = track
            loadCurrentArtwork()
            updateNowPlaying()
        }
    }

    private func readMetadata(for id: UUID, replaceTitle: Bool = false) async {
        guard let original = tracks.first(where: { $0.id == id }) else { return }
        let asset = AVURLAsset(url: audioURL(for: original))
        do {
            let items = try await asset.load(.commonMetadata)
            var title: String?, artist: String?, album: String?, imageData: Data?
            var albumArtist: String?, trackNumber: Int?, discNumber: Int?
            var genre: String?, composer: String?, releaseYear: Int?
            for item in items {
                switch item.commonKey {
                case .commonKeyTitle: title = try? await item.load(.stringValue)
                case .commonKeyArtist: artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                case .commonKeyArtwork: imageData = try? await item.load(.dataValue)
                default: break
                }
            }
            let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
            for format in formats {
                for item in (try? await asset.loadMetadata(for: format)) ?? [] {
                    if item.identifier == .iTunesMetadataAlbumArtist { albumArtist = try? await item.load(.stringValue) }
                    if item.identifier == .iTunesMetadataUserGenre { genre = try? await item.load(.stringValue) }
                    if item.identifier == .iTunesMetadataComposer { composer = try? await item.load(.stringValue) }
                    if item.identifier == .iTunesMetadataReleaseDate, let raw = try? await item.load(.stringValue) {
                        releaseYear = Int(raw.prefix(4))
                    }
                    if item.identifier == .iTunesMetadataTrackNumber || item.identifier == .iTunesMetadataDiscNumber {
                        let number: Int?
                        if let data = try? await item.load(.dataValue), data.count >= 4 {
                            number = Int(data[2]) * 256 + Int(data[3])
                        } else if let raw = try? await item.load(.stringValue) { number = Int(raw.split(separator: "/").first ?? "") }
                        else { number = nil }
                        if item.identifier == .iTunesMetadataTrackNumber { trackNumber = number }
                        else { discNumber = number }
                    }
                }
            }
            guard var latest = tracks.first(where: { $0.id == id }) else { return }
            if replaceTitle, latest.title == original.title, let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { latest.title = title }
            if latest.artist == nil { latest.artist = artist }
            if latest.album == nil { latest.album = album }
            if latest.albumArtist == nil { latest.albumArtist = albumArtist }
            if latest.trackNumber == nil { latest.trackNumber = trackNumber }
            if latest.discNumber == nil { latest.discNumber = discNumber }
            if latest.genre == nil { latest.genre = genre }
            if latest.composer == nil { latest.composer = composer }
            if latest.releaseYear == nil { latest.releaseYear = releaseYear }
            latest.metadataVersion = 4
            try commitTrack(latest)
            if let imageData, latest.artworkFilename == nil { try storeArtwork(imageData, for: id) }
        } catch {
            // Metadata is optional. The imported audio remains available without it.
        }
    }

    func artwork(for track: Track) -> UIImage? {
        guard let filename = track.artworkFilename else { return nil }
        if let cached = artworkCache[filename] { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(filename).path) else { return nil }
        artworkCache[filename] = image
        return image
    }

    private func loadCurrentArtwork() {
        artworkImage = current.flatMap { artwork(for: $0) }
        artworkTint = artworkImage?.prominentColor ?? UIColor(red: 0.28, green: 0.23, blue: 0.38, alpha: 1)
        if let image = artworkImage { nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        else { nowPlayingArtwork = nil }
    }

    private func storeArtwork(_ data: Data, for id: UUID) throws {
        guard var track = tracks.first(where: { $0.id == id }) else { return }
        guard let original = UIImage(data: data), original.size.width > 0, original.size.height > 0 else {
            throw NSError(domain: "Artwork", code: 1, userInfo: [NSLocalizedDescriptionKey: "画像を読み込めませんでした。別の画像を選んでください。"])
        }
        let scale = min(1, 1200 / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = image.jpegData(compressionQuality: 0.9) else { return }
        let old = track.artworkFilename
        let filename = "\(id.uuidString)-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        try jpg.write(to: url, options: .atomic)
        track.artworkFilename = filename
        do { try commitTrack(track) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        if let old {
            artworkCache.removeValue(forKey: old)
            removeUnusedArtwork(old)
        }
    }

    func setArtwork(_ data: Data, for id: UUID) {
        do { try storeArtwork(data, for: id) }
        catch { message = error.localizedDescription }
    }

    func removeArtwork(for id: UUID) {
        guard var track = tracks.first(where: { $0.id == id }) else { return }
        let old = track.artworkFilename
        track.artworkFilename = nil
        do {
            try commitTrack(track)
            if let old {
                artworkCache.removeValue(forKey: old)
                removeUnusedArtwork(old)
            }
        } catch { message = "ジャケットを変更できませんでした：\(error.localizedDescription)" }
    }

    func updateDetails(for id: UUID, title: String, artist: String, album: String, albumArtist: String = "", trackNumber: Int? = nil,
                       discNumber: Int? = nil, genre: String? = nil, releaseYear: Int? = nil, composer: String? = nil, notes: String? = nil) {
        guard var track = tracks.first(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { message = "曲名を入力してください。"; return }
        guard [trackNumber, discNumber, releaseYear].allSatisfy({ $0 == nil || $0! > 0 }),
              releaseYear == nil || releaseYear! <= 9999 else { message = "収録順・ディスク番号は1以上、発売年は1〜9999で入力してください。"; return }
        track.title = cleanTitle
        track.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        if track.album != cleanAlbum { track.albumID = nil }
        track.album = cleanAlbum
        track.albumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        track.trackNumber = trackNumber
        track.discNumber = discNumber
        track.genre = genre?.nonEmpty
        track.releaseYear = releaseYear
        track.composer = composer?.nonEmpty
        track.notes = notes?.nonEmpty
        do { try commitTrack(track) }
        catch { message = "曲の情報を保存できませんでした：\(error.localizedDescription)" }
    }

    func toggleFavorite(_ track: Track) {
        guard var latest = tracks.first(where: { $0.id == track.id }) else { return }
        latest.favorite = !latest.isFavorite
        do { try commitTrack(latest) }
        catch { message = "お気に入りを保存できませんでした：\(error.localizedDescription)" }
    }

    func importLyrics(_ url: URL, for trackID: UUID) async {
        do {
            let content = try await Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return try String(contentsOf: url, encoding: .utf8)
            }.value
            let lines = try Lyrics.parse(content)
            guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
            var updated = tracks
            updated[index].lyrics = lines
            try save(updated)
            tracks = updated
            if current?.id == trackID { current = updated[index] }
        } catch { message = "歌詞を読み込めませんでした：\(error.localizedDescription)" }
    }

    func playLyric(_ line: LyricLine, trackID: UUID) {
        guard current?.id == trackID else { return }
        let seconds = current?.lyricTime(line) ?? line.seconds
        guard seconds < duration else {
            message = "この歌詞の時刻は曲の長さを超えています。PCで時刻を修正してください。"
            return
        }
        seek(seconds)
        if !playing { resume() }
    }

    func remove(_ track: Track) {
        let id = UUID()
        let source = audioURL(for: track)
        let name = FileManager.default.fileExists(atPath: source.path) ? id.uuidString + "." + source.pathExtension : nil
        let trash = directory.appendingPathComponent("Trash", isDirectory: true)
        let destination = name.map { trash.appendingPathComponent($0) }
        do {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            if let destination { try FileManager.default.moveItem(at: source, to: destination) }
            let updated = tracks.filter { $0.id != track.id }
            let positions = playlists.compactMap { list in list.trackIDs.firstIndex(of: track.id).map { PlaylistPosition(playlistID: list.id, index: $0) } }
            let record = DeletedTrack(id: id, track: track, removedAt: Date(), audioName: name, positions: positions)
            var lists = playlists
            for index in lists.indices { lists[index].trackIDs.removeAll { $0 == track.id } }
            try writeCatalog(tracks: updated, playlists: lists, albums: manualAlbums, deleted: deletedTracks + [record])
            tracks = updated; playlists = lists; deletedTracks.append(record)
            if current?.id == track.id { stop() }
            playbackOrder.remove(track.id)
            refreshMissingTracks(); savePlaybackState()
        } catch {
            if let destination, FileManager.default.fileExists(atPath: destination.path) { try? FileManager.default.moveItem(at: destination, to: source) }
            message = "削除できませんでした：\(error.localizedDescription)"
        }
    }

    func removeFromPlaylist(_ trackID: UUID, playlistID: UUID) {
        guard let list = playlists.first(where: { $0.id == playlistID }) else { return }
        savePlaylist(id: list.id, title: list.title, trackIDs: list.trackIDs.filter { $0 != trackID })
    }

    func restoreDeleted(_ record: DeletedTrack) {
        let source = record.audioName.map { directory.appendingPathComponent("Trash").appendingPathComponent($0) }
        let target = audioURL(for: record.track)
        var moved = false
        do {
            guard !tracks.contains(where: { $0.id == record.track.id }) else { throw StorageError.fileConflict }
            if let source {
                guard !FileManager.default.fileExists(atPath: target.path) else { throw StorageError.fileConflict }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: source, to: target); moved = true
            }
            var lists = playlists
            for saved in record.positions {
                if let index = lists.firstIndex(where: { $0.id == saved.playlistID }), !lists[index].trackIDs.contains(record.track.id) {
                    lists[index].trackIDs.insert(record.track.id, at: min(saved.index, lists[index].trackIDs.count))
                }
            }
            let deleted = deletedTracks.filter { $0.id != record.id }
            try writeCatalog(tracks: tracks + [record.track], playlists: lists, albums: manualAlbums, deleted: deleted)
            tracks.append(record.track); playlists = lists; deletedTracks = deleted; refreshMissingTracks()
        } catch {
            if moved, let source { try? FileManager.default.moveItem(at: target, to: source) }
            message = "復元できませんでした：\(error.localizedDescription)"
        }
    }

    func permanentlyDelete(_ record: DeletedTrack) {
        do {
            if let name = record.audioName {
                let url = directory.appendingPathComponent("Trash").appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let updated = deletedTracks.filter { $0.id != record.id }
            try writeCatalog(tracks: tracks, playlists: playlists, albums: manualAlbums, deleted: updated)
            deletedTracks = updated
            if let name = record.track.artworkFilename { removeUnusedArtwork(name) }
        } catch { message = "完全に削除できませんでした：\(error.localizedDescription)" }
    }

    func refreshMissingTracks() {
        missingTrackIDs = Set(tracks.filter { !FileManager.default.fileExists(atPath: audioURL(for: $0).path) }.map(\.id))
    }

    func setLyricsOffset(_ value: Double) {
        guard value.isFinite, abs(value) <= 3600, var track = current else { return }
        track.lyricsOffset = (value * 10).rounded() / 10
        do { try commitTrack(track); lyricLoop = nil }
        catch { message = "歌詞の調整を保存できませんでした：\(error.localizedDescription)" }
    }

    func setLoopStart(_ line: LyricLine) {
        guard let track = current else { return }
        let start = track.lyricTime(line)
        guard start < duration else { message = "この歌詞は曲の長さを超えています。"; return }
        lyricLoop = PlaybackLoop(trackID: track.id, start: start, end: nil)
    }

    func setLoopEnd(_ line: LyricLine) {
        guard let track = current, let lines = track.lyrics, let index = lines.firstIndex(where: { $0.id == line.id }),
              let range = lyricLoop, range.trackID == track.id else { return }
        let time = track.lyricTime(line)
        guard time >= range.start else { message = "開始の歌詞より後の行を選んでください。"; return }
        let end = index + 1 < lines.count ? min(duration, track.lyricTime(lines[index + 1])) : duration
        guard end > range.start else { message = "繰り返す範囲が短すぎます。"; return }
        lyricLoop = PlaybackLoop(trackID: track.id, start: range.start, end: end)
        seek(range.start); resume()
    }

    func clearLyricLoop() { lyricLoop = nil }

    func enqueue(_ track: Track, next: Bool) {
        guard current != nil else { select(track); return }
        playbackOrder.enqueue(track.id, next: next)
        objectWillChange.send(); savePlaybackState()
    }

    func playQueued(_ track: Track) {
        let old = playbackOrder
        playbackOrder.jump(to: track.id)
        if !loadTrack(track) { playbackOrder = old }
    }

    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        var ids = playbackOrder.upcoming
        let moved = offsets.sorted().compactMap { ids.indices.contains($0) ? ids[$0] : nil }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where ids.indices.contains(index) { ids.remove(at: index) }
        ids.insert(contentsOf: moved, at: max(0, min(adjusted, ids.count)))
        playbackOrder.replaceUpcoming(ids); objectWillChange.send(); savePlaybackState()
    }

    func removeUpcoming(_ id: UUID) {
        playbackOrder.replaceUpcoming(playbackOrder.upcoming.filter { $0 != id }); objectWillChange.send(); savePlaybackState()
    }

    func savePlaybackState() {
        do {
            let data = try JSONEncoder().encode(PlaybackSnapshot(order: playbackOrder, position: position))
            try data.write(to: directory.appendingPathComponent("playback.json"), options: .atomic)
            lastPlaybackSave = Date()
        } catch { /* Playback remains usable if a temporary state save fails. */ }
    }

    private func restorePlaybackIfNeeded() {
        guard var snapshot = pendingPlayback else { return }
        pendingPlayback = nil
        snapshot.order.sanitize(validIDs: Set(tracks.map(\.id)))
        guard let id = snapshot.order.current, let track = tracks.first(where: { $0.id == id }), !missingTrackIDs.contains(id) else { return }
        playbackOrder = snapshot.order
        shuffleEnabled = snapshot.order.shuffled; repeatMode = snapshot.order.repeatMode
        if loadTrack(track, autoplay: false) { seek(snapshot.position); savePlaybackState() }
    }

    func select(_ track: Track, context: [Track]? = nil) {
        let old = playbackOrder
        playbackOrder.start(track.id, in: (context ?? tracks).map(\.id))
        if current?.id == track.id, player != nil { updateNowPlaying(); savePlaybackState(); return }
        if !loadTrack(track) { playbackOrder = old }
    }

    @discardableResult
    private func loadTrack(_ track: Track, autoplay: Bool = true) -> Bool {
        do {
            let next = try AVAudioPlayer(contentsOf: audioURL(for: track))
            next.delegate = self
            next.prepareToPlay()
            player?.stop()
            timer?.invalidate()
            player = next
            current = track
            lyricLoop = nil
            loadCurrentArtwork()
            position = 0
            duration = next.duration
            playing = false
            if autoplay { resume() } else { updateNowPlaying() }
            savePlaybackState()
            return true
        } catch {
            refreshMissingTracks()
            message = missingTrackIDs.contains(track.id) ? "音楽ファイルが見つかりません。設定の「音楽が見つからない曲」で保存場所を指定し直せます。" : "再生できませんでした：\(error.localizedDescription)"
            return false
        }
    }

    func toggle() {
        if playing { pause() }
        else if player != nil { resume() }
        else if let first = tracks.first { select(first) }
    }

    func resume() {
        guard let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else {
                message = "再生を開始できませんでした。"
                return
            }
            playing = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let before = self.position
                    if let range = self.lyricLoop, let end = range.end, (self.player?.currentTime ?? 0) >= end {
                        self.player?.currentTime = range.start
                    }
                    self.position = self.player?.currentTime ?? 0
                    if Int(before) != Int(self.position) { self.updateNowPlaying() }
                    if Date().timeIntervalSince(self.lastPlaybackSave) >= 5 { self.savePlaybackState() }
                }
            }
            updateNowPlaying()
        } catch { message = "音声出力を開始できませんでした：\(error.localizedDescription)" }
    }

    func pause() {
        player?.pause()
        playing = false
        timer?.invalidate()
        position = player?.currentTime ?? 0
        updateNowPlaying()
        savePlaybackState()
    }

    private func stop() {
        player?.stop()
        player = nil
        current = nil
        lyricLoop = nil
        artworkImage = nil
        nowPlayingArtwork = nil
        playing = false
        position = 0
        duration = 0
        timer?.invalidate()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        savePlaybackState()
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = min(max(0, seconds), duration)
        if let range = lyricLoop, let end = range.end, position < range.start || position >= end { lyricLoop = nil }
        player?.currentTime = position
        updateNowPlaying()
        savePlaybackState()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle(); playbackOrder.setShuffle(shuffleEnabled)
        UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled")
        updateNowPlaying(); savePlaybackState()
    }
    func cycleRepeat() {
        let modes = RepeatMode.allCases
        repeatMode = modes[(modes.firstIndex(of: repeatMode)! + 1) % modes.count]
        playbackOrder.repeatMode = repeatMode
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
        updateNowPlaying(); savePlaybackState()
    }
    func next(automatic: Bool = false) {
        let old = playbackOrder
        guard let id = playbackOrder.advance(automatic: automatic), let track = tracks.first(where: { $0.id == id }) else { return }
        if !loadTrack(track) { playbackOrder = old }
    }
    func previous() {
        if position > 3 { seek(0); return }
        let old = playbackOrder
        guard let id = playbackOrder.retreat(), let track = tracks.first(where: { $0.id == id }) else { seek(0); return }
        if !loadTrack(track) { playbackOrder = old }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            if flag, let range = self.lyricLoop, range.end != nil { self.seek(range.start); self.resume(); return }
            self.pause()
            if flag { self.next(automatic: true) }
            else { self.message = "曲の再生中にエラーが発生しました。" }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.pause()
            self.message = "音声を読み取れませんでした。"
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if let artist = current.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = current.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork = nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = canGoNext
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = true
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor (MusicLibrary) -> Void) {
            command.isEnabled = true
            let token = command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                Task { @MainActor in action(self) }
                return .success
            }
            commands.append((command, token))
        }
        register(center.playCommand) { $0.resume() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        center.changePlaybackPositionCommand.isEnabled = true
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in self.seek(seconds) }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, token))
    }
}

extension MusicLibrary {
    func createBackup(includeAudio: Bool) async throws -> URL {
        guard !scanning, !importing else { throw StorageError.busy }
        guard catalogReadable else { throw StorageError.invalidBackup }
        importing = true; defer { importing = false }
        let settings = Dictionary(uniqueKeysWithValues: BackupFiles.settingsKeys.compactMap { key -> (String, String)? in
            guard let value = UserDefaults.standard.object(forKey: key) else { return nil }
            return (key, String(describing: value))
        })
        let records = tracks.map { original -> Track in
            var track = original
            if track.sharedPath == nil { track.sharedPath = "Music/" + track.filename }
            return track
        }
        let manifest = BackupManifest(createdAt: Date(), tracks: records, playlists: playlists, albums: manualAlbums,
                                      audioFiles: [:], artworkFiles: [:], settings: settings)
        let audio = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, audioURL(for: $0)) })
        let artworkRoot = directory
        return try await Task.detached(priority: .userInitiated) {
            try BackupFiles.export(manifest: manifest, audio: audio, artworkRoot: artworkRoot, includeAudio: includeAudio)
        }.value
    }

    func restoreBackup(from folder: URL) async throws {
        guard !scanning, !importing else { throw StorageError.busy }
        importing = true; defer { importing = false }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let shared = sharedDirectory, support = directory, existing = tracks
        let prepared = try await Task.detached(priority: .userInitiated) {
            try BackupFiles.prepareRestore(at: folder, existing: existing, sharedRoot: shared, supportRoot: support)
        }.value
        defer { try? FileManager.default.removeItem(at: prepared.staging) }
        // Verify all archived audio before moving files or changing the catalog.
        let stagedAudio = (try? FileManager.default.contentsOfDirectory(at: prepared.audioFolder, includingPropertiesForKeys: nil)) ?? []
        for url in stagedAudio { _ = try await AudioImportValidator.duration(at: url) }
        for url in prepared.artwork.values { guard UIImage(contentsOfFile: url.path) != nil else { throw StorageError.invalidBackup } }
        let restoredIDs = Set(prepared.manifest.tracks.map(\.id))
        var merged = tracks.filter { !restoredIDs.contains($0.id) && prepared.replaces[$0.id] == nil }
        merged += prepared.manifest.tracks
        var lists = playlists.filter { old in !prepared.manifest.playlists.contains { $0.id == old.id } }
        for index in lists.indices {
            lists[index].trackIDs = lists[index].trackIDs.map { prepared.replaces[$0] ?? $0 }
        }
        lists += prepared.manifest.playlists
        var albums = manualAlbums.filter { old in !prepared.manifest.albums.contains { $0.id == old.id } }
        albums += prepared.manifest.albums
        var moved: [URL] = []
        do {
            if !stagedAudio.isEmpty {
                try FileManager.default.createDirectory(at: prepared.finalAudioFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: prepared.audioFolder, to: prepared.finalAudioFolder)
                moved.append(prepared.finalAudioFolder)
            }
            for (name, staged) in prepared.artwork {
                let target = directory.appendingPathComponent(name)
                try FileManager.default.moveItem(at: staged, to: target); moved.append(target)
            }
            try writeCatalog(tracks: merged, playlists: lists, albums: albums, deleted: deletedTracks, allowRecovery: true)
        } catch {
            for url in moved { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        let oldArtwork = Set(tracks.compactMap(\.artworkFilename))
        tracks = merged; playlists = lists; manualAlbums = albums; catalogReadable = true
        if let id = current?.id { current = tracks.first { $0.id == id }; loadCurrentArtwork() }
        for name in oldArtwork { removeUnusedArtwork(name) }
        for (key, value) in prepared.manifest.settings where BackupFiles.settingsKeys.contains(key) {
            if ["lyricsTimestamps", "lyricsPreview", "lyricsAutoScroll"].contains(key) { UserDefaults.standard.set(value == "true" || value == "1", forKey: key) }
            else if key == "lyricsSize" { UserDefaults.standard.set(Int(value) ?? 1, forKey: key) }
            else { UserDefaults.standard.set(value, forKey: key) }
        }
        refreshMissingTracks(); updateNowPlaying(); savePlaybackState()
    }

    func relink(_ trackID: UUID, to source: URL) async {
        guard !importing, let original = tracks.first(where: { $0.id == trackID }) else { return }
        importing = true; defer { importing = false }
        while scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var copied: URL?
        do {
            guard SharedFiles.audioExtensions.contains(source.pathExtension.lowercased()) else { throw StorageError.unsafePath }
            _ = try await AudioImportValidator.duration(at: source)
            let target: URL
            if SharedFiles.relativePath(for: source, under: sharedDirectory) != nil { target = SharedFiles.canonicalURL(source) }
            else {
                target = sharedDirectory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: target); copied = target
            }
            guard let path = SharedFiles.relativePath(for: target, under: sharedDirectory) else { throw StorageError.unsafePath }
            let duplicate = tracks.first { $0.id != trackID && $0.sharedPath == path }
            var track = original; track.sharedPath = path; track.filename = source.lastPathComponent; track.fileStamp = nil
            var updated = tracks.filter { $0.id != trackID && $0.id != duplicate?.id }; updated.append(track)
            var lists = playlists
            if let duplicate {
                for index in lists.indices {
                    var seen = Set<UUID>()
                    lists[index].trackIDs = lists[index].trackIDs.map { $0 == duplicate.id ? trackID : $0 }.filter { seen.insert($0).inserted }
                }
            }
            try writeCatalog(tracks: updated, playlists: lists, albums: manualAlbums, deleted: deletedTracks)
            tracks = updated; playlists = lists
            if current?.id == trackID { _ = loadTrack(track, autoplay: false) }
            if let name = duplicate?.artworkFilename { removeUnusedArtwork(name) }
            refreshMissingTracks()
        } catch {
            if let copied { try? FileManager.default.removeItem(at: copied) }
            message = "保存場所を変更できませんでした：\(error.localizedDescription)"
        }
    }
}
