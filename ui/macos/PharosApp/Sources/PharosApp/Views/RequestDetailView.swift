import SwiftUI

struct RequestDetailView: View {
    @EnvironmentObject private var appState: AppState
    let detail: RequestDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summary
                actions
                evidence
                timeline
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Request Detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.request.title)
                .font(.largeTitle.bold())
            HStack {
                StatusBadge(text: detail.request.status.label)
                StatusBadge(text: detail.request.priority.rawValue.uppercased())
                StatusBadge(text: detail.request.risk.label)
                StatusBadge(text: detail.request.sourceKind.rawValue)
            }
        }
    }

    private var summary: some View {
        Card(title: "Summary") {
            Text(detail.request.summary)
            Divider()
            LabeledContent("Entry reason", value: detail.request.reason)
            LabeledContent("Next step", value: detail.request.nextStep)
        }
    }

    private var actions: some View {
        Card(title: "Proposed Actions") {
            if detail.actions.isEmpty {
                Text("No actions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.actions) { action in
                    ProposedActionView(action: action)
                    if action.id != detail.actions.last?.id { Divider() }
                }
            }
        }
    }

    private var evidence: some View {
        Card(title: "Evidence") {
            if detail.evidence.isEmpty {
                Text("No evidence yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.evidence) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text(item.body).font(.body)
                        if let url = item.url, let link = URL(string: url) {
                            Link("Open source", destination: link)
                        }
                    }
                    if item.id != detail.evidence.last?.id { Divider() }
                }
            }
        }
    }

    private var timeline: some View {
        Card(title: "Timeline") {
            ForEach(detail.timeline) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.title).font(.headline)
                        Spacer()
                        Text(event.createdAt).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.body).font(.callout)
                    Text(event.kind).font(.caption2).foregroundStyle(.secondary)
                }
                if event.id != detail.timeline.last?.id { Divider() }
            }
        }
    }
}

struct ProposedActionView: View {
    @EnvironmentObject private var appState: AppState
    let action: ProposedAction
    @State private var editedBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.title).font(.headline)
                Spacer()
                StatusBadge(text: action.status.rawValue.uppercased())
                StatusBadge(text: action.risk.label)
            }
            LabeledContent("Target", value: "\(action.targetKind) / \(action.targetRef)")
            TextEditor(text: $editedBody)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .onAppear { editedBody = action.body }
            HStack {
                Button("Approve") {
                    Task { await appState.approve(action) }
                }
                .disabled(action.status == .executed || action.status == .rejected)

                Button("Edit and Approve") {
                    Task { await appState.editAndApprove(action, body: editedBody) }
                }
                .disabled(action.status == .executed || action.status == .rejected)

                Button("Reject", role: .destructive) {
                    Task { await appState.reject(action) }
                }
                .disabled(action.status == .executed || action.status == .rejected)

                Spacer()
                Text(action.payloadHash)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
