import AVFoundation
import PhotosUI
import SwiftUI

/// Snap capture: point the camera at text (framed live with yellow brackets),
/// tap Capture Text, and the extracted text is added straight to the text-space,
/// where it can be edited. Falls back to picking a photo where live text isn't supported.
struct SnapCaptureView: View {
    private enum Phase {
        case scanning
        case choosingPhoto
        case recognizing
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
            shutterButton
                .padding(.bottom, 24)
        }
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

    /// Captures a still and reads it with full-accuracy OCR. If that finds
    /// nothing, falls back to whatever the viewfinder was recognizing live.
    private func snap() {
        guard !isCapturing else { return }
        isCapturing = true
        notice = nil
        Task {
            defer { isCapturing = false }
            do {
                let photo = try await scannerController.capturePhoto()
                let liveText = scannerController.liveText
                phase = .recognizing
                let text = try await TextRecognizer.recognize([photo])
                add(text.isEmpty ? liveText : text, retryPhase: .scanning)
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
            add(try await TextRecognizer.recognize([image]), retryPhase: .choosingPhoto)
        } catch {
            showPhotoFallback("Couldn't read text: \(error.localizedDescription)")
        }
    }

    /// Adds the recognized text to the text-space and closes Snap. If nothing
    /// was found, stays in Snap so the user can try again.
    private func add(_ text: String, retryPhase: Phase) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = "No text found. Try again with the text in focus and well lit."
            if retryPhase == .scanning {
                withAnimation { notice = message }
            } else {
                errorMessage = message
                photoItem = nil
            }
            phase = retryPhase
            return
        }
        store.append(text)
        dismiss()
    }
}
