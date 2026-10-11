import SwiftUI

@main
struct M4APlayerApp: App {
    @StateObject private var library = MusicLibrary()

    var body: some Scene {
        WindowGroup { LibraryView().environmentObject(library) }
    }
}
