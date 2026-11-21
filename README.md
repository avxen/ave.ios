# Private Judges Workspace

An independent, private judging tool for crosshair-based image assessments:
multi-judge consensus, human-approved final decisions, hash-chained audit
trails, AES-GCM encrypted local storage, and export/backup of judging records.

> **Identity** — This is an independent application. It is NOT the official
> BOTB application, is not derived from it, and is not affiliated with or
> endorsed by BOTB plc. The internal project codename used in documentation
> ("BOTB Private Judges Edition") and the fictional project persona
> (`docs/PROJECT_PERSONA.md`, James Alexander Bennett) exist for documentation
> only.

## Repository layout

| Path | Contents |
| --- | --- |
| `Sources/Engine/` | Coordinate engine (Swift port), assessment models/builder, heuristic proposal engine |
| `Sources/Services/` | Auth gate, encrypted stores, workspace store, audit log, video frames, export |
| `Sources/Views/` | SwiftUI screens (workspace, judge viewer, assessments, AI proposals, records) |
| `engine/`, `tests/` | **Preserved** Python reference implementation + 50-test regression suite |
| `schemas/` | `assessment.schema.json` (machine-readable record schema) |
| `Tests/` | Swift XCTest suite + Python-generated parity fixtures |
| `scripts/gen_reference_vectors.py` | Regenerates the cross-language parity fixture |
| `docs/` | Investigation report, signing guide, parity notes, persona, coordinate spec |
| `.github/workflows/build.yml` | CI: Python tests → Swift tests → unsigned IPA → GitHub release |

## Build (macOS, one command each)

```bash
brew install xcodegen
xcodegen generate --spec project.yml     # creates PrivateJudgesWorkspace.xcodeproj
open PrivateJudgesWorkspace.xcodeproj    # Cmd+R on an iOS simulator/device
```

CI (GitHub Actions, macOS runner) runs everything automatically on every push:
Python regression suite, parity-fixture check, full Swift test suite on an iOS
simulator, unsigned Release archive, IPA packaging + structure verification,
and a GitHub **release** with a Safari-downloadable IPA.

## Security model

- **Access** — first-launch PIN (salted PBKDF2 verifier in the Keychain;
  the PIN is never stored), optional device biometrics, exponential lockout.
- **At rest** — every record, assessment, workspace document and image blob is
  AES-GCM sealed with a 256-bit Keychain key.
- **Integrity** — record/assessment digests are SHA-256 over a canonical JSON
  serialization, byte-compatible with the Python reference; audit trails are
  hash-chained (`GENESIS` → …) and verified on every load.
- **AI separation** — proposals live in `ai_proposals[]` only; judge
  submissions cannot come from AI (ids beginning with "ai" are refused) and
  never influence the consensus or the approval gate.

## Coordinate engine (single source of truth)

`Sources/Engine/CoordinateEngine.swift` mirrors `engine/coordinate_engine.py`
rule-for-rule (canonical integer pixel space, normalized space,
round-half-to-even, Weiszfeld geometric median, deterministic outputs). Every
screen that places, adjusts, stores, reopens, compares or verifies a crosshair
routes through this engine. Parity is pinned byte-for-byte by
`Tests/Fixtures/reference_vectors.json`, regenerated on the CI platform by
`scripts/gen_reference_vectors.py` (see `docs/PARITY_NOTES.md`).

## Deliverables produced by CI

- `Private_Judges_Workspace_unsigned.ipa` — real, structure-verified,
  **unsigned** archive built from this source. Installable only after the
  owner signs it (see `docs/SIGNING_GUIDE.md`).
- `Private_Judges_Workspace_source.zip` — this repository.
- `TEST_SUMMARY.md`, `IPA_SHA256.txt` — executed test totals and artifact hash.
