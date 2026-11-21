# PARITY NOTES — Swift engine vs Python reference

The Python reference (`engine/coordinate_engine.py`, `engine/multi_judge.py`,
`engine/crosshair_records.py`) is the single authoritative implementation.
The Swift port (`Sources/Engine/`, `Sources/Support/CanonicalJSON.swift`) must
produce identical results for identical inputs. This document records every
point where platform behaviour could diverge and how each is handled.

## 1. Round-half-to-even (fixed in this build)

The prior scaffold's Swift `roundHalfEven` diverged from Python for NEGATIVE
half-integers (e.g. `round(-2.5)` must be `-2`, not `-3`). The current
implementation selects the even neighbour via floor/ceil for exact `.5` cases
and matches Python for both signs. Pinned by
`Tests/Fixtures/reference_vectors.json` → `rounding_vectors` (generated from
Python `round()` on the CI platform).

## 2. Canonical JSON hashing

Swift no longer hashes through `JSONEncoder` (its integer/float formatting is
platform-behaviour-dependent). `CanonicalJSON` reproduces Python
`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`
exactly:

- keys sorted by code point; compact separators;
- only `"`, `\` and control characters escaped; `/` untouched;
- non-ASCII emitted as raw UTF-8;
- `Int` as decimal integer; `Double` via shortest round-trip repr with
  Python's trailing `.0` for integral values (`12.0`).

The `Int`/`Double` distinction is preserved end-to-end (Python int vs float)
in every typed canonical dict (`x_px` int, `tolerance_px` float, …), and
fixture parsing uses `NSNumber.objCType` so `12` vs `12.0` survive the
JSON round trip in tests.

## 3. Floating-point rounding of consensus fields

The reference rounds `raw_x/raw_y` to 6 decimals, `max_spread_px` to 3 and
`agreement_ratio` to 4 (`round()` = half-to-even on decimal representation).
Swift `roundTo(_:digits:)` implements the same operation. Python's
`decimal-aware` rounding and a multiply/divide implementation differ ONLY at
exact decimal boundaries; the fixture generator asserts every vector sits
far from a boundary (`margin_ok`), so the two agree on all pinned vectors.
For hashes this is additionally irrelevant in production: both
implementations hash the PARSED stored values (repr round-trip is exact),
never a recomputed float.

## 4. `hypot` across platforms

CPython implements `math.hypot` itself; macOS libm provides the Swift
`hypot`. They can differ by ≤1 ulp on irrational results. The consensus
vectors therefore use point sets whose spreads are exact or margin-safe, and
the CI regenerates the fixture ON THE BUILD PLATFORM (`--check` step) before
the Swift tests run, so Swift always compares against same-platform Python
output. Any real ulp difference is reported loudly by the `--check` step and
absorbed by fixture regeneration.

## 5. Weiszfeld iteration

Both sides initialize at the per-axis median, iterate at most 100 times,
use the 1e-9 distance floor and the 1e-7 convergence tolerance, and update
in the same operation order (`wsum += w; sx += w*x; sy += w*y`), giving
deterministic, platform-stable results for the tested point sets.

## 6. Where parity is pinned (CI)

- `canonical_vectors` — serializer bytes + SHA-256, byte-for-byte.
- `rounding_vectors` — half-to-even including negatives.
- `roundtrip_vectors` — P→N→P over 4 image sizes, error ≤ 1 px/axis.
- `distance_vectors` / `normalized_distance_vectors` — 3-4-5 exactness.
- `consensus_vectors` — full consensus dict, canonical bytes + hash.
- `record_vectors` — crosshair record ids identical to Python.
- `assessment_vectors` — full assessment rebuilt step-by-step in Swift must
  reproduce Python's canonical serialization and `assessment_hash`.
- `sample_assessment.json` — a real Python-produced record verifies in Swift
  (decode + hash + audit chain).

## 7. Engine version

Both engines remain at `1.0.0`. Any change to the Python reference requires
regenerating the fixture and updating the Swift port in the same change.
