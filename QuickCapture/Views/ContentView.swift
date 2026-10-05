import SwiftUI
import UIKit

/// The ways to add text to the text-space (besides typing into it directly).
enum CaptureMode: String, Identifiable, CaseIterable {
    case speak, snap

    var id: Self { self }

    var title: String {
        switch self {
        case .speak: "Speak"
        case .snap: "Snap"
        }
    }

    var systemImage: String {
        switch self {
        case .speak: "mic.fill"
        case .snap: "camera.fill"
        }
    }

    var color: Color {
        switch self {
        case .speak: .red
        case .snap: Color(red: 1.0, green: 0.72, blue: 0.0) // amber
        }
    }
}

struct ContentView: View {
    @Environment(CaptureStore.self) private var store
    @State private var activeCapture: CaptureMode?
    @State private var isConfirmingClear = false
    @State private var showCopied = false
    @State private var isEditing = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            CaptureTextView(text: $store.text, isEditing: $isEditing,
                            scrollToEndTrigger: store.appendCount)
                .overlay(alignment: .topLeading) {
                    if store.text.isEmpty && !isEditing {
                        emptyStateHint
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        countFooter
                        captureBar
                    }
                    .background(.bar)
                }
                .navigationTitle("Quick Capture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sensoryFeedback(.success, trigger: store.appendCount)
                .confirmationDialog(
                    "Clear all captured text?",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("Clear", role: .destructive) { store.clear() }
                } message: {
                    Text("This can't be undone.")
                }
                .sheet(item: captureBinding(only: .speak)) { _ in
                    AudioCaptureSheet()
                }
                .fullScreenCover(item: captureBinding(only: .snap)) { _ in
                    SnapCaptureView()
                }
        }
    }

    // MARK: - Subviews

    private var emptyStateHint: some View {
        Text("Tap here to type, or use Speak or Snap to capture text.\nEverything you capture is added here.")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    private var countFooter: some View {
        let words = store.text.split(whereSeparator: \.isWhitespace).count
        return HStack {
            Spacer()
            Text("\(words) words · \(store.text.count) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var captureBar: some View {
        HStack(spacing: 12) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    isEditing = false
                    activeCapture = mode
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.headline)
                        .foregroundStyle(mode.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(mode.color.opacity(0.2), in: Capsule())
                        .contentShape(Capsule())
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Clear", systemImage: "trash", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(store.text.isEmpty)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isEditing {
                Button("Done") { isEditing = false }
                    .fontWeight(.semibold)
            } else {
                Button(showCopied ? "Copied" : "Copy",
                       systemImage: showCopied ? "checkmark" : "doc.on.doc") {
                    copyAll()
                }
                .disabled(store.text.isEmpty)

                ShareLink(item: store.text, subject: Text("Quick Capture")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(store.text.isEmpty)
            }
        }
    }

    // MARK: - Presentation

    /// Snap runs full screen (it hosts the camera); Speak is a sheet.
    private func captureBinding(only mode: CaptureMode) -> Binding<CaptureMode?> {
        Binding(
            get: { activeCapture == mode ? mode : nil },
            set: { activeCapture = $0 }
        )
    }

    // MARK: - Actions

    private func copyAll() {
        UIPasteboard.general.string = store.text
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }
}

#Preview {
    ContentView()
        .environment(CaptureStore(fileURL: URL.temporaryDirectory.appending(path: "preview.txt")))
}
