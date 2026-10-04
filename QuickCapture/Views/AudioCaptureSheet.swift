import SwiftUI

/// Speak capture: live transcription while recording, then an editable
/// review before the text is appended to the text-space.
struct AudioCaptureSheet: View {
    private enum Phase: Equatable {
        case starting
        case recording
        case review
        case unavailable(message: String, offerSettings: Bool)
    }

    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var transcriber = SpeechTranscriber()
    @State private var phase: Phase = .starting
    @State private var draft = ""
    @State private var isConfirmingDiscard = false

    private var hasContent: Bool {
        let text = phase == .recording ? transcriber.transcript : draft
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Speak")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasContent {
                                isConfirmingDiscard = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                    if phase == .review {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                store.append(draft)
                                dismiss()
                            }
                            .disabled(!hasContent)
                        }
                    }
                }
                .confirmationDialog(
                    "Discard this recording?",
                    isPresented: $isConfirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) { dismiss() }
                }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(phase == .recording || hasContent)
        .task { await begin() }
        .onDisappear { transcriber.stop() }
        .onChange(of: transcriber.isRecording) { _, isRecording in
            // Recording ended by itself (e.g. an error): move to review with what we have.
            if !isRecording && phase == .recording {
                draft = transcriber.transcript
                phase = .review
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .starting:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .recording:
            recordingView
        case .review:
            reviewView
        case let .unavailable(message, offerSettings):
            ContentUnavailableView {
                Label("Can't Record", systemImage: "mic.slash")
            } description: {
                Text(message)
            } actions: {
                if offerSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var recordingView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if transcriber.transcript.isEmpty {
                            Text("Listening…").foregroundStyle(.secondary)
                        } else {
                            Text(transcriber.transcript)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("transcript")
                }
                .onChange(of: transcriber.transcript) {
                    proxy.scrollTo("transcript", anchor: .bottom)
                }
            }

            Button(action: stopRecording) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding()
            .overlay(alignment: .top) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .offset(y: -24)
                    .accessibilityHidden(true)
            }
        }
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            if let error = transcriber.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .top])
            }
            TextEditor(text: $draft)
                .padding(.horizontal, 12)
            Button("Record More", systemImage: "mic.fill", action: recordMore)
                .buttonStyle(.bordered)
                .padding()
        }
    }

    // MARK: - Actions

    private func begin() async {
        switch await transcriber.requestAuthorization() {
        case let .denied(message):
            phase = .unavailable(message: message, offerSettings: true)
        case .authorized:
            startRecording(continuing: "")
        }
    }

    private func startRecording(continuing existing: String) {
        transcriber.start(continuing: existing)
        if let error = transcriber.errorMessage {
            phase = existing.isEmpty ? .unavailable(message: error, offerSettings: false) : .review
        } else {
            phase = .recording
        }
    }

    private func stopRecording() {
        transcriber.stop()
        draft = transcriber.transcript
        phase = .review
    }

    private func recordMore() {
        startRecording(continuing: draft)
    }
}
