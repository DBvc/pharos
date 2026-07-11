# Architecture Decision Records

## ADR-001: OCaml owns the core

Status: accepted.

Reason: the core is a typed state machine with policy, evidence, approval matching, and persistence. OCaml gives strong modeling tools and keeps safety rules away from UI callback soup.

## ADR-002: SwiftUI for the first macOS surface

Status: accepted.

Reason: Pharos is macOS-first and needs menu bar, notifications, local lifecycle, and future Keychain integration. SwiftUI keeps the desktop shell native and thin.

## ADR-003: Local HTTP first, Unix socket later

Status: accepted for v0.3 with a local capability boundary.

Reason: local HTTP remains convenient for CLI, curl, and SwiftUI, but localhost alone is not caller authentication. In v0.3, `pharosd` accepts only the exact loopback hosts `127.0.0.1` and `::1`. `PHAROS_CAPABILITY_TOKEN` must be exactly 64 lowercase hexadecimal characters and is validated before SQLite is opened. `/health` is public; every `/v0/*` route requires its Bearer capability and uses fixed-time token comparison.

The v0.3 boundary protects against non-loopback exposure, unauthenticated network calls, browser or accidental local calls, and other OS users. It does not claim to protect against malicious software that already controls the same user account or process environment. Capability and source tokens must never enter SQLite, timeline, metrics, exports, examples, snapshots, or logs. A Unix domain socket plus Keychain-managed lifecycle remains the later hardening path.

## ADR-004: SQLite first

Status: accepted.

Reason: local-first, inspectable, portable, good enough for event and request state. Add encryption or SQLCipher only after token and secret boundaries are clear.

## ADR-005: Adapter protocol over adapter language purity

Status: accepted.

Reason: Feishu and GitLab SDK reality may favor languages other than OCaml. The invariant is the protocol and policy boundary, not that every edge worker is OCaml.
