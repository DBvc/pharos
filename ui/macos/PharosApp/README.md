# PharosApp

SwiftUI starter shell for the Pharos macOS cockpit.

## Run

1. Start the OCaml daemon from the repository root:

```bash
./scripts/run-core.sh
```

2. Open this package in Xcode:

```bash
open Package.swift
```

3. Run the `PharosApp` executable target.

## Current scope

- Today list.
- Request detail.
- Manual quick capture.
- Approve, reject, execute local action.
- Placeholder pages for Sources, Rules, and Metrics.

The app intentionally keeps business logic thin. It talks to the core local API and should not contain policy or adapter writeback logic.
