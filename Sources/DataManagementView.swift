import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var includeAudio = false
    @State private var busy = false
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var showImport = false
    @State private var restoreURL: URL?
    @State private var confirmRestore = false
    @State private var result: String?
    var body: some View {
        Form {
            Section("バックアップを保存") {
                Text("歌詞の時刻・曲情報・ジャケット・プレイリスト・表示設定を、フォルダーにまとめて保存します。")
                Toggle("音楽ファイルも含める", isOn: $includeAudio)
                Text(includeAudio ? "音楽を含むため、保存先に音楽と同じ分の空き容量が必要です。" : "音楽は複製しません。復元時は同じ音楽ファイルを用意してください。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("バックアップを保存") {
                    Task {
                        busy = true; defer { busy = false }
                        do { exportURL = try await library.createBackup(includeAudio: includeAudio); showExport = true }
                        catch { result = error.localizedDescription }
                    }
                }.disabled(busy).accessibilityIdentifier("backup-create")
            }
            Section("バックアップから復元") {
                Text("保存した「音の棚バックアップ」のフォルダーを選びます。同じ曲の編集情報はバックアップの内容へ戻り、ほかの曲は残ります。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("バックアップを選ぶ") { showImport = true }.disabled(busy)
                    .accessibilityIdentifier("backup-restore")
            }
            if busy { Section { HStack { ProgressView(); Text("処理しています…") } } }
        }.navigationTitle("バックアップと復元")
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.folder]) { outcome in
                switch outcome {
                case .success(let url): restoreURL = url; confirmRestore = true
                case .failure(let error): result = error.localizedDescription
                }
            }
            .confirmationDialog("このバックアップから復元しますか？", isPresented: $confirmRestore) {
                Button("復元する") {
                    guard let url = restoreURL else { return }; restoreURL = nil
                    Task {
                        busy = true; defer { busy = false }
                        do { try await library.restoreBackup(from: url); result = "復元しました。音楽が見つからない曲は、設定から保存場所を指定し直せます。" }
                        catch { result = "復元できませんでした：" + error.localizedDescription }
                    }
                }
                Button("キャンセル", role: .cancel) { restoreURL = nil }
            }
            .sheet(isPresented: $showExport, onDismiss: {
                if let url = exportURL { try? FileManager.default.removeItem(at: url) }; exportURL = nil
            }) {
                if let exportURL { FolderExporter(url: exportURL) { showExport = false } }
            }
            .alert("バックアップ", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK") { result = nil }
            } message: { Text(result ?? "") }
    }
}

struct FolderExporter: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: () -> Void
        init(completion: @escaping () -> Void) { self.completion = completion }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion() }
    }
}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var permanent: DeletedTrack?
    @State private var confirmPermanent = false
    var body: some View {
        List {
            Section {
                Text("ここにある音楽は復元できます。容量を空けるには、曲のメニューから「完全に削除」を選んでください。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if library.deletedTracks.isEmpty { Text("削除した曲はありません") }
            ForEach(library.deletedTracks) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.track.title).font(.headline)
                    Text(item.track.artist?.nonEmpty ?? "アーティスト未設定").font(.caption).foregroundStyle(.secondary)
                    Text(item.removedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("復元") { library.restoreDeleted(item) }.accessibilityIdentifier("trash-restore-\(item.track.id)")
                        Spacer()
                        Button("完全に削除", role: .destructive) { permanent = item; confirmPermanent = true }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 4)
            }
        }.navigationTitle("最近削除した曲")
            .confirmationDialog("この音楽を完全に削除しますか？", isPresented: $confirmPermanent) {
                Button("完全に削除", role: .destructive) { if let permanent { library.permanentlyDelete(permanent) }; permanent = nil }
            } message: { Text("完全に削除すると、音の棚からは復元できません。") }
    }
}

struct MissingTracksView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var selected: Track?
    @State private var showPicker = false
    @State private var candidate: URL?
    @State private var confirmCandidate = false
    var body: some View {
        List {
            Section { Text("PCで移動・改名した音楽を指定し直せます。歌詞と編集情報は引き継ぎます。指定先が同じアプリ内なら、追加コピーは作りません。")
                    .font(.footnote).foregroundStyle(.secondary) }
            ForEach(library.tracks.filter { library.missingTrackIDs.contains($0.id) }) { track in
                Button { selected = track; showPicker = true } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                        Text(track.artist?.nonEmpty ?? "アーティスト未設定").font(.caption).foregroundStyle(.secondary)
                        Text("保存場所を指定").font(.caption)
                    }
                }
            }
            if library.missingTrackIDs.isEmpty { Text("すべての音楽が見つかっています") }
        }.navigationTitle("音楽の保存場所")
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.audio]) { outcome in
                switch outcome {
                case .success(let url): candidate = url; confirmCandidate = true
                case .failure(let error): library.message = error.localizedDescription
                }
            }
            .confirmationDialog("このファイルを使いますか？", isPresented: $confirmCandidate) {
                Button("このファイルを使う") {
                    if let track = selected, let url = candidate { Task { await library.relink(track.id, to: url) } }
                    candidate = nil
                }
            } message: { Text("選んだ音楽ファイルを、この曲の歌詞・編集情報に関連付けます。") }
    }
}
