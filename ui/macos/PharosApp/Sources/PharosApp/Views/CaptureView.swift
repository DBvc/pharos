import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Capture")
                .font(.title.bold())
            TextField("Optional title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Optional source URL", text: $url)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $bodyText)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Capture") {
                    Task { await appState.capture(title: title, body: bodyText, url: url) }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
