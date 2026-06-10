#!/usr/bin/env bash
# Run an agent harness on the curated 20-instance set, then evaluate predictions
# against SWE-rebench. Designed for benchmarking Qwen 3.6 quantizations served
# by a local vLLM at OPENAI_API_BASE.
#
# Usage:
#   scripts/benchmark.sh <run_id> [harness] [model_name] [api_base]
#
# Args:
#   run_id      Tag for this run (e.g. qwen36_awq, qwen36_q4km).
#   harness     mini | swe-agent (default: mini)
#   model_name  Model id served by the endpoint (default: qwen3.6-35b-a3b-awq)
#   api_base    OpenAI-compatible base URL (default: http://localhost:8021/v1)
#
# Outputs:
#   results/<run_id>/preds.json         agent predictions
#   results/<run_id>/<instance>/...     trajectories
#   logs/run_evaluation/<run_id>/...    per-instance test reports
#   <model>.<run_id>.json               final summary

set -euo pipefail

RUN_ID="${1:?usage: scripts/benchmark.sh <run_id> [harness] [model_name] [api_base]}"
HARNESS="${2:-mini}"
MODEL_NAME="${3:-qwen3.6-35b-a3b-awq}"
API_BASE="${4:-http://localhost:8021/v1}"
INSTANCES_REGEX_FILE="${INSTANCES_REGEX_FILE:-configs/instances_20.regex}"

cd "$(dirname "$0")/.."
source .venv/bin/activate

OUT_DIR="results/${RUN_ID}"
mkdir -p "$OUT_DIR" logs

REGEX="$(cat "$INSTANCES_REGEX_FILE")"

echo "==> Running ${HARNESS} agent on 20 instances (run_id=${RUN_ID}, model=${MODEL_NAME})"
case "$HARNESS" in
  mini)
    # Generate a per-run config that injects the model & endpoint
    cat > "$OUT_DIR/agent_config.yaml" <<EOF
model:
  model_name: "openai/${MODEL_NAME}"
  cost_tracking: "ignore_errors"
  model_kwargs:
    api_base: "${API_BASE}"
    api_key: "EMPTY"
    temperature: 0.6
    top_p: 0.95
    max_tokens: 32768
    timeout: 1800
    drop_params: true
agent:
  step_limit: 250
  cost_limit: 0
EOF

    # `import minisweagent` prints a banner to stdout; suppress it so we capture only the path.
    BASE_CFG="$(MSWEA_QUIET=1 python -c 'import sys, os; sys.stdout = open(os.devnull, "w"); import minisweagent; sys.stdout = sys.__stdout__; print(os.path.dirname(minisweagent.__file__))')/config/benchmarks/swebench_backticks.yaml"
    if [[ ! -f "$BASE_CFG" ]]; then
      echo "ERROR: base config not found at $BASE_CFG" >&2
      exit 3
    fi

    mini-extra swebench \
      --subset nebius/SWE-rebench-leaderboard \
      --split test \
      --filter "$REGEX" \
      --workers 1 \
      --model-class litellm_textbased \
      -c "$BASE_CFG" \
      -c "$OUT_DIR/agent_config.yaml" \
      -o "$OUT_DIR" 2>&1 | tee "logs/${RUN_ID}_agent.log"
    ;;

  swe-agent)
    # SWE-agent harness — see scripts/swe_agent_run.sh for the wiring
    bash scripts/swe_agent_run.sh "$RUN_ID" "$MODEL_NAME" "$API_BASE" 2>&1 | tee "logs/${RUN_ID}_agent.log"
    ;;

  *)
    echo "unknown harness: $HARNESS (expected: mini | swe-agent)" >&2
    exit 2
    ;;
esac

echo
echo "==> Evaluating predictions"
python -m swebench.harness.run_evaluation \
  --dataset_name nebius/SWE-rebench-leaderboard \
  --split test \
  --predictions_path "$OUT_DIR/preds.json" \
  --max_workers 4 \
  --cache_level instance \
  --namespace swerebench \
  --run_id "$RUN_ID" 2>&1 | tee "logs/${RUN_ID}_eval.log"

echo
echo "==> Summary"
INSTANCES_JSON="${INSTANCES_REGEX_FILE%.regex}.json"
python scripts/summarize.py "$RUN_ID" "$MODEL_NAME" "$INSTANCES_JSON"
