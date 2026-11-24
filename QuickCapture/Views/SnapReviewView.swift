import SwiftUI

/// After a snap: the photo with its text outlined. Tap a paragraph to pick it, or
/// drag across lines to pick just those; with nothing picked, all of it is added.
/// A note written here goes under the passage, in your own words.
struct SnapReviewView: View {
    let photo: UIImage
    let page: TextLayout.Page
    var onRetake: () -> Void
    var onAdd: (_ passage: String, _ note: String) -> Void

    @State private var selected: Set<Int> = []
    /// While dragging: what was picked before the drag began, and the row it began on.
    @State private var dragStart: (selection: Set<Int>, row: Int)?
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                let frame = Self.fittedFrame(for: photo.size, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: photo)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(0.75)
                    outlines(in: frame)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(pickGesture(in: frame))
                .accessibilityElement()
                .accessibilityLabel("Photo of the text")
                .accessibilityValue(selected.isEmpty ? "Nothing picked" : "\(pickedParagraphCount) picked")
            }
            .clipped()

            bottomPanel
        }
        .background(Color.black.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: - Subviews

    /// The count of what's picked; Retake and Add sit at the bottom, within reach.
    private var topBar: some View {
        Text(selected.isEmpty ? "Pick Text" : "\(pickedParagraphCount) Picked")
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selected.isEmpty
                 ? "Tap a paragraph, or drag across lines, to pick just that text."
                 : "Tap a picked paragraph again to drop it.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            TextField("Add a note on this passage", text: $note, axis: .vertical)
                .lineLimit(1...5)
                .focused($noteFocused)
                .padding(12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .accessibilityIdentifier("snapNote")
            actionButtons
                .padding(.top, 4)
        }
        .padding()
        .background(Color(white: 0.1))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onRetake) {
                Label("Retake", systemImage: "camera.rotate")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.white.opacity(0.15), in: Capsule())
                    .contentShape(Capsule())
            }
            Button {
                onAdd(TextLayout.text(of: page, rows: selected.isEmpty ? nil : selected), note)
            } label: {
                Label(selected.isEmpty ? "Add All" : "Add", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(ContentView.snapColor.opacity(0.9), in: Capsule())
                    .contentShape(Capsule())
            }
        }
    }

    /// Each paragraph gets a faint outline; picked lines are filled yellow.
    private func outlines(in frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(page.paragraphs, id: \.lowerBound) { paragraph in
                let rect = Self.rect(of: paragraphBox(paragraph), in: frame).insetBy(dx: -4, dy: -3)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            ForEach(Array(selected), id: \.self) { row in
                let rect = Self.rect(of: page.rows[row].box, in: frame).insetBy(dx: -2, dy: -1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Picking

    private var pickedParagraphCount: Int {
        page.paragraphs.filter { $0.contains(where: selected.contains) }.count
    }

    /// A short touch toggles the paragraph under it; a drag picks every line from
    /// where it began to where the finger is, on top of what was already picked.
    private func pickGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard value.translation.magnitude > 10 else { return }
                noteFocused = false
                if dragStart == nil {
                    guard let row = row(at: value.startLocation, in: frame) else { return }
                    dragStart = (selected, row)
                }
                guard let start = dragStart, let row = row(at: value.location, in: frame) else { return }
                selected = start.selection.union(min(start.row, row)...max(start.row, row))
            }
            .onEnded { value in
                defer { dragStart = nil }
                guard dragStart == nil, value.translation.magnitude <= 10 else { return }
                noteFocused = false
                guard let row = row(at: value.location, in: frame),
                      let paragraph = page.paragraphs.first(where: { $0.contains(row) }) else { return }
                if paragraph.allSatisfy(selected.contains) {
                    selected.subtract(paragraph)
                } else {
                    selected.formUnion(paragraph)
                }
            }
    }

    /// The line nearest to `point`, if the point is beside the text.
    private func row(at point: CGPoint, in frame: CGRect) -> Int? {
        let rects = page.rows.map { Self.rect(of: $0.box, in: frame) }
        let lineHeight = rects.map(\.height).sorted().dropFirst(rects.count / 2).first ?? 20
        return rects.indices
            .filter { rects[$0].insetBy(dx: -40, dy: -lineHeight).contains(point) }
            .min { abs(rects[$0].midY - point.y) < abs(rects[$1].midY - point.y) }
    }

    private func paragraphBox(_ rows: Range<Int>) -> CGRect {
        rows.map { page.rows[$0].box }.reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: - Geometry

    /// Where an image of `imageSize` sits when fitted, centred, into `size`.
    static func fittedFrame(for imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    /// A Vision box (0–1, origin bottom-left) in the coordinates of `frame`.
    static func rect(of box: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + box.minX * frame.width,
               y: frame.minY + (1 - box.maxY) * frame.height,
               width: box.width * frame.width,
               height: box.height * frame.height)
    }
}

private extension CGSize {
    var magnitude: CGFloat { (width * width + height * height).squareRoot() }
}
