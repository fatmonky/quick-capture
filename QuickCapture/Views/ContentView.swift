import SwiftUI
import UIKit

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
    @State private var snapping = false
    @State private var editingTags = false
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
                .fullScreenCover(isPresented: $snapping) {
                    SnapCaptureView()
                }
                .sheet(isPresented: $editingTags) {
                    TagEditor(tags: store.tags) { store.tags = $0 }
                }
                .sheet(item: $shareItem) { item in
                    ActivityView(items: item.items)
                        .presentationDetents([.medium, .large])
                        .ignoresSafeArea()
                }
                .sheet(isPresented: $showingWhatsApp) {
                    WhatsAppExportView(page: store.text, title: exportTitle, tags: store.tags)
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
        Text("Tap here to type, or use Snap to capture printed text.\nEverything you capture is added here.")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    /// The note's tags on the left (tap to change them), the counts on the right.
    private var countFooter: some View {
        let words = store.text.split(whereSeparator: \.isWhitespace).count
        return HStack(spacing: 12) {
            if !store.tags.isEmpty {
                Button(NoteTags.display(store.tags)) { editingTags = true }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .accessibilityLabel("Tags: \(NoteTags.display(store.tags))")
                    .accessibilityHint("Changes the note's tags")
            }
            Spacer(minLength: 0)
            Text("\(words) words · \(store.text.count) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// Snap is the main button, in the middle; tags and export sit just below it.
    private var captureBar: some View {
        VStack(spacing: 10) {
            Button {
                isEditing = false
                snapping = true
            } label: {
                Label("Snap", systemImage: "camera.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 300, minHeight: 60)
                    .background(Self.snapColor.opacity(0.9), in: Capsule())
                    .contentShape(Capsule())
            }

            HStack(spacing: 12) {
                Button { editingTags = true } label: {
                    Label("Tags", systemImage: "number")
                        .smallCapsule()
                }
                exportMenu
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    static let snapColor = Color(red: 1.0, green: 0.72, blue: 0.0) // amber

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
                .smallCapsule()
        }
        .disabled(store.text.isEmpty)
    }

    // MARK: - Actions

    private func export(to destination: ExportDestination) {
        switch destination {
        case .markdownFolder:
            saveToFolder()
        case .markdownFile:
            shareMarkdownFile(MarkdownFormatter.note(page: store.text, title: exportTitle, tags: store.tags))
        case .notes:
            shareItem = ShareItem(items: [RichTextFormatter.note(page: store.text, title: exportTitle, tags: store.tags)])
        case .pdf:
            do {
                shareItem = ShareItem(items: [try PDFExporter.temporaryFile(page: store.text, title: exportTitle, tags: store.tags)])
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
        let note = MarkdownFormatter.note(page: store.text, title: exportTitle, tags: store.tags)
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

private extension View {
    /// The look of the smaller buttons under Snap.
    func smallCapsule() -> some View {
        font(.subheadline.weight(.medium))
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(.fill.tertiary, in: Capsule())
            .contentShape(Capsule())
    }
}

#Preview {
    ContentView()
        .environment(CaptureStore(fileURL: URL.temporaryDirectory.appending(path: "preview.txt")))
}
