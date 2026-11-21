#!/usr/bin/env python3
"""
Generate cross-language parity fixtures for the Private Judges Workspace.

The Python reference implementation (engine/) is the SINGLE SOURCE OF TRUTH.
This script writes JSON vectors that the Swift XCTest suite compares against,
byte-for-byte, so the Swift CoordinateEngine/AssessmentBuilder port is pinned
to the reference behaviour on the SAME platform where the tests run.

Usage:
    python3 scripts/gen_reference_vectors.py Tests/Fixtures/reference_vectors.json
    python3 scripts/gen_reference_vectors.py Tests/Fixtures/reference_vectors.json --check
        (--check regenerates in memory and compares against the committed file;
         a mismatch means platform floating-point behaviour changed the vectors.)
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, "..", "engine")
sys.path.insert(0, ENGINE)

import coordinate_engine as ce  # noqa: E402
import crosshair_records as cr  # noqa: E402
import multi_judge as mj  # noqa: E402

FIXED_NOW = "2026-11-21T10:00:00Z"


def margin_ok(value: float, digits: int = 6) -> bool:
    """Ensure rounding to `digits` decimals is far from a .5 boundary, so
    platform ulp differences cannot flip the rounded value."""
    scaled = abs(value) * (10 ** digits)
    frac = scaled - int(scaled)
    return min(frac, 1.0 - frac) > 1e-3 if frac not in (0.0,) else True


def main() -> int:
    out_path = sys.argv[1] if len(sys.argv) > 1 else "Tests/Fixtures/reference_vectors.json"
    check_only = "--check" in sys.argv

    vectors = {
        "meta": {
            "engine_version": ce.ENGINE_VERSION,
            "generated_with": "scripts/gen_reference_vectors.py",
            "note": "Python reference is authoritative; Swift tests compare byte-for-byte.",
        }
    }

    # ---- canonical JSON vectors ------------------------------------------------
    canonical_cases = [
        {"a": 1, "b": "two", "c": [1, 2, 3], "d": {"x": True, "y": None}},
        {"z": 12.0, "y": 8.485, "x": 512.000004, "w": 0.1},
        {"s": "quote\" backslash\\ newline\n tab\t unicode: كرة القدم ⚽"},
        {"ctrl": "\u0001\u001f", "slash": "a/b", "empty": "", "neg": -7},
        {"nested": {"deep": {"deeper": [1.5, [2, "three"]]}}, "f": False},
        [1, "two", 3.5, None, True],
        {},
        [],
    ]
    vectors["canonical_vectors"] = [
        {"input": case, "canonical": ce.canonical_json(case), "hash": ce.record_hash(case)}
        for case in canonical_cases
    ]

    # ---- round-half-to-even vectors (incl. negatives) --------------------------
    rounding_inputs = [2.5, 3.5, -2.5, -3.5, 0.5, -0.5, 1.4999999, -1.4999999,
                       4.5, -4.5, 12.5, -12.5, 0.49, -0.51, 6.5, -6.5, 7.5]
    vectors["rounding_vectors"] = [{"v": v, "rounded": round(v)} for v in rounding_inputs]

    # ---- P -> N -> P round-trip vectors ----------------------------------------
    sizes = [(4032, 3024), (3024, 4032), (1920, 1080), (1000, 1000)]
    roundtrip = []
    for (w, h) in sizes:
        points = [[0, 0], [w - 1, h - 1], [w // 2, h // 2], [1, 1], [17, 901],
                  [w - 2, 5], [int(w * 0.3), int(h * 0.77)]]
        for (x, y) in points:
            p = ce.PixelPoint(x, y)
            nx, ny = ce.to_normalized(p, w, h)
            q = ce.from_normalized(nx, ny, w, h)
            err = ce.roundtrip_error_px(p, w, h)
            roundtrip.append({"w": w, "h": h, "x": x, "y": y,
                              "nx": nx, "ny": ny,
                              "rx": q.x, "ry": q.y,
                              "err_x": err[0], "err_y": err[1],
                              "assert_err_le_1": err[0] <= 1 and err[1] <= 1})
            assert err[0] <= 1 and err[1] <= 1
    vectors["roundtrip_vectors"] = roundtrip

    # ---- distance vectors (3-4-5 exact) ----------------------------------------
    vectors["distance_vectors"] = [
        {"ax": 0, "ay": 0, "bx": 3, "by": 4, "distance": ce.euclidean_distance_px(ce.PixelPoint(0, 0), ce.PixelPoint(3, 4))},
        {"ax": 100, "ay": 100, "bx": 103, "by": 104, "distance": ce.euclidean_distance_px(ce.PixelPoint(100, 100), ce.PixelPoint(103, 104))},
        {"ax": 0, "ay": 0, "bx": 5, "by": 0, "distance": ce.euclidean_distance_px(ce.PixelPoint(0, 0), ce.PixelPoint(5, 0))},
    ]
    vectors["normalized_distance_vectors"] = [
        {"w": 1920, "h": 1080, "ax": 0, "ay": 0, "bx": 3, "by": 4,
         "nd": ce.normalized_distance(ce.PixelPoint(0, 0), ce.PixelPoint(3, 4), 1920, 1080)},
    ]

    # ---- consensus vectors ------------------------------------------------------
    # Point sets chosen so pairwise spreads are exact or have safe rounding margins.
    consensus_sets = [
        {"name": "square_symmetric", "points": [[500, 340], [524, 340], [524, 364], [500, 364]],
         "tolerance_px": 12.0, "method": "geometric_median"},
        {"name": "triangle_345", "points": [[100, 100], [103, 104], [106, 108]],
         "tolerance_px": 12.0, "method": "geometric_median"},
        {"name": "outlier_robust", "points": [[500, 340], [512, 352], [524, 364], [2000, 800]],
         "tolerance_px": 12.0, "method": "geometric_median"},
        {"name": "even_median", "points": [[100, 200], [104, 200], [100, 204], [104, 204]],
         "tolerance_px": 15.5, "method": "per_axis_median"},
        {"name": "single_point", "points": [[640, 480]],
         "tolerance_px": 0.0, "method": "geometric_median"},
    ]
    consensus_vectors = []
    for spec in consensus_sets:
        pts = [ce.PixelPoint(x, y) for (x, y) in spec["points"]]
        probe = ce.consensus(pts, method=spec["method"])
        for v in [probe["raw_x"], probe["raw_y"]]:
            assert margin_ok(float(v)), f"raw value {v} too close to rounding boundary"
        ev = ce.evaluate_consensus(pts, spec["tolerance_px"], method=spec["method"])
        canonical = ce.canonical_json(ev)
        consensus_vectors.append({
            "name": spec["name"],
            "points": spec["points"],
            "tolerance_px": spec["tolerance_px"],
            "method": spec["method"],
            "consensus": ev,
            "canonical": canonical,
            "hash": ce.record_hash(ev),
        })
    vectors["consensus_vectors"] = consensus_vectors

    # ---- record vectors (crosshair_records) -------------------------------------
    record_payloads = []
    recs = [
        cr.CrosshairRecord(competition_id="PJV-2026-R1", judge_id="JUDGE-01",
                           image_id="a" * 64, image_width_px=1920, image_height_px=1080,
                           x_px=1234, y_px=567, note="near centre circle",
                           created_at=FIXED_NOW),
        cr.CrosshairRecord(competition_id="PJV-2026-R1", judge_id="JUDGE-02",
                           image_id="a" * 64, image_width_px=1920, image_height_px=1080,
                           x_px=1241, y_px=570, note="", created_at=FIXED_NOW),
    ]
    for rec in recs:
        d = rec.to_json_dict()
        record_payloads.append({"payload": d, "record_id": cr.record_hash(d)})
    vectors["record_vectors"] = record_payloads

    # ---- assessment vectors (multi_judge) ---------------------------------------
    # Freeze timestamps so the Swift builder can reproduce byte-identical records.
    real_now = mj.utc_now_iso
    mj.utc_now_iso = lambda: FIXED_NOW
    try:
        assessment_specs = [
            {"assessment_id": "A-VECT-001", "competition_id": "PJV-2026-R1", "image_id": "b" * 64,
             "tolerance_px": 12.0, "method": "geometric_median",
             "submissions": [
                 {"judge_id": "JUDGE-01", "x_px": 950, "y_px": 512, "note": "left of centre"},
                 {"judge_id": "JUDGE-02", "x_px": 962, "y_px": 520, "note": ""},
                 {"judge_id": "JUDGE-03", "x_px": 954, "y_px": 516, "note": "goal line"},
             ],
             "proposals": [{"x_px": 957, "y_px": 516, "model": "heuristic-blob-v1", "confidence": 0.83}],
             "decisions": []},
            {"assessment_id": "A-VECT-002", "competition_id": "PJV-2026-R1", "image_id": "b" * 64,
             "tolerance_px": 20.0, "method": "geometric_median",
             "submissions": [
                 {"judge_id": "JUDGE-01", "x_px": 500, "y_px": 340, "note": ""},
                 {"judge_id": "JUDGE-02", "x_px": 524, "y_px": 340, "note": ""},
                 {"judge_id": "JUDGE-03", "x_px": 524, "y_px": 364, "note": ""},
                 {"judge_id": "JUDGE-04", "x_px": 500, "y_px": 364, "note": "symmetric set"},
             ],
             "proposals": [],
             "decisions": [{"status": "APPROVED", "approver": "project-owner"}]},
        ]
        assessment_vectors = []
        for spec in assessment_specs:
            a = mj.Assessment(assessment_id=spec["assessment_id"],
                              competition_id=spec["competition_id"],
                              image_id=spec["image_id"], judges=[], tolerance_px=spec["tolerance_px"],
                              consensus_method=spec["method"])
            for s in spec["submissions"]:
                a.add_judge_submission(mj.JudgeSubmission(
                    judge_id=s["judge_id"], x_px=s["x_px"], y_px=s["y_px"],
                    image_width_px=1920, image_height_px=1080, submitted_at=FIXED_NOW,
                    note=s["note"]), actor=s["judge_id"])
            for p in spec["proposals"]:
                a.add_ai_proposal(dict(p), actor="system")
            for dec in spec["decisions"]:
                a.decide(dec["status"], dec["approver"])
            d = a.to_json_dict()
            assessment_vectors.append({
                "name": spec["assessment_id"],
                "assessment": d,
                "assessment_hash": d["assessment_hash"],
                "audit_chain_valid": a.audit_chain_valid(),
                "canonical_without_hash": ce.canonical_json(
                    {k: v for k, v in d.items() if k != "assessment_hash"}),
            })
            assert a.audit_chain_valid()
        vectors["assessment_vectors"] = assessment_vectors
    finally:
        mj.utc_now_iso = real_now

    rendered = json.dumps(vectors, indent=1, ensure_ascii=False)

    if check_only and os.path.exists(out_path):
        with open(out_path, "r", encoding="utf-8") as fh:
            committed = fh.read()
        if committed == rendered:
            print("parity check: OK (committed fixture matches this platform)")
            return 0
        # Diagnose: compare per-vector to report where platforms differ.
        committed_obj = json.loads(committed)
        diffs = []
        for key in vectors:
            if json.dumps(committed_obj.get(key), sort_keys=True) != json.dumps(vectors.get(key), sort_keys=True):
                diffs.append(key)
        print("parity check: MISMATCH in sections:", diffs)
        print("Regenerating the fixture file for this platform.")
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(rendered)
        return 2

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    print(f"vectors written: {out_path}")
    print(f"sections: {', '.join(k for k in vectors)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
