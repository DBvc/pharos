import SwiftUI

struct RequestDetailView: View {
    @EnvironmentObject private var appState: AppState
    let detail: RequestDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                whatIsThis
                whyNow
                evidence
                preparedNextMove
                executionRecord
                auditDetails
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
                StatusBadge(text: detail.request.sourceKind.rawValue)
                StatusBadge(text: detail.request.priority.rawValue.uppercased())
                StatusBadge(text: detail.request.risk.label)
            }
            Text("Internal status: \(detail.request.status.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var whatIsThis: some View {
        Card(title: "What is this?") {
            Text(detail.request.summary)
            if let sourceLink {
                Link("Open source link", destination: sourceLink)
            }
        }
    }

    private var whyNow: some View {
        Card(title: "Why now?") {
            LabeledContent("Why Pharos brought this here", value: detail.request.reason)
            LabeledContent("Suggested next step", value: detail.request.nextStep)
        }
    }

    private var preparedNextMove: some View {
        Card(title: "Prepared next move") {
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
        Card(title: "Evidence used") {
            if detail.evidence.isEmpty {
                Text("No evidence yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.evidence) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline)
                        Text(item.kind)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private var executionRecord: some View {
        Card(title: "Execution record") {
            if detail.timeline.isEmpty {
                Text("No execution record yet.")
                    .foregroundStyle(.secondary)
            } else {
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

    private var auditDetails: some View {
        DisclosureGroup("Audit details") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("request id", value: detail.request.id)
                LabeledContent("internal status", value: detail.request.status.rawValue)
                ForEach(detail.actions) { action in
                    Divider()
                    LabeledContent("action id", value: action.id)
                    LabeledContent("payload_hash", value: action.payloadHash)
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sourceLink: URL? {
        for item in detail.evidence {
            if let url = item.url, let link = URL(string: url) {
                return link
            }
        }
        return nil
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
            }
            LabeledContent("Target system", value: action.targetKind)
            LabeledContent("Target object", value: action.targetRef)
            LabeledContent("External write", value: isLocalTarget ? "no" : "yes")
            LabeledContent("Risk", value: action.risk.label)
            TextEditor(text: $editedBody)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .onAppear { editedBody = action.body }
            HStack {
                Button(approveButtonTitle) {
                    Task { await appState.approve(action, executeAfterApproval: isLocalTarget) }
                }
                .disabled(isTerminal)

                Button("Edit and Approve") {
                    Task { await appState.editAndApprove(action, body: editedBody, executeAfterApproval: isLocalTarget) }
                }
                .disabled(isTerminal)

                Button("Reject", role: .destructive) {
                    Task { await appState.reject(action) }
                }
                .disabled(isTerminal)

                Spacer()
            }
            if !isLocalTarget {
                Text("External writeback is not implemented in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isLocalTarget: Bool {
        action.targetKind.hasPrefix("pharos.")
    }

    private var isTerminal: Bool {
        action.status == .executed || action.status == .rejected
    }

    private var approveButtonTitle: String {
        isLocalTarget ? "Approve and complete locally" : "Approve and send"
    }
}
