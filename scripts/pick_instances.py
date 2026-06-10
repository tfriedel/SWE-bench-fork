#!/usr/bin/env python3
"""Build a deterministic 20-instance benchmark set covering Plantix-relevant categories.

For each repo in CATEGORIES, pick the alphabetically-first instance ID. This keeps
selection stable across quantization runs.
"""
import json
from pathlib import Path
from datasets import load_dataset

CATEGORIES = {
    "fastapi_services": [
        "BerriAI/litellm",
        "schemathesis/schemathesis",
        "jlowin/fastmcp",
        "vitalik/django-ninja",
    ],
    "geospatial": [
        "movingpandas/movingpandas",
        "GenericMappingTools/pygmt",
        "SciTools/iris",
        "UXARRAY/uxarray",
    ],
    "dataframe": [
        "pandas-dev/pandas",
        "modin-project/modin",
        "pydata/xarray",
        "lincc-frameworks/nested-pandas",
    ],
    "sql": [
        "tobymao/sqlglot",
        "agronholm/sqlacodegen",
        "reata/sqllineage",
    ],
    "cli": [
        "BrianPugh/cyclopts",
        "omni-us/jsonargparse",
        "simonw/files-to-prompt",
    ],
    "frontend_fullstack": [
        "marimo-team/marimo",
        "Avaiga/taipy",
    ],
}


def main() -> None:
    ds = load_dataset("nebius/SWE-rebench-leaderboard", split="test")
    by_repo: dict[str, list[dict]] = {}
    for row in ds:
        by_repo.setdefault(row["repo"], []).append(row)

    chosen: list[dict] = []
    missing: list[str] = []
    for category, repos in CATEGORIES.items():
        for repo in repos:
            instances = sorted(by_repo.get(repo, []), key=lambda r: r["instance_id"])
            if not instances:
                missing.append(repo)
                continue
            chosen.append({"category": category, **instances[0]})

    print(f"Picked {len(chosen)} instances; missing: {missing}\n")
    for c in chosen:
        problem = (c["problem_statement"] or "").splitlines()[0][:90]
        print(f"  [{c['category']:20s}] {c['instance_id']:50s} | {problem}")

    out = Path("configs/instances_20.json")
    out.parent.mkdir(exist_ok=True)
    out.write_text(
        json.dumps(
            [{"instance_id": c["instance_id"], "category": c["category"], "repo": c["repo"]} for c in chosen],
            indent=2,
        )
    )
    print(f"\nWrote {out}")

    ids = [c["instance_id"] for c in chosen]
    regex = "^(" + "|".join(i.replace(".", r"\.") for i in ids) + ")$"
    Path("configs/instances_20.regex").write_text(regex)
    print(f"Wrote configs/instances_20.regex")


if __name__ == "__main__":
    main()
