import SwiftUI

/// Send the page's highlights to WhatsApp, as in Article Saver: the message, and
/// optionally the PDF, go to the share sheet in one share.
struct WhatsAppExportView: View {
    let page: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var attachPDF = false
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?

    private var message: WhatsAppMessage { WhatsAppFormatter.message(page: page, title: title) }

    var body: some View {
        let message = message
        NavigationStack {
            Form {
                Section {
                    Text(message.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("whatsappText")
                } header: {
                    Text("Message")
                } footer: {
                    Text(footer(message))
                }

                Section {
                    Toggle("Attach the notes as a PDF", isOn: pdfBinding(message))
                        .disabled(message.isTruncated)
                } footer: {
                    if message.isTruncated {
                        Text("The message is too long for WhatsApp, so it's cut short and the PDF goes with it.")
                    }
                }

                Section {
                    Button("Share to WhatsApp", systemImage: "square.and.arrow.up") { share(message) }
                } footer: {
                    Text("Quote briefly from books you share.")
                }
            }
            .navigationTitle("Send to WhatsApp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: item.items)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert("Couldn't make the PDF", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func footer(_ message: WhatsAppMessage) -> String {
        let count = "\(message.text.count.formatted()) characters."
        switch message.highlightCount {
        case 0: return "\(count) No highlights yet, so the snapped passages are used. Select text on the page and tap Highlight."
        case 1: return "\(count) 1 highlight."
        default: return "\(count) \(message.highlightCount) highlights."
        }
    }

    /// A cut-short message always takes the PDF along.
    private func pdfBinding(_ message: WhatsAppMessage) -> Binding<Bool> {
        Binding(get: { attachPDF || message.isTruncated }, set: { attachPDF = $0 })
    }

    private func share(_ message: WhatsAppMessage) {
        guard attachPDF || message.isTruncated else {
            shareItem = ShareItem(items: [message.text])
            return
        }
        do {
            shareItem = ShareItem(items: [message.text, try PDFExporter.temporaryFile(page: page, title: title)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
