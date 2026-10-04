import SwiftUI

@main
struct QuickCaptureApp: App {
    @State private var store = QuickCaptureApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }

    /// UI tests launch with `-uiTesting` so they start empty and never touch real notes.
    private static func makeStore() -> CaptureStore {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else {
            return CaptureStore()
        }
        let url = URL.temporaryDirectory.appending(path: "uitest-capture.txt")
        try? FileManager.default.removeItem(at: url)
        return CaptureStore(fileURL: url)
    }
}
