import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let timedLyrics = UTType(exportedAs: "com.example.M4APlayer.lrc", conformingTo: .plainText)
}

/// Let the system own the exported bytes throughout the Files save operation.
struct LyricsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.timedLyrics, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
