# Task Intent Eval Fixtures

This directory contains model-facing task-intent eval data. The fixtures are
JSONL so they can be used by local Python runners, hosted eval jobs, or future
model-comparison scripts without adding app-specific Swift test code.

## macos-default-apps-v1

- `macos-default-apps-v1.jsonl`: one eval case per line.
- `macos-default-apps-v1.manifest.json`: suite summary, included apps, and
  schema notes.
- `scripts/evals/generate_macos_app_task_intent_evals.py`: source generator and
  freshness checker.
- `scripts/evals/run_task_intent_sidecar_evals.py`: sidecar eval runner and
  scorer.

Each case contains a natural-language `command`, the expected target app, and
minimum structured-output expectations such as `taskType`, `requiredTools`, and
query hints. Cases can also require a multi-app chain, for example
`Stocks -> Numbers` for a live market-data table. The current sidecar-compatible
shape scores that through `metadata.appChain` while keeping `targetAppName` as
the final destination app. The evals intentionally test app and action selection
rather than hardcoding exact final prose, URLs, or live data.

Only apps included as eval targets are persisted in these fixtures. Source app
inventories and non-target app decisions are intentionally omitted from public
artifacts for privacy.

Regenerate after editing the generator:

```bash
python3 scripts/evals/generate_macos_app_task_intent_evals.py
python3 scripts/evals/generate_macos_app_task_intent_evals.py --check
```

Smoke-test the runner without invoking a model:

```bash
python3 scripts/evals/run_task_intent_sidecar_evals.py --dry-run --limit 10
```

Run a small live sidecar sample against the local LLM sidecar:

```bash
DONKEY_RUNTIME_ID=local-llm \
DONKEY_MODEL_ID=qwen2.5-0.5b-instruct-q4_k_m \
python3 scripts/evals/run_task_intent_sidecar_evals.py --app Safari --limit 3
```

Run the full suite:

```bash
DONKEY_RUNTIME_ID=local-llm \
DONKEY_MODEL_ID=qwen2.5-0.5b-instruct-q4_k_m \
python3 scripts/evals/run_task_intent_sidecar_evals.py
```

Compare the small local-model candidates before changing the packaged default:

```bash
python3 scripts/evals/run_task_intent_sidecar_evals.py \
  --compare-default-candidates
```

For a quick smoke test, keep the same comparison path but limit the suite:

```bash
python3 scripts/evals/run_task_intent_sidecar_evals.py \
  --compare-default-candidates \
  --limit 10
```

Candidate GGUF downloads are stored under the gitignored
`evals/task-intent/model-cache/` directory. Per-model reports and the ranked
comparison summary are written under the gitignored
`evals/task-intent/model-comparison/` directory. The comparison decision ranks
models by pass rate first, then failed count, average latency, and model size.
The candidate list comes from
`evals/task-intent/local-llm-model-candidates.json`; pass
`--candidate-config path/to/candidates.json` to test another candidate set. The
single-model default comes from `config/local-llm-models.json`; pass
`--model-config path/to/config.json` to test another packaged-default config.

The runner writes a JSON report to
`evals/task-intent/macos-default-apps-v1.latest-report.json` by default. That
report is generated output and should normally be treated as a local artifact,
not source data.
