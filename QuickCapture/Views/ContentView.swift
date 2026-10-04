import SwiftUI
import UIKit

/// The three ways to add text to the text-space.
enum CaptureMode: String, Identifiable, CaseIterable {
    case type, speak, snap

    var id: Self { self }

    var title: String {
        switch self {
        case .type: "Type"
        case .speak: "Speak"
        case .snap: "Snap"
        }
    }

    var systemImage: String {
        switch self {
        case .type: "keyboard"
        case .speak: "mic.fill"
        case .snap: "camera.fill"
        }
    }
}

struct ContentView: View {
    @Environment(CaptureStore.self) private var store
    @State private var activeCapture: CaptureMode?
    @State private var isConfirmingClear = false
    @State private var showCopied = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            TextEditor(text: $store.text)
                .focused($editorFocused)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if store.text.isEmpty && !editorFocused {
                        emptyStateHint
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        countFooter
                        captureBar
                    }
                }
                .navigationTitle("Quick Capture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationDialog(
                    "Clear all captured text?",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("Clear", role: .destructive) { store.clear() }
                } message: {
                    Text("This can't be undone.")
                }
                .sheet(item: captureBinding(excluding: .snap)) { mode in
                    switch mode {
                    case .type:
                        TypeCaptureSheet()
                    case .speak, .snap:
                        CapturePlaceholderSheet(mode: mode)
                    }
                }
                .fullScreenCover(item: captureBinding(only: .snap)) { _ in
                    SnapCaptureView()
                }
        }
    }

    // MARK: - Subviews

    private var emptyStateHint: some View {
        Text("Tap Type, Speak or Snap to capture text.\nEverything you capture is added here.")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 17)
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
                    editorFocused = false
                    activeCapture = mode
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .labelStyle(.verticalCapture)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
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
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { editorFocused = false }
        }
    }

    // MARK: - Presentation

    /// Snap runs full screen (it hosts the camera); the other captures are sheets.
    private func captureBinding(only mode: CaptureMode) -> Binding<CaptureMode?> {
        Binding(
            get: { activeCapture == mode ? mode : nil },
            set: { activeCapture = $0 }
        )
    }

    private func captureBinding(excluding mode: CaptureMode) -> Binding<CaptureMode?> {
        Binding(
            get: { activeCapture == mode ? nil : activeCapture },
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

/// Icon above title, used for the large capture buttons.
struct VerticalCaptureLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.font(.title3).frame(height: 26)
            configuration.title.font(.subheadline.weight(.semibold))
        }
    }
}

extension LabelStyle where Self == VerticalCaptureLabelStyle {
    static var verticalCapture: Self { .init() }
}

/// Stand-in until each capture flow is built (step 6).
private struct CapturePlaceholderSheet: View {
    let mode: CaptureMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "\(mode.title) capture",
                systemImage: mode.systemImage,
                description: Text("Coming soon.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
        .environment(CaptureStore(fileURL: URL.temporaryDirectory.appending(path: "preview.txt")))
}
