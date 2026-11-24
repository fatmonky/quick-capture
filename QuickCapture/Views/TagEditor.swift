import SwiftUI

/// A row of hashtags to tap, to add or take off.
struct TagBar: View {
    let tags: [String]
    let selected: [String]
    let tap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let isSelected = selected.contains(tag)
                    Button("#\(tag)") { tap(tag) }
                        .font(.subheadline)
                        .buttonStyle(.plain)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}

/// Types the note's hashtags, as in Article Saver, or taps ones used before, which
/// narrow to the matching ones while a tag is being typed.
struct TagEditor: View {
    let tags: [String]
    let save: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var used = NoteTags.used()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("#strategy #power", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(saveAndClose)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(.fill.tertiary, in: .capsule)
                    .padding(.horizontal)
                    .accessibilityIdentifier("tagField")
                suggestions
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndClose)
                }
            }
        }
        .presentationDetents([.fraction(0.3), .medium])
        .onAppear {
            text = tags.isEmpty ? "#" : NoteTags.display(tags) + " #"
            focused = true
        }
    }

    /// While a tag is being typed, the tags used before that match it; otherwise
    /// every tag used before, to add or take off with a tap.
    @ViewBuilder private var suggestions: some View {
        let fragment = NoteTags.fragment(in: text)
        let tags = NoteTags.suggestions(for: text, from: used)
        if let fragment, tags.isEmpty {
            Text("#\(fragment) will be a new tag")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .frame(minHeight: 36)
        } else if !tags.isEmpty {
            TagBar(tags: tags, selected: fragment == nil ? NoteTags.parse(text) : []) { tag in
                if fragment == nil {
                    toggle(tag)
                } else {
                    text = NoteTags.completing(text, with: tag)
                }
            }
        }
    }

    private func toggle(_ tag: String) {
        var tags = NoteTags.parse(text)
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
        text = tags.isEmpty ? "#" : NoteTags.display(tags) + " #"
    }

    private func saveAndClose() {
        let tags = NoteTags.parse(text)
        NoteTags.remember(tags.filter { !self.tags.contains($0) })
        save(tags)
        dismiss()
    }
}
