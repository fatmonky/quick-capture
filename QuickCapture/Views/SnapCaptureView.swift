import AVFoundation
import PhotosUI
import SwiftUI

/// Snap capture: point the camera at text (framed live with yellow brackets;
/// tap a block of text to frame just that) and tap Capture Text. The photo then
/// shows the text inside the brackets, to pick paragraphs or lines from and add a
/// note on. The passage goes on the page as a quote, with the note under it.
/// Falls back to picking a photo where live text isn't supported.
struct SnapCaptureView: View {
    private enum Phase {
        case scanning
        case choosingPhoto
        case recognizing
        case reviewing(UIImage, TextLayout.Page, retake: Retake)
    }

    /// Where Retake goes back to.
    private enum Retake {
        case camera, photos
    }

    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: Phase = LiveTextScannerController.isSupported ? .scanning : .choosingPhoto
    @State private var scannerController = LiveTextScannerController()
    @State private var cameraReady = false
    @State private var isCapturing = false
    /// Shown over the camera when a snap found no text.
    @State private var notice: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var offerSettings = false

    var body: some View {
        Group {
            switch phase {
            case .scanning:
                cameraScreen
            case .choosingPhoto:
                photoChooser
            case .recognizing:
                ProgressView("Reading text…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .reviewing(photo, page, retake):
                SnapReviewView(photo: photo, page: page) {
                    notice = nil
                    photoItem = nil
                    phase = retake == .camera ? .scanning : .choosingPhoto
                } onAdd: { passage, note in
                    store.append(NoteFormat.snap(passage: passage, note: note))
                    dismiss()
                }
                .preferredColorScheme(.dark)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - Screens

    private var cameraScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraReady {
                LiveTextScanner(controller: scannerController) { error in
                    showPhotoFallback("The camera isn't available: \(error.localizedDescription)")
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding()
        }
        .overlay(alignment: .top) {
            if let notice {
                Text(notice)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.top, 72)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if cameraReady {
                    Text(scannerController.isFocused
                         ? "Tap the text again to capture everything"
                         : "Tap a block of text to capture just that")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .allowsHitTesting(false)
                }
                shutterButton
            }
            .padding(.bottom, 24)
        }
        .sensoryFeedback(.selection, trigger: scannerController.focusedItemID)
        .task { await prepareCamera() }
    }

    private var shutterButton: some View {
        Button(action: snap) {
            Text("Capture Text")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .frame(minHeight: 56)
                .background(.blue, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .scaleEffect(isCapturing ? 0.94 : 1)
                .animation(.easeOut(duration: 0.15), value: isCapturing)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing || !cameraReady)
    }

    private var photoChooser: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Snap Text", systemImage: "text.viewfinder")
            } description: {
                if let errorMessage {
                    Text(errorMessage)
                } else if !LiveTextScannerController.isSupported {
                    Text("Live text scanning isn't available on this device. Choose a photo of some text instead.")
                }
            } actions: {
                PhotosPicker("Choose from Photos", selection: $photoItem, matching: .images)
                    .buttonStyle(.borderedProminent)
                if offerSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
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

    // MARK: - Actions

    private func prepareCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraReady = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                cameraReady = true
            } else {
                showCameraDenied()
            }
        default:
            showCameraDenied()
        }
    }

    private func showCameraDenied() {
        offerSettings = true
        showPhotoFallback("Camera access is turned off for Quick Capture. Turn it on in Settings, or choose a photo instead.")
    }

    private func showPhotoFallback(_ message: String) {
        errorMessage = message
        phase = .choosingPhoto
    }

    /// Captures a still and reads the bracketed part of it with full-accuracy OCR,
    /// then shows it to pick from. If that finds nothing, adds what the viewfinder
    /// was recognizing live inside the brackets.
    private func snap() {
        guard !isCapturing else { return }
        isCapturing = true
        notice = nil
        Task {
            defer { isCapturing = false }
            do {
                let photo = try await scannerController.capturePhoto()
                let region = scannerController.bracketedRegion(ofPhotoSized: photo.size)
                let liveText = scannerController.liveText
                phase = .recognizing
                let page = try await TextRecognizer.page(in: photo, within: region)
                if !page.isEmpty {
                    phase = .reviewing(photo, page, retake: .camera)
                } else if !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store.append(NoteFormat.snap(passage: liveText))
                    dismiss()
                } else {
                    withAnimation { notice = Self.noTextMessage }
                    phase = .scanning
                }
            } catch {
                showPhotoFallback("Couldn't read text: \(error.localizedDescription)")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        phase = .recognizing
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            showPhotoFallback("Couldn't open that photo.")
            return
        }
        do {
            let page = try await TextRecognizer.page(in: image, within: nil)
            if page.isEmpty {
                errorMessage = Self.noTextMessage
                photoItem = nil
                phase = .choosingPhoto
            } else {
                phase = .reviewing(image, page, retake: .photos)
            }
        } catch {
            showPhotoFallback("Couldn't read text: \(error.localizedDescription)")
        }
    }

    private static let noTextMessage = "No text found. Try again with the text in focus and well lit."
}
