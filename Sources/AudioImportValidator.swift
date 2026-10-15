import AVFoundation

enum AudioImportValidator {
    /// A file received over USB can be visible before the transfer completes.
    /// Retry temporary decode errors without converting or copying the audio.
    static func duration(at url: URL) async throws -> Double {
        for attempt in 0..<3 {
            do {
                return try await Task.detached(priority: .utility) {
                    let audio = try AVAudioPlayer(contentsOf: url)
                    guard audio.duration.isFinite, audio.duration > 0 else {
                        throw NSError(domain: "MusicImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "音楽の長さを読み取れませんでした。"])
                    }
                    return audio.duration
                }.value
            } catch {
                if attempt == 2 { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
            }
        }
        preconditionFailure("Retry loop must return or throw")
    }
}
