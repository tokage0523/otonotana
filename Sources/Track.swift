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
    var albumArtist: String? = nil
    var trackNumber: Int? = nil
    var discNumber: Int? = nil
    var genre: String? = nil
    var releaseYear: Int? = nil
    var composer: String? = nil
    var notes: String? = nil
    var albumID: UUID? = nil
    var sharedPath: String? = nil
    var fileStamp: String? = nil
    var lyricsStamp: String? = nil
    var imageStamp: String? = nil
    var addedAt: Date? = nil
    var metadataVersion: Int? = nil

    var isFavorite: Bool { favorite ?? false }
}
