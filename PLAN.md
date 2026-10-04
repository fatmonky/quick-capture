# Plan: Recreate Quick Capture (iOS, SwiftUI)

## Context
Quick Capture was an iOS app for fast note-taking. It had one text-space, and three ways to add text to it: **typing**, **audio** (speech → text), and **snap** (camera → OCR text). Each capture is **appended** to the text-space, and the text-space can be **exported to Apple Notes**. The repo (`quick-capture`) is empty, so we start from scratch.

Decisions confirmed with the user:
- Native **SwiftUI** app (Xcode 26.3 / Swift 6.2 are installed).
- Export to Notes goes through the **iOS share sheet**. Apple has no public API for writing to Notes.
- The text-space is **kept** after export. The user clears it manually.
- Audio uses **live transcription** that runs on-device.

Target: iOS 18+, iPhone only, portrait-first. No third-party dependencies.

## Architecture
```
QuickCapture/
  QuickCaptureApp.swift        // @main, injects CaptureStore
  Model/CaptureStore.swift     // @Observable: text, append(_:source:), clear(), persistence
  Views/ContentView.swift      // text-space (TextEditor) + bottom capture bar + toolbar
  Views/TypeCaptureSheet.swift // focused TextField sheet → append
  Views/AudioCaptureSheet.swift// live transcript view, Done/Cancel
  Views/SnapCaptureView.swift  // document camera → OCR → review/edit sheet → append
  Services/SpeechTranscriber.swift // AVAudioEngine + SFSpeechRecognizer (on-device)
  Services/TextRecognizer.swift    // Vision VNRecognizeTextRequest wrapper (async)
  Support/ShareSheet.swift     // ShareLink / UIActivityViewController wrapper
  Info.plist                   // usage descriptions
QuickCaptureTests/CaptureStoreTests.swift
```

### Core: `CaptureStore`
- `@Observable` class that holds `text: String`.
- `append(_ snippet: String)` trims whitespace and ignores empty input. It joins onto existing text with a blank-line separator (`"\n\n"`). An optional setting can add a timestamp header to each capture.
- Persists to `Documents/capture.txt`: debounced write on change, load on launch. The user should never lose text, so a plain file is safer and simpler than SwiftData for one document.
- `clear()` asks for confirmation first.

### Main screen (`ContentView`)
- A full-height editable `TextEditor` bound to `store.text`, so the user can fix any capture by hand.
- A bottom bar with three large buttons: **Type**, **Speak**, **Snap**. Each opens its own capture flow as a sheet or full-screen cover.
- Toolbar: **Export** (`ShareLink(item: store.text)`, where Notes appears as a share target), **Copy**, **Clear**.
- Character and word count footer (optional, nice-to-have).

### 1. Type
- A sheet with an auto-focused multiline `TextField`. **Add** appends and dismisses.
- This is quicker than scrolling the main editor, and it keeps the "capture then append" model the same across all three modes.

### 2. Audio (live)
- `SpeechTranscriber`:
  - Uses `AVAudioEngine` input tap → `SFSpeechAudioBufferRecognitionRequest`, with `shouldReportPartialResults = true` and `requiresOnDeviceRecognition = true` when supported.
  - Publishes `transcript` and `isRecording`.
  - Works around the ~1-minute recognition-task limit: when a task finishes, it starts a new one and concatenates the results.
- The sheet shows the live transcript and a pulsing mic. **Done** stops recording, then appends the transcript (editable before confirming). **Cancel** discards it.
- Permissions: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`. If access is denied, the sheet links to Settings.
- Possible upgrade later: iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` API for long-form dictation, behind `if #available(iOS 26, *)`.

### 3. Snap (camera → text)
- Uses `VNDocumentCameraViewController` (VisionKit), wrapped in `UIViewControllerRepresentable`. It gives auto edge detection and perspective correction, which suits book and paper pages, and it supports multi-page scans.
- `TextRecognizer.recognize(images:) async -> String` runs `VNRecognizeTextRequest` with `.accurate`, language correction on, and `automaticallyDetectsLanguage`. It joins lines in reading order and pages with blank lines.
- A review sheet shows the extracted text in a `TextEditor` so the user can trim or fix it. **Add** appends.
- Permission: `NSCameraUsageDescription`.
- Optional: a **"From Photos"** source (`PhotosPicker`) that sends the image through the same recognizer.

### Export to Apple Notes
- `ShareLink(item: store.text, subject: Text("Quick Capture"))`. The user picks Notes and can choose a new or existing note in the Notes share extension.
- The text-space is kept after sharing, as decided.

## Build steps (in order)
1. **Project setup.** Create the Xcode project. Use `xcodegen` with a `project.yml` if it's installed (reproducible from the CLI). Otherwise use Xcode's iOS App template, saved into this repo. Add `.gitignore` and Info.plist usage strings.
2. `CaptureStore` + persistence + unit tests.
3. `ContentView` with editor, capture bar, and Export/Copy/Clear.
4. Type capture sheet.
5. Snap: document camera + `TextRecognizer` + review sheet.
6. Audio: `SpeechTranscriber` + live sheet + permission handling.
7. Polish: haptics on append, scroll to the end after an append, app icon, empty-state hint, dark mode check.
8. Commit after each step on a feature branch.

## Verification
- **Unit tests** (`xcodebuild test -scheme QuickCapture -destination 'platform=iOS Simulator,name=iPhone 17'`): append separator logic, empty/whitespace input ignored, persistence round-trip, clear.
- **Simulator**: Type flow, editing, persistence after relaunch, and the share sheet (Notes isn't on the simulator, but the share sheet still shows). OCR can be tested in the simulator through a Photos-import path using a sample image.
- **Physical iPhone** (needed for the camera, plus mic quality): scan a book page and check the extracted text is accurate. Dictate for 2+ minutes to check the restart logic. Export to Notes and confirm the note has the full text with line breaks intact. This needs a free Apple ID signing team in Xcode.
