import SwiftUI

/// Quick typed capture: write a snippet, tap Add, and it's appended to the text-space.
struct TypeCaptureSheet: View {
    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isConfirmingDiscard = false
    @FocusState private var isFocused: Bool

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TextField("What do you want to capture?", text: $draft, axis: .vertical)
                .focused($isFocused)
                .lineLimit(3...)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Type")
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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", action: add)
                            .disabled(!hasContent)
                    }
                }
                .confirmationDialog(
                    "Discard this capture?",
                    isPresented: $isConfirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) { dismiss() }
                }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(hasContent)
        .onAppear { isFocused = true }
    }

    private func add() {
        store.append(draft)
        dismiss()
    }
}

#Preview {
    Text("Background")
        .sheet(isPresented: .constant(true)) {
            TypeCaptureSheet()
        }
        .environment(CaptureStore(fileURL: URL.temporaryDirectory.appending(path: "preview.txt")))
}
