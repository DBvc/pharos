import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedRequestId) {
                if let snapshot = appState.snapshot {
                    Section("Needs Review") {
                        ForEach(snapshot.needsReview) { request in
                            RequestRow(request: request)
                                .tag(request.id)
                                .onTapGesture { Task { await appState.select(request) } }
                        }
                    }
                    Section("Running") {
                        ForEach(snapshot.running) { request in
                            RequestRow(request: request)
                                .tag(request.id)
                                .onTapGesture { Task { await appState.select(request) } }
                        }
                    }
                    Section("Needs Context") {
                        ForEach(snapshot.needsContext) { request in
                            RequestRow(request: request)
                                .tag(request.id)
                                .onTapGesture { Task { await appState.select(request) } }
                        }
                    }
                    Section("New") {
                        ForEach(snapshot.newItems) { request in
                            RequestRow(request: request)
                                .tag(request.id)
                                .onTapGesture { Task { await appState.select(request) } }
                        }
                    }
                    Section("Done Today") {
                        ForEach(snapshot.doneToday) { request in
                            RequestRow(request: request)
                                .tag(request.id)
                                .onTapGesture { Task { await appState.select(request) } }
                        }
                    }
                } else if appState.isLoading {
                    ProgressView("Loading Today")
                } else {
                    EmptyStateView(title: "No data", systemImage: "tray", message: "Start pharosd, then capture a request.")
                }
            }
            .navigationTitle("Today")
        } detail: {
            if let detail = appState.selectedDetail {
                RequestDetailView(detail: detail)
            } else {
                EmptyStateView(title: "Select a request", systemImage: "doc.text.magnifyingglass", message: "Pick a card from Today to inspect evidence, timeline, and proposed actions.")
            }
        }
    }
}

struct RequestRow: View {
    let request: WorkRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.title)
                .font(.headline)
                .lineLimit(2)
            Text(request.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                StatusBadge(text: request.status.label)
                StatusBadge(text: request.priority.rawValue.uppercased())
                StatusBadge(text: request.risk.label)
                Spacer()
                Text(request.sourceKind.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
