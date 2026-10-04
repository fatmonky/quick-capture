import Foundation
import Testing
@testable import QuickCapture

@MainActor
struct CaptureStoreTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "CaptureStoreTests-\(UUID().uuidString).txt")

    @Test func appendToEmptyHasNoLeadingSeparator() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("First note")
        #expect(store.text == "First note")
    }

    @Test func appendSeparatesCapturesWithBlankLine() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("One")
        store.append("Two")
        store.append("Three")
        #expect(store.text == "One\n\nTwo\n\nThree")
    }

    @Test func appendTrimsWhitespace() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("  hello \n")
        store.append("\n world\n\n")
        #expect(store.text == "hello\n\nworld")
    }

    @Test func appendIgnoresEmptyAndWhitespaceInput() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("Keep")
        store.append("")
        store.append("   \n\t ")
        #expect(store.text == "Keep")
    }

    @Test func appendAfterManualEditWithTrailingNewlines() {
        let store = CaptureStore(fileURL: fileURL)
        store.text = "Typed by hand\n\n\n"
        store.append("Next")
        #expect(store.text == "Typed by hand\n\nNext")
    }

    @Test func persistenceRoundTrip() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("Line one\nLine two")
        store.append("Second capture")
        store.saveNow()

        let reloaded = CaptureStore(fileURL: fileURL)
        #expect(reloaded.text == "Line one\nLine two\n\nSecond capture")
    }

    @Test func clearEmptiesAndPersists() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("Something")
        store.saveNow()
        store.clear()
        store.saveNow()

        #expect(store.text.isEmpty)
        #expect(CaptureStore(fileURL: fileURL).text.isEmpty)
    }

    @Test func appendCountTracksOnlySuccessfulAppends() {
        let store = CaptureStore(fileURL: fileURL)
        store.append("One")
        store.append("   ")
        store.text += " edited by hand"
        store.append("Two")
        #expect(store.appendCount == 2)
    }

    @Test func missingFileStartsEmpty() {
        #expect(CaptureStore(fileURL: fileURL).text.isEmpty)
    }
}
