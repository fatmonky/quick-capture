import PhotosUI
import SwiftUI

/// Snap capture: scan a page (or pick a photo), extract its text,
/// let the user tidy it up, then append it to the text-space.
struct SnapCaptureView: View {
    private enum Phase {
        case scanning
        case choosingPhoto
        case recognizing
        case review
    }

    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = DocumentScanner.isSupported ? .scanning : .choosingPhoto
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch phase {
            case .scanning:
                DocumentScanner(
                    onFinish: { images in recognize(images) },
                    onCancel: { dismiss() },
                    onError: { error in
                        errorMessage = error.localizedDescription
                        phase = .choosingPhoto
                    }
                )
                .ignoresSafeArea()
            case .choosingPhoto:
                photoChooser
            case .recognizing:
                ProgressView("Reading text…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .review:
                reviewScreen
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - Screens

    private var photoChooser: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Snap Text", systemImage: "text.viewfinder")
            } description: {
                if let errorMessage {
                    Text(errorMessage)
                } else if !DocumentScanner.isSupported {
                    Text("The camera scanner isn't available on this device. Choose a photo of some text instead.")
                }
            } actions: {
                PhotosPicker("Choose from Photos", selection: $photoItem, matching: .images)
                    .buttonStyle(.borderedProminent)
                if DocumentScanner.isSupported {
                    Button("Scan with Camera") {
                        errorMessage = nil
                        phase = .scanning
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var reviewScreen: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if draft.isEmpty {
                    Text("No text found. Try again with the page flat and well lit.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
                TextEditor(text: $draft)
                    .padding(.horizontal, 12)
                Button(DocumentScanner.isSupported ? "Scan Again" : "Choose Another Photo",
                       systemImage: "arrow.counterclockwise") {
                    photoItem = nil
                    phase = DocumentScanner.isSupported ? .scanning : .choosingPhoto
                }
                .buttonStyle(.bordered)
                .padding()
            }
            .navigationTitle("Review Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.append(draft)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func recognize(_ images: [UIImage]) {
        phase = .recognizing
        Task {
            do {
                draft = try await TextRecognizer.recognize(images)
                phase = .review
            } catch {
                errorMessage = "Couldn't read text: \(error.localizedDescription)"
                phase = .choosingPhoto
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        phase = .recognizing
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't open that photo."
            phase = .choosingPhoto
            return
        }
        recognize([image])
    }
}
