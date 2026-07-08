# Task 03: Swift Today decision cockpit

Branch: `codex/swift-today-decision-cockpit`

## Goal

Make SwiftUI consume the v0.3 `/v0/today` shape and show Today as a decision cockpit.

## Read first

```text
specs/today_decision_card_contract.md
specs/swift_implementation_contract.md
```

## Files to change

```text
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/AppState.swift
ui/macos/PharosApp/Sources/PharosApp/Views/TodayView.swift
```

## Exact implementation steps

1. Add `AttentionGroup`, `DecisionCard`, and `NoiseSummary` models.
2. Replace `TodaySnapshot` old fields with v0.3 fields:

```swift
needsDecision
needsInput
watching
handled
noise
```

3. Add `AppState.select(_ card: DecisionCard)`.
4. Update TodayView sections in exact order:
   - Needs Decision
   - Needs Input
   - Watching
   - Handled
   - Noise
5. Always render `Needs Decision` and `Needs Input`, with empty text if there are no cards.
6. Render `Watching` and `Handled` only if non-empty.
7. Render `Noise` summary if `noise.count > 0`.
8. `RequestRow` should become `DecisionCardRow` and show:
   - title
   - summary
   - why now
   - source kind
   - priority
   - risk
   - evidence count
   - prepared next move if present
9. Selecting a card loads detail by `requestId`.

## Do not change

1. Do not call `/v0/debug/today-internal` from Swift.
2. Do not display old top-level section names.
3. Do not move mapping logic into Swift.
4. Do not remove `WorkRequest` detail model.

## Commands

```bash
swift build --package-path ui/macos/PharosApp
```

If SwiftPM is unavailable, do static compile review and report it.

## Manual acceptance

1. Start core daemon from task 02.
2. Capture a manual request.
3. Open Swift app.
4. Today shows one card under `Needs Decision`.
5. Selecting the card opens detail.
6. No top-level `Needs Review`, `Running`, `Needs Context`, `New`, or `Done Today` section exists.

## Final response format

```text
Changed files:
Swift build:
Manual acceptance:
Known follow-up:
```
