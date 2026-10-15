import Foundation

struct SharedImportIssue: Identifiable, Codable {
    var id: String { path }
    let path: String
    let reason: String
    let details: String

    init(path: String, stage: String, url: URL, error: Error) {
        self.path = path
        let problem = error as NSError
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        reason = stage == "曲一覧の保存" ? "音楽を開けましたが、曲一覧を保存できませんでした。" :
            size == 0 ? "ファイルが空です。PCからの転送が完了しているか確認してください。" :
            "音楽ファイルを開けませんでした。ファイルの内容や転送状態の確認が必要です。"
        let sizeText = size.map { "\($0)バイト" } ?? "確認できません"
        var lines = ["処理：\(stage)", "サイズ：\(sizeText)", "詳細：\(problem.localizedDescription)",
                     "エラー：\(problem.domain)（\(problem.code)）"]
        if let underlying = problem.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("関連エラー：\(underlying.domain)（\(underlying.code)）\(underlying.localizedDescription)")
        }
        details = lines.joined(separator: "\n")
    }
}
