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

    /// Text and icon colour that reads on `color`.
    var labelColor: Color {
        switch self {
        case .speak: .white
        case .snap: .black
        }
    }
}

/// Where the page can be exported to.
enum ExportDestination: Identifiable {
    /// A Markdown note in the chosen folder, such as an Obsidian inbox.
    case markdownFolder
    /// A Markdown file, through the share sheet.
    case markdownFile
    /// Rich text for Apple Notes, through the share sheet.
    case notes
    /// An A4 PDF, through the share sheet.
    case pdf
    /// The highlights as a WhatsApp message.
    case whatsApp

    var id: Self { self }
}

struct ContentView: View {
    @Environment(CaptureStore.self) private var store
    @State private var activeCapture: CaptureMode?
    @State private var showCopied = false
    @State private var isEditing = false
    /// Waiting for a title before exporting.
    @State private var pendingExport: ExportDestination?
    @AppStorage("exportTitle") private var exportTitle = ""
    @State private var choosingFolder = false
    /// The folder is being chosen as part of saving, so save once it's chosen.
    @State private var saveAfterChoosingFolder = false
    @State private var shareItem: ShareItem?
    @State private var showingWhatsApp = false
    /// A note the folder wouldn't take, which can go through the share sheet instead.
    @State private var unsavedNote: MarkdownNote?
    @State private var savedMessage: String?
    @State private var errorMessage: String?

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
                .sheet(item: captureBinding(only: .speak)) { _ in
                    AudioCaptureSheet()
                }
                .fullScreenCover(item: captureBinding(only: .snap)) { _ in
                    SnapCaptureView()
                }
                .sheet(item: $shareItem) { item in
                    ActivityView(items: item.items)
                        .presentationDetents([.medium, .large])
                        .ignoresSafeArea()
                }
                .sheet(isPresented: $showingWhatsApp) {
                    WhatsAppExportView(page: store.text, title: exportTitle)
                }
                .alert("Title", isPresented: .constant(pendingExport != nil), presenting: pendingExport) { destination in
                    TextField("Book or topic", text: $exportTitle)
                    Button("Cancel", role: .cancel) { pendingExport = nil }
                    Button(destination == .markdownFolder ? "Save" : destination == .whatsApp ? "Next" : "Share") {
                        pendingExport = nil
                        export(to: destination)
                    }
                } message: { _ in
                    Text("Used as the note's heading and file name.")
                }
                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                    do {
                        try MarkdownFolder.remember(result.get())
                        if saveAfterChoosingFolder {
                            saveToFolder()
                        } else {
                            savedMessage = "Markdown notes will be saved to \(MarkdownFolder.current?.lastPathComponent ?? "that folder")"
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    saveAfterChoosingFolder = false
                }
                .alert("Couldn't save to the folder", isPresented: .constant(unsavedNote != nil), presenting: unsavedNote) { note in
                    Button("Share Instead") { shareMarkdownFile(note) }
                    Button("Cancel", role: .cancel) { unsavedNote = nil }
                } message: { _ in
                    Text("Share the note to another app, or choose the folder again from the Export menu.")
                }
                .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
                .overlay(alignment: .top) {
                    if let savedMessage {
                        Text(savedMessage)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: savedMessage)
                .sensoryFeedback(.success, trigger: savedMessage) { _, message in message != nil }
                .task(id: savedMessage) {
                    guard savedMessage != nil else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { savedMessage = nil }
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
                        .foregroundStyle(mode.labelColor)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(mode.color.opacity(0.9), in: Capsule())
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
                store.clear()
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

                exportMenu
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button(MarkdownFolder.current.map { "Save to \($0.lastPathComponent)" } ?? "Save as Markdown",
                   systemImage: "folder") {
                pendingExport = .markdownFolder
            }
            Button("Share Markdown File", systemImage: "doc.text") { pendingExport = .markdownFile }
            Button("Share to Notes", systemImage: "note.text") { pendingExport = .notes }
            Button("Share PDF", systemImage: "doc.richtext") { pendingExport = .pdf }
            Button("Send to WhatsApp", systemImage: "message") { pendingExport = .whatsApp }
            Divider()
            Button("Choose Markdown Folder…", systemImage: "folder.badge.gearshape") { choosingFolder = true }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(store.text.isEmpty)
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

    private func export(to destination: ExportDestination) {
        switch destination {
        case .markdownFolder:
            saveToFolder()
        case .markdownFile:
            shareMarkdownFile(MarkdownFormatter.note(page: store.text, title: exportTitle))
        case .notes:
            shareItem = ShareItem(items: [RichTextFormatter.note(page: store.text, title: exportTitle)])
        case .pdf:
            do {
                shareItem = ShareItem(items: [try PDFExporter.temporaryFile(page: store.text, title: exportTitle)])
            } catch {
                errorMessage = error.localizedDescription
            }
        case .whatsApp:
            showingWhatsApp = true
        }
    }

    /// Adds the page to the Markdown folder as a new note, asking for the folder the first time.
    private func saveToFolder() {
        guard let folder = MarkdownFolder.current else {
            saveAfterChoosingFolder = true
            choosingFolder = true
            return
        }
        let note = MarkdownFormatter.note(page: store.text, title: exportTitle)
        Task {
            do {
                // Another app's folder can take a while to answer.
                try await Task.detached { try MarkdownFolder.save(note, in: folder) }.value
                savedMessage = "Saved to \(folder.lastPathComponent)"
            } catch {
                unsavedNote = note
            }
        }
    }

    private func shareMarkdownFile(_ note: MarkdownNote) {
        unsavedNote = nil
        do {
            shareItem = ShareItem(items: [try MarkdownFolder.temporaryFile(for: note)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
