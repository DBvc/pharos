import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedRequestId) {
                if let snapshot = appState.snapshot {
                    DecisionSection(title: AttentionGroup.needsDecision.label, cards: snapshot.needsDecision, emptyText: "No decisions waiting.")
                    DecisionSection(title: AttentionGroup.needsInput.label, cards: snapshot.needsInput, emptyText: "No input needed.")
                    if !snapshot.watching.isEmpty {
                        DecisionSection(title: AttentionGroup.watching.label, cards: snapshot.watching)
                    }
                    if !snapshot.handled.isEmpty {
                        DecisionSection(title: AttentionGroup.handled.label, cards: snapshot.handled)
                    }
                    if snapshot.noise.count > 0 {
                        Section(AttentionGroup.noise.label) {
                            NoiseSummaryRow(count: snapshot.noise.count)
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

private struct DecisionSection: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let cards: [DecisionCard]
    var emptyText: String?

    var body: some View {
        Section(title) {
            if cards.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(cards) { card in
                    DecisionCardRow(card: card)
                        .tag(card.requestId)
                        .onTapGesture { Task { await appState.select(card) } }
                }
            }
        }
    }
}

private struct DecisionCardRow: View {
    let card: DecisionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.headline)
                .lineLimit(2)
            Text(card.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(card.whyNow)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let preparedNextMove = card.preparedNextMove, !preparedNextMove.isEmpty {
                Text(preparedNextMove)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                StatusBadge(text: card.priority.rawValue.uppercased())
                StatusBadge(text: card.risk.label)
                StatusBadge(text: card.sourceKind.rawValue)
                Spacer()
                Text("\(card.evidenceCount) evidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NoiseSummaryRow: View {
    let count: Int

    var body: some View {
        HStack {
            Text("\(count) archived as noise")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
