#!/usr/bin/env python3
"""Print a per-instance + per-category summary for a benchmark run.

Usage: scripts/summarize.py <run_id> <model_name>
"""
import json
import sys
from collections import defaultdict
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: summarize.py <run_id> <model_name> [instances_json]")
    run_id, model = sys.argv[1], sys.argv[2]
    instances_json = sys.argv[3] if len(sys.argv) > 3 else "configs/instances_20.json"
    # Final summary file is named <model_with_slashes_as_double_underscore>.<run_id>.json
    safe_model = model.replace("/", "__")
    summary_path = Path(f"openai__{safe_model}.{run_id}.json")
    if not summary_path.exists():
        # Sometimes harness uses no provider prefix
        for p in Path(".").glob(f"*{run_id}.json"):
            summary_path = p
            break
    if not summary_path.exists():
        sys.exit(f"no summary file found for run_id={run_id}")
    summary = json.loads(summary_path.read_text())

    resolved, unresolved = set(), set()
    eval_root = Path("logs/run_evaluation") / run_id / f"openai__{safe_model}"
    if not eval_root.exists():
        # Fallback: pick the only model dir
        candidates = list((Path("logs/run_evaluation") / run_id).iterdir())
        if candidates:
            eval_root = candidates[0]
    for iid in summary["completed_ids"]:
        rep_path = eval_root / iid / "report.json"
        if not rep_path.exists():
            continue
        rep = json.loads(rep_path.read_text())
        (resolved if rep[iid]["resolved"] else unresolved).add(iid)

    cats = json.loads(Path(instances_json).read_text())
    n_total = summary["submitted_instances"] or len(cats)
    print(f"\n=== {run_id} | model={model} ===")
    print(
        f"resolved: {summary['resolved_instances']}/{n_total} "
        f"({summary['resolved_instances'] / n_total * 100:.0f}% pass@1) | "
        f"unresolved: {summary['unresolved_instances']} | "
        f"empty: {summary['empty_patch_instances']} | "
        f"errors: {summary['error_instances']}"
    )
    if summary["completed_instances"]:
        rate_among_submitted = summary["resolved_instances"] / summary["completed_instances"]
        print(f"resolved among submitted: {summary['resolved_instances']}/{summary['completed_instances']} ({rate_among_submitted * 100:.0f}%)")
    print()

    has_category = bool(cats and "category" in cats[0])
    print("=== PER-INSTANCE ===")
    for c in cats:
        iid = c["instance_id"]
        if iid in resolved:
            status = "RESOLVED"
        elif iid in unresolved:
            status = "unresolved"
        else:
            status = "empty patch"
        if has_category:
            print(f"  [{c['category']:20s}] {iid:50s} {status}")
        else:
            print(f"  {iid:60s} {status}")

    if has_category:
        per_cat = defaultdict(lambda: [0, 0, 0])  # resolved, unresolved, empty
        for c in cats:
            iid = c["instance_id"]
            idx = 0 if iid in resolved else (1 if iid in unresolved else 2)
            per_cat[c["category"]][idx] += 1
        print("\n=== BY CATEGORY ===")
        for cat, (r, u, e) in per_cat.items():
            n = r + u + e
            print(f"  {cat:20s}  resolved {r}/{n}  unresolved {u}  empty {e}")


if __name__ == "__main__":
    main()
