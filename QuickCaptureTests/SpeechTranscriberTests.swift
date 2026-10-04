import Testing
@testable import QuickCapture

struct SpeechTranscriberTests {
    @Test func combineJoinsSegmentsAndPartialWithSpaces() {
        #expect(SpeechTranscriber.combine(["Buy milk.", "Call mum."], partial: "Then the") ==
                "Buy milk. Call mum. Then the")
    }

    @Test func combineSkipsEmptyPieces() {
        #expect(SpeechTranscriber.combine(["", "  Hello "], partial: "") == "Hello")
        #expect(SpeechTranscriber.combine([], partial: "   ") == "")
    }

    @Test func combineKeepsEditedTextWhenRecordingMore() {
        #expect(SpeechTranscriber.combine(["Edited\nfirst part"], partial: "and more") ==
                "Edited\nfirst part and more")
    }
}
