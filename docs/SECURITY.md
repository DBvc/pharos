# Security and Safety Invariants

## Default posture

Pharos is local-first and default-read-only. The starter intentionally begins with local actions only. External writeback is added later behind explicit source permission and user approval.

## Hard invariants

1. External writes require approval.
2. Approval must match the current action payload hash.
3. L3 and above cannot bypass Review Gate.
4. L4 and L5 are not executable in MVP.
5. Source adapters cannot approve or execute actions.
6. Skills cannot approve or execute actions.
7. UI cannot directly call adapter writeback.
8. Every Ready for Review action has evidence.
9. Every execution attempt creates a visible timeline event.
10. Unapproved external write count must remain 0 in normal operation. Blocked attempts must be counted separately.

## Approval hash

Payload hash v2 is computed as:

```text
"pharos.action-payload.v2\0"
  || uint64_be(byte_length(target_kind)) || target_kind
  || uint64_be(byte_length(target_ref))  || target_ref
  || uint64_be(byte_length(risk))        || canonical risk
  || uint64_be(byte_length(body))        || body
```

Core returns `sha256:<64 lowercase hex>`. Lengths are byte counts, not character
counts. When the user edits a draft, the core updates the action body and hash,
then creates an approval bound to the new hash. Execution re-checks the current
action hash against the approval hash and rejects legacy MD5 identities.

## Secret handling

M0:

- No source tokens in SQLite.
- Dev tokens may come from environment variables.
- Logs must redact authorization headers and obvious token fields.

M1:

- SwiftUI stores source tokens in Keychain.
- Core receives short-lived local access through a local capability token or a secure handoff file.

M2:

- Package app with local daemon.
- Prefer Unix domain socket over localhost HTTP.
- Add per-install capability token.

## Logging rules

Allowed:

- Request id.
- Source kind.
- External object id or URL when not sensitive.
- Action id.
- Approval id.
- Hashes.
- Error categories.

Avoid:

- Full raw message bodies in daemon logs.
- Tokens or authorization headers.
- Full source API responses.
- User secrets or private credentials.

## Threat notes

### UI compromised or buggy

Mitigation: UI cannot write externally. It can ask core to approve. Core binds approval to payload hash.

### Adapter compromised or buggy

Mitigation: adapters cannot execute without approval. Source failure is isolated.

### Skill hallucination

Mitigation: skill output is evidence-referenced, typed, review-gated, and non-authoritative.

### User edits after approval display

Mitigation: edit and approve creates a new action hash. Execution checks current hash.

### Replay or stale approval

Mitigation: approval should eventually include action revision and expiry. Starter includes hash verification. Add revision and expiry in M1.
