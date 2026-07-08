# Swift Implementation Contract for v0.3 Today

Apply in task 03, after the OCaml `/v0/today` shape has changed.

## Files to edit

```text
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/AppState.swift
ui/macos/PharosApp/Sources/PharosApp/Views/TodayView.swift
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift  # only if row selection signatures need cleanup
```

## Model changes

Replace the old `TodaySnapshot` fields with:

```swift
enum AttentionGroup: String, Codable {
    case needsDecision = "needs_decision"
    case needsInput = "needs_input"
    case watching
    case handled
    case noise

    var label: String {
        switch self {
        case .needsDecision: return "Needs Decision"
        case .needsInput: return "Needs Input"
        case .watching: return "Watching"
        case .handled: return "Handled"
        case .noise: return "Noise"
        }
    }
}

struct DecisionCard: Identifiable, Codable, Hashable {
    let requestId: String
    let title: String
    let summary: String
    let group: AttentionGroup
    let sourceKind: SourceKind
    let sourceUrl: String?
    let priority: Priority
    let risk: Risk
    let whyNow: String
    let preparedNextMove: String?
    let targetPreview: String?
    let evidenceCount: Int
    let updatedAt: String
    let debugStatus: RequestStatus

    var id: String { requestId }
}

struct NoiseSummary: Codable, Hashable {
    let count: Int
}

struct TodaySnapshot: Codable {
    let needsDecision: [DecisionCard]
    let needsInput: [DecisionCard]
    let watching: [DecisionCard]
    let handled: [DecisionCard]
    let noise: NoiseSummary
}
```

Keep `WorkRequest`, `ProposedAction`, `EvidenceItem`, `TimelineEvent`, and `RequestDetail` as-is because detail still uses internal entities.

## AppState changes

Add:

```swift
func select(_ card: DecisionCard) async {
    selectedRequestId = card.requestId
    await loadDetail(id: card.requestId)
}
```

Keep existing `select(_ request: WorkRequest)` only if other views still call it.

## TodayView changes

Use these top-level sections in this order:

1. `Needs Decision`
2. `Needs Input`
3. `Watching`
4. `Handled`
5. `Noise`

Do not display these old section names as top-level sections:

```text
Needs Review
Running
Needs Context
New
Done Today
```

Required section behavior:

1. Always render `Needs Decision` and `Needs Input` sections, even when empty, with a small empty-state row.
2. Render `Watching` and `Handled` only when non-empty.
3. Render `Noise` as a summary row if `snapshot.noise.count > 0`.
4. Selecting a card loads `/v0/requests/:request_id`.

## DecisionCard row content

Each row must show:

1. `card.title`
2. `card.summary`
3. `card.whyNow` labeled or visually secondary
4. badges for `priority`, `risk`, and `sourceKind`
5. evidence count, e.g. `3 evidence`
6. optional prepared next move when present

Do not show `debugStatus` as the primary status badge. If shown, it must be secondary or inside an audit/debug area.

## Acceptance

```bash
swift build --package-path ui/macos/PharosApp
```

Manual app acceptance:

1. Start `pharosd`.
2. Capture one manual request.
3. Today shows it under `Needs Decision`.
4. There is no top-level `Needs Review` section.
5. Clicking the card loads Request Detail.
