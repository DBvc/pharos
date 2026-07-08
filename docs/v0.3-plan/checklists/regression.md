# Regression Checklist

Run this after each Codex task when feasible.

## Core build

```bash
cd core && dune build
cd core && dune runtest
```

## Swift build

```bash
swift build --package-path ui/macos/PharosApp
```

## M0 manual flow

```bash
rm -f var/regression.sqlite
PHAROS_DB=var/regression.sqlite ./scripts/run-core.sh
```

In another shell:

```bash
curl -s http://127.0.0.1:8765/health | jq
curl -s -X POST http://127.0.0.1:8765/v0/capture \
  -H 'content-type: application/json' \
  -d '{"body":"Review the retry logic MR before standup","title":"Review retry MR"}' | jq
curl -s http://127.0.0.1:8765/v0/today | jq
```

Expected v0.3 shape:

```text
.needs_decision exists
.needs_input exists
.watching exists
.handled exists
.noise.count exists
```

Old top-level fields must not exist:

```text
.needs_review
.running
.needs_context
.new_items
.done_today
.archived_noise_count
```

## Safety checks

1. Execute action without approval: must fail.
2. Edit-and-approve: hash changes and edited body executes.
3. Reject: action cannot execute.
4. L4/L5: cannot approve or execute.
5. Non-`pharos.` target via `execute-local`: blocked, timeline event created, metric increments.

## UI checks

1. Today top sections are `Needs Decision`, `Needs Input`, `Watching`, `Handled`, `Noise`.
2. No top-level `Needs Review` section.
3. Detail page shows evidence before approval buttons.
4. Detail page clearly shows target and external-write yes/no.
5. Payload hash appears only in audit/debug details.
