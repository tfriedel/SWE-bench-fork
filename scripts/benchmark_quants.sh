#!/usr/bin/env bash
# Sweep multiple Qwen 3.6 quant/variant combinations through the SWE-rebench
# benchmark. For each variant, stop any running Qwen container, start the
# target variant via the user's qwen-moe.sh / qwen.sh launchers, wait for the
# vLLM endpoint to come up, then call scripts/benchmark.sh.
#
# Usage:
#   scripts/benchmark_quants.sh [variant1 variant2 ...]
# (no args = run all defined variants)
#
# Variant table is below — edit to add quants. Each line is:
#   <run_id>|<launcher>|<mode>|<model_name>|<port>
#
# Existing results in results/<run_id>/ are skipped.

set -euo pipefail

QWEN_DIR="/ssdpool/thomas/projects/qwen3.6"
SWE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Order matters: AWQ first because we already have the container up; GGUF and
# 27B require swapping containers (~5 min each load).
VARIANTS=(
  "qwen36_awq|qwen-moe.sh|tp2|qwen3.6-35b-a3b-awq|8021"
  "qwen36_gguf|qwen-moe.sh|gguf|qwen3.6-35b-a3b-gguf|8022"
  "qwen27b_tp2|qwen.sh|tp2|qwen3.6-27b-autoround|8020"
  "qwen27b_bf16|qwen.sh|bf16-tp4|qwen3.6-27b-bf16|8020"
)

declare -A VARIANT_FIELDS
for v in "${VARIANTS[@]}"; do
  IFS='|' read -r run_id _ <<< "$v"
  VARIANT_FIELDS[$run_id]=$v
done

selected=("$@")
if [[ ${#selected[@]} -eq 0 ]]; then
  for v in "${VARIANTS[@]}"; do
    IFS='|' read -r run_id _ <<< "$v"
    selected+=("$run_id")
  done
fi

stop_all_qwen() {
  bash "$QWEN_DIR/qwen-moe.sh" stop 2>&1 | sed 's/^/    /' || true
  bash "$QWEN_DIR/qwen.sh" stop 2>&1 | sed 's/^/    /' || true
}

wait_endpoint() {
  local url="$1"
  local timeout="${2:-360}"
  local t=0
  printf "  waiting for %s/models" "$url"
  until curl -sf -m 2 "$url/models" >/dev/null 2>&1; do
    if (( t >= timeout )); then
      echo " — TIMEOUT after ${timeout}s"
      return 1
    fi
    sleep 5
    t=$((t + 5))
    printf "."
  done
  echo " ready (after ${t}s)"
}

cd "$SWE_DIR"

# Optional: append a suffix to each variant's run_id so different instance sets
# (e.g. instances_20 vs instances_30random) write to separate result dirs and
# summary files without collision. Combine with INSTANCES_REGEX_FILE.
RUN_ID_SUFFIX="${RUN_ID_SUFFIX:-}"

for run_id_base in "${selected[@]}"; do
  spec="${VARIANT_FIELDS[$run_id_base]:-}"
  if [[ -z "$spec" ]]; then
    echo "WARN: unknown variant '$run_id_base' — skipping" >&2
    continue
  fi
  IFS='|' read -r _ launcher mode model port <<< "$spec"
  api_base="http://localhost:${port}/v1"
  run_id="${run_id_base}${RUN_ID_SUFFIX}"

  echo
  echo "############################################################"
  echo "# variant: $run_id"
  echo "#   launcher: $launcher mode=$mode"
  echo "#   model:    $model"
  echo "#   endpoint: $api_base"
  echo "#   instances: ${INSTANCES_REGEX_FILE:-configs/instances_20.regex}"
  echo "############################################################"

  # Skip if final summary already produced (resilient resume).
  safe_model="${model//\//__}"
  if [[ -f "openai__${safe_model}.${run_id}.json" ]]; then
    echo "  results already present; skipping. (delete openai__${safe_model}.${run_id}.json to re-run)"
    continue
  fi

  echo "==> stopping any running Qwen containers"
  stop_all_qwen

  echo "==> starting variant $run_id ($launcher $mode)"
  # `|| true` because the launcher's internal wait_ready may time out (35B
  # AWQ cold-load takes ~7 min) — wait_endpoint below covers the rest.
  bash "$QWEN_DIR/$launcher" start "$mode" 2>&1 | sed 's/^/    /' || true

  # qwen-moe.sh / qwen.sh already wait_ready, but assert one more time.
  if ! wait_endpoint "$api_base" 900; then
    echo "ERROR: $run_id did not come up; skipping" >&2
    continue
  fi

  echo "==> sanity-checking endpoint"
  curl -sf "$api_base/models" | python3 -c "
import json,sys
d=json.load(sys.stdin)['data'][0]
print(f\"    served: {d['id']}, max_model_len={d.get('max_model_len','?')}\")
"

  echo "==> running benchmark"
  bash scripts/benchmark.sh "$run_id" mini "$model" "$api_base"
done

echo
echo "==> all variants done. final summaries:"
for run_id_base in "${selected[@]}"; do
  spec="${VARIANT_FIELDS[$run_id_base]:-}"
  [[ -z "$spec" ]] && continue
  run_id="${run_id_base}${RUN_ID_SUFFIX}"
  IFS='|' read -r _ _ _ model _ <<< "$spec"
  safe_model="${model//\//__}"
  f="openai__${safe_model}.${run_id}.json"
  if [[ -f "$f" ]]; then
    echo "--- $run_id ---"
    python3 -c "
import json
d=json.load(open('$f'))
n=d['submitted_instances']
print(f'  resolved={d[\"resolved_instances\"]}/{n}  unresolved={d[\"unresolved_instances\"]}  empty={d[\"empty_patch_instances\"]}  errors={d[\"error_instances\"]}')
"
  fi
done
