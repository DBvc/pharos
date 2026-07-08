# Task 07: Source settings shell

Branch: `codex/source-settings-shell`

## Goal

Add persistent source settings and a Swift Sources shell before real adapters.

## Read first

```text
specs/source_settings_contract.md
```

## Files to change

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/bin/daemon/main.ml
core/test/source_settings_test.ml
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Views/SourcesView.swift
docs/API.md
protocol/openapi.yaml
```

## Exact implementation steps

1. Add `source_config` type and JSON encoders.
2. Add `sources` table and default rows.
3. Add Store functions:
   - `list_sources`
   - `get_source`
   - `patch_source`
   - `ensure_default_sources`
4. Add API routes:
   - `GET /v0/sources`
   - `PATCH /v0/sources/:id`
5. Add Swift models and API client functions.
6. Update `SourcesView` to list all four P0 sources.
7. Ensure `write_enabled` defaults to false and copy says review is still required.
8. Add OCaml tests.

## Do not change

1. Do not implement real remote source calls.
2. Do not store tokens in SQLite.
3. Do not allow source settings to bypass Review Gate.

## Commands

```bash
cd core && dune build && dune runtest
swift build --package-path ui/macos/PharosApp
```

## Acceptance

1. Empty DB initializes four sources.
2. `GET /v0/sources` returns four rows.
3. Patching a source persists after closing and reopening store.
4. Swift Sources page compiles.

## Final response format

```text
Changed files:
Tests run:
Swift build:
Acceptance status:
Known follow-up:
```
