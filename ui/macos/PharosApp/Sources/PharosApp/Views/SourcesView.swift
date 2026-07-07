import SwiftUI

struct SourcesView: View {
    private let sources: [SourceStub] = [
        SourceStub(name: "Feishu Chat", detail: "Read configured chats, mentions, threads, and forwarded messages."),
        SourceStub(name: "Feishu Project", detail: "Read assigned items, comments, blockers, and status changes."),
        SourceStub(name: "GitLab", detail: "Read review requests, mentions, issues, discussions, and pipeline status."),
        SourceStub(name: "Feishu Docs", detail: "Read document comments, mentions, and linked context paragraphs.")
    ]

    var body: some View {
        List {
            Section("P0 Sources") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(source.name).font(.headline)
                            Spacer()
                            StatusBadge(text: "STUB")
                        }
                        Text(source.detail).foregroundStyle(.secondary)
                        Text("Write permission defaults to off. L3 actions must still pass Review Gate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Sources")
    }
}

private struct SourceStub: Identifiable {
    var id: String { name }
    let name: String
    let detail: String
}
