import AVFoundation
import Combine
import MediaPlayer
import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let filename: String
    var lyrics: [LyricLine]? = nil
}

@MainActor
final class MusicLibrary: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var playing = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var importing = false
    @Published var message: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    override init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: indexURL))
            }
        } catch { message = "曲一覧を読み込めませんでした：\(error.localizedDescription)" }
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
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        commands.forEach { $0.0.removeTarget($0.1) }
    }

    func importFiles(_ urls: [URL]) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        var failures: [String] = []
        for source in urls {
            let destinationDirectory = directory
            do {
                let track = try await Task.detached(priority: .userInitiated) {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let ext = source.pathExtension.lowercased()
                    guard ["m4a", "mp3", "wav", "aif", "aiff", "caf"].contains(ext) else {
                        throw NSError(domain: "MusicImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "未対応の形式です"])
                    }
                    let id = UUID()
                    let filename = "\(id.uuidString).\(ext)"
                    let target = destinationDirectory.appendingPathComponent(filename)
                    try FileManager.default.copyItem(at: source, to: target)
                    do {
                        // Decode before committing the library entry; no conversion is performed.
                        _ = try AVAudioPlayer(contentsOf: target)
                        return Track(id: id, title: source.deletingPathExtension().lastPathComponent, filename: filename)
                    } catch {
                        try? FileManager.default.removeItem(at: target)
                        throw error
                    }
                }.value
                do {
                    let updated = tracks + [track]
                    try save(updated)
                    tracks = updated
                } catch {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(track.filename))
                    throw error
                }
            } catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !failures.isEmpty { message = failures.joined(separator: "\n") }
    }

    private func save(_ value: [Track]) throws {
        try JSONEncoder().encode(value).write(to: indexURL, options: .atomic)
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
        guard line.seconds < duration else {
            message = "この歌詞の時刻は曲の長さを超えています。PCで時刻を修正してください。"
            return
        }
        seek(line.seconds)
        if !playing { resume() }
    }

    func remove(_ track: Track) {
        do {
            let updated = tracks.filter { $0.id != track.id }
            try save(updated)
            tracks = updated
            if current?.id == track.id { stop() }
            try FileManager.default.removeItem(at: directory.appendingPathComponent(track.filename))
        } catch { message = "削除できませんでした：\(error.localizedDescription)" }
    }

    func select(_ track: Track) {
        do {
            let next = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(track.filename))
            next.delegate = self
            next.prepareToPlay()
            player?.stop()
            timer?.invalidate()
            player = next
            current = track
            position = 0
            duration = next.duration
            playing = false
            resume()
        } catch { message = "再生できませんでした：\(error.localizedDescription)" }
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
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.position = self.player?.currentTime ?? 0
                    self.updateNowPlaying()
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
    }

    private func stop() {
        player?.stop()
        player = nil
        current = nil
        playing = false
        position = 0
        duration = 0
        timer?.invalidate()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = min(max(0, seconds), duration)
        player?.currentTime = position
        updateNowPlaying()
    }

    func next() {
        guard let current, let index = tracks.firstIndex(where: { $0.id == current.id }), index + 1 < tracks.count else { return }
        select(tracks[index + 1])
    }

    func previous() {
        if position > 3 { seek(0); return }
        guard let current, let index = tracks.firstIndex(where: { $0.id == current.id }), index > 0 else { seek(0); return }
        select(tracks[index - 1])
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.pause()
            if flag { self.next() }
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        let index = tracks.firstIndex(where: { $0.id == current.id }) ?? 0
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = index + 1 < tracks.count
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
