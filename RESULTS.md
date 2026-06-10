# Qwen 3.6 quant sweep on SWE-rebench (20-instance subset)

Benchmark of three Qwen 3.6 quantizations / variants against a curated set of
20 SWE-rebench instances chosen to span the categories the user cares about
(FastAPI services, geospatial, dataframe, SQL, CLI, frontend / full-stack).

## Setup

- **Dataset:** `nebius/SWE-rebench-leaderboard`, `test` split, filtered to 20 instances (`configs/instances_20.regex`).
- **Harness:** `mini-swe-agent` (`mini-extra swebench`), `litellm_textbased` model class with `swebench_backticks.yaml` action template.
- **Inference:** local OpenAI-compatible endpoints (vLLM tp=2 / llama.cpp) on 2× RTX 3090. Single worker — no parallel agents.
- **Sampling:** `temperature=0.6`, `top_p=0.95`, `max_output_tokens=32768`, `step_limit=250`, `timeout=1800s`.
- **Eval:** `swebench.harness.run_evaluation --namespace swerebench` (per-instance Docker, FAIL_TO_PASS + PASS_TO_PASS).
- **Driver scripts:** `scripts/benchmark.sh`, `scripts/benchmark_quants.sh`.

## Variants

| run id | launcher | mode | model id | port | quant |
|---|---|---|---|---|---|
| `qwen36_awq` | `qwen-moe.sh` | tp2 | `qwen3.6-35b-a3b-awq` | 8021 | AWQ-int4, vLLM, `--reasoning-parser qwen3` |
| `qwen36_gguf` | `qwen-moe.sh` | gguf | `qwen3.6-35b-a3b-gguf` | 8022 | IQ4_XS GGUF, llama.cpp |
| `qwen27b_tp2` | `qwen.sh` | tp2 | `qwen3.6-27b-autoround` | 8020 | autoround-int4, vLLM |
| `qwen27b_bf16` | `qwen.sh` | bf16-tp4 | `qwen3.6-27b-bf16` | 8020 | bfloat16 (full precision), vLLM TP=4 — quality ceiling |

## Headline results

| variant | resolved | unresolved | empty | errors |
|---|---|---|---|---|
| qwen36_awq (35B AWQ-int4) | 7/20 (35%) | 10 | 2 | 1 |
| qwen36_gguf (35B IQ4_XS GGUF) | 6/20 (30%) | 12 | 1 | 1 |
| **qwen27b_tp2 (27B autoround-int4)** | **9/20 (45%)** | 10 | 1 | 0 |
| qwen27b_bf16 (27B bf16, ceiling) | 8/20 (40%) | 11 | 1 | 0 |

The 27B autoround variant beats both 35B quants. The IQ4_XS GGUF underperforms the AWQ-int4 of the same base model. The bf16 ceiling is *not* meaningfully higher than the int4 autoround — at 20 instances with temp=0.6 the difference is noise. **The int4 autoround is at the ceiling**; further quality gain on this hardware would require a different model family, not a higher-precision quant.

## Per-category breakdown

| category | AWQ-35B | GGUF-35B | autoround-27B | bf16-27B |
|---|---|---|---|---|
| fastapi_services | 0/4 | 0/4 | 0/4 | **1/4** |
| geospatial | 2/4 | 2/4 | **3/4** | 2/4 |
| dataframe | 3/4 | 2/4 | 3/4 | 2/4 |
| sql | 1/3 | 1/3 | **2/3** | **2/3** |
| cli | 1/3 | 1/3 | 1/3 | 1/3 |
| frontend_fullstack | 0/2 | 0/2 | 0/2 | 0/2 |

## Per-instance results

| category | instance | AWQ-35B | GGUF-35B | int4-27B | bf16-27B |
|---|---|---|---|---|---|
| fastapi_services | BerriAI__litellm-13868 | unresolved | unresolved | unresolved | unresolved |
| fastapi_services | schemathesis__schemathesis-2985 | unresolved | unresolved | unresolved | RESOLVED |
| fastapi_services | jlowin__fastmcp-1011 | unresolved | error | unresolved | unresolved |
| fastapi_services | vitalik__django-ninja-1427 | unresolved | empty | unresolved | unresolved |
| geospatial | movingpandas__movingpandas-444 | unresolved | unresolved | unresolved | unresolved |
| geospatial | GenericMappingTools__pygmt-4104 | RESOLVED | RESOLVED | RESOLVED | RESOLVED |
| geospatial | SciTools__iris-6719 | unresolved | unresolved | RESOLVED | unresolved |
| geospatial | UXARRAY__uxarray-1369 | RESOLVED | RESOLVED | RESOLVED | RESOLVED |
| dataframe | pandas-dev__pandas-60691 | RESOLVED | unresolved | RESOLVED | RESOLVED |
| dataframe | modin-project__modin-7434 | empty | unresolved | unresolved | unresolved |
| dataframe | pydata__xarray-10035 | RESOLVED | RESOLVED | RESOLVED | unresolved |
| dataframe | lincc-frameworks__nested-pandas-190 | RESOLVED | RESOLVED | RESOLVED | RESOLVED |
| sql | tobymao__sqlglot-4563 | RESOLVED | RESOLVED | RESOLVED | RESOLVED |
| sql | agronholm__sqlacodegen-368 | unresolved | unresolved | unresolved | unresolved |
| sql | reata__sqllineage-723 | unresolved | empty | RESOLVED | RESOLVED |
| cli | BrianPugh__cyclopts-609 | RESOLVED | RESOLVED | RESOLVED | RESOLVED |
| cli | omni-us__jsonargparse-667 | unresolved | unresolved | unresolved | unresolved |
| cli | simonw__files-to-prompt-44 | unresolved | unresolved | unresolved | unresolved |
| frontend_fullstack | marimo-team__marimo-6629 | empty | unresolved | empty | empty |
| frontend_fullstack | avaiga__taipy-2797 | error | unresolved | unresolved | unresolved |

## Observations

- **27B beats 35B in both quants.** 9 vs 7 vs 6. The 27B autoround pickups vs AWQ are SciTools__iris-6719 (geospatial) and reata__sqllineage-723 (sql); it never loses an instance the AWQ solved.
- **bf16 ceiling is statistically indistinguishable from int4 autoround** on this benchmark. 8/20 vs 9/20. Bf16 picked up `schemathesis-2985` (the only fastapi_services solve across any variant) but lost `SciTools__iris-6719` and `pydata__xarray-10035`. Net –1 — within sampling noise at temp=0.6 on 20 instances. **Conclusion: the int4 autoround is at the 27B family ceiling on this hardware. Don't pay for full-precision serving here.**
- **GGUF (IQ4_XS) is slightly weaker than AWQ-int4** on the same 35B base — lost `pandas-dev__pandas-60691`, gained nothing. Action extraction worked fine despite llama.cpp not having `--reasoning-parser qwen3` (model output was already in the THOUGHT/`mswea_bash_command` template the prompt asks for; no inline `<think>` tags observed).
- **fastapi_services and frontend_fullstack are nearly 0/n across the board** — only bf16-27B cracked one fastapi case (`schemathesis-2985`). Both frontend instances (marimo-6629, taipy-2797) are unresolved by every variant. These are the hard tasks for Qwen 3.6 in this harness at 250 steps.
- **Geospatial and dataframe are where the small wins are** — int4-27B scores 3/4 in geospatial and 3/4 in dataframe; AWQ-35B and bf16-27B both score 2/4 in geospatial and 3/4 or 2/4 in dataframe.
- **Empty/error instances vary by run** — model produced no usable patch on marimo-6629 across three runs (AWQ, int4-27B, bf16-27B) and taipy-2797 once (AWQ).

## Files

- `results/<run_id>/preds.json` — agent predictions per variant
- `results/<run_id>/<instance>/...` — full trajectories
- `logs/run_evaluation/<run_id>/...` — per-instance test reports
- `openai__<model>.<run_id>.json` — final eval summary
- `logs/benchmark_quants.log` — full sweep log

## Reproduce

```bash
# pick instances (idempotent — already committed)
python scripts/pick_instances.py

# single variant
bash scripts/benchmark.sh <run_id> mini <model_name> <api_base>

# full sweep (skips variants whose summary file exists)
bash scripts/benchmark_quants.sh
# or pick variants explicitly
bash scripts/benchmark_quants.sh qwen36_gguf qwen27b_tp2
```
