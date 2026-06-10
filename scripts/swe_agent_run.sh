#!/usr/bin/env bash
# Run SWE-agent (full harness) on the curated 20-instance set.
# Produces a SWE-bench compatible preds.json at results/<run_id>/preds.json so
# scripts/benchmark.sh can feed it directly into the eval harness.
#
# Args (positional):
#   $1  run_id
#   $2  model_name
#   $3  api_base

set -euo pipefail
RUN_ID="${1:?run_id required}"
MODEL_NAME="${2:-qwen3.6-35b-a3b-awq}"
API_BASE="${3:-http://localhost:8021/v1}"
INSTANCES_REGEX_FILE="${INSTANCES_REGEX_FILE:-configs/instances_20.regex}"

cd "$(dirname "$0")/.."

OUT_DIR="results/${RUN_ID}"
mkdir -p "$OUT_DIR"

REGEX="$(cat "$INSTANCES_REGEX_FILE")"

# Use the bash-only template; it doesn't rely on Anthropic-specific tools.
CONFIG="swe-agent/config/bash_only.yaml"

sweagent run-batch \
  --config "$CONFIG" \
  --instances.type huggingface \
  --instances.dataset_name nebius/SWE-rebench-leaderboard \
  --instances.split test \
  --instances.filter "$REGEX" \
  --output_dir "$OUT_DIR" \
  --num_workers 1 \
  --agent.type default \
  --agent.model.name "openai/${MODEL_NAME}" \
  --agent.model.api_base "${API_BASE}" \
  --agent.model.api_key "EMPTY" \
  --agent.model.temperature 0.6 \
  --agent.model.top_p 0.95 \
  --agent.model.max_input_tokens 200000 \
  --agent.model.max_output_tokens 32768 \
  --agent.model.per_instance_cost_limit 0 \
  --agent.model.per_instance_call_limit 250 \
  --agent.model.total_cost_limit 0 \
  --agent.model.completion_kwargs '{"timeout":1800,"drop_params":true}'

# SWE-agent emits its preds in $OUT_DIR/preds.json — but in nested layout. The
# top-level merged file is what the SWE-bench harness needs.
if [[ ! -f "$OUT_DIR/preds.json" ]]; then
  # Fall back to merging nested predictions
  source .venv/bin/activate
  sweagent merge-preds --directory "$OUT_DIR" --output "$OUT_DIR/preds.json"
fi
