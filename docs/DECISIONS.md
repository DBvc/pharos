# Architecture Decision Records

## ADR-001: OCaml owns the core

Status: accepted.

Reason: the core is a typed state machine with policy, evidence, approval matching, and persistence. OCaml gives strong modeling tools and keeps safety rules away from UI callback soup.

## ADR-002: SwiftUI for the first macOS surface

Status: accepted.

Reason: Pharos is macOS-first and needs menu bar, notifications, local lifecycle, and future Keychain integration. SwiftUI keeps the desktop shell native and thin.

## ADR-003: Local HTTP first, Unix socket later

Status: accepted for M0.

Reason: localhost HTTP is faster for early testing and easy for CLI, curl, and SwiftUI. It should be replaced or wrapped with Unix domain socket plus capability token before real source credentials and writeback are enabled.

## ADR-004: SQLite first

Status: accepted.

Reason: local-first, inspectable, portable, good enough for event and request state. Add encryption or SQLCipher only after token and secret boundaries are clear.

## ADR-005: Adapter protocol over adapter language purity

Status: accepted.

Reason: Feishu and GitLab SDK reality may favor languages other than OCaml. The invariant is the protocol and policy boundary, not that every edge worker is OCaml.
