import SwiftUI

@main
struct QuickCaptureApp: App {
    @State private var store = QuickCaptureApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await appendTestCapture() }
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
        let store = CaptureStore(fileURL: url)
        if let seed = ProcessInfo.processInfo.environment["UITEST_SEED_TEXT"] {
            store.text = seed
        }
        return store
    }

    /// UI tests can pass `UITEST_APPEND_TEXT` to have a capture appended once the
    /// main screen is showing, standing in for a Speak or Snap capture.
    private func appendTestCapture() async {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              let snippet = ProcessInfo.processInfo.environment["UITEST_APPEND_TEXT"] else { return }
        try? await Task.sleep(for: .seconds(1))
        store.append(snippet)
    }
}
