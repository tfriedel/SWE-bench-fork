#!/usr/bin/env bash
# Score mini-swe-agent predictions against SWE-rebench-leaderboard via swebench harness.
# Usage: scripts/run_eval.sh <preds.json> <run_id> [extra_workers]
set -euo pipefail
PREDS="${1:-results/smoke/preds.json}"
RUN_ID="${2:-smoke}"
WORKERS="${3:-2}"

cd "$(dirname "$0")/.."
source .venv/bin/activate

python -m swebench.harness.run_evaluation \
  --dataset_name nebius/SWE-rebench-leaderboard \
  --split test \
  --predictions_path "$PREDS" \
  --max_workers "$WORKERS" \
  --cache_level instance \
  --namespace swerebench \
  --run_id "$RUN_ID"
