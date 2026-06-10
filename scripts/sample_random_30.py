#!/usr/bin/env python3
"""Pick 30 random SWE-rebench instances (fixed seed), excluding the curated 20.

Output:
  configs/instances_30random.regex   (regex for --filter)
  configs/instances_30random.json    (instance_id + repo for reference)
"""
import json
import random
from pathlib import Path

from datasets import load_dataset

SEED = 42
N = 30
EXCLUDE_FILE = Path("configs/instances_20.json")


def main() -> None:
    ds = load_dataset("nebius/SWE-rebench-leaderboard", split="test")
    excluded = {r["instance_id"] for r in json.loads(EXCLUDE_FILE.read_text())}

    pool = [row["instance_id"] for row in ds if row["instance_id"] not in excluded]
    pool.sort()
    rng = random.Random(SEED)
    chosen_ids = rng.sample(pool, N)

    chosen = []
    by_id = {row["instance_id"]: row for row in ds}
    for iid in chosen_ids:
        row = by_id[iid]
        chosen.append({"instance_id": iid, "repo": row["repo"]})

    chosen.sort(key=lambda c: c["instance_id"])

    print(f"Picked {len(chosen)} random instances (seed={SEED}):")
    for c in chosen:
        print(f"  {c['instance_id']:60s}  ({c['repo']})")

    Path("configs/instances_30random.json").write_text(json.dumps(chosen, indent=2))
    print("\nWrote configs/instances_30random.json")

    regex = "^(" + "|".join(c["instance_id"].replace(".", r"\.") for c in chosen) + ")$"
    Path("configs/instances_30random.regex").write_text(regex)
    print("Wrote configs/instances_30random.regex")


if __name__ == "__main__":
    main()
