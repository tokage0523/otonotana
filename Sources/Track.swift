import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let filename: String
    var lyrics: [LyricLine]? = nil
    var artist: String? = nil
    var album: String? = nil
    var artworkFilename: String? = nil
    var favorite: Bool? = nil

    var isFavorite: Bool { favorite ?? false }
}
