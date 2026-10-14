import SwiftUI

@main
struct M4APlayerApp: App {
    @StateObject private var library = MusicLibrary()

    var body: some Scene {
        WindowGroup { RootView().environmentObject(library) }
    }
}
