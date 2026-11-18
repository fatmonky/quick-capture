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

struct SpeechTranscriberRevisionTests {
    @Test func growingResultIsARevision() {
        #expect(SpeechTranscriber.isRevision(of: "Does this", by: "Does this override?",
                                             previousEndedUtterance: false))
    }

    @Test func rewordedResultIsARevision() {
        #expect(SpeechTranscriber.isRevision(of: "Does this override?", by: "Does this overwrite?",
                                             previousEndedUtterance: false))
    }

    @Test func resultStartingOverAfterAPauseIsNotARevision() {
        #expect(!SpeechTranscriber.isRevision(of: "Buy milk and eggs", by: "Call mum",
                                              previousEndedUtterance: false))
    }

    @Test func anyNewWordsAfterAnEndedUtteranceStartANewOne() {
        #expect(!SpeechTranscriber.isRevision(of: "Whether", by: "Does this override?",
                                              previousEndedUtterance: true))
    }

    @Test func endedUtteranceThatKeepsGrowingIsStillARevision() {
        #expect(SpeechTranscriber.isRevision(of: "Hello", by: "Hello there",
                                             previousEndedUtterance: true))
    }

    @Test func shortResultCanBeReworded() {
        #expect(SpeechTranscriber.isRevision(of: "Weather", by: "Whether it",
                                             previousEndedUtterance: false))
    }

    @Test func firstResultIsAlwaysTaken() {
        #expect(SpeechTranscriber.isRevision(of: "", by: "Anything",
                                             previousEndedUtterance: true))
    }
}
