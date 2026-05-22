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
DONKEY_MODEL_ID=qwen3-0.6b-q4_0 \
python3 scripts/evals/run_task_intent_sidecar_evals.py --app Safari --limit 3
```

Run the full suite:

```bash
DONKEY_RUNTIME_ID=local-llm \
DONKEY_MODEL_ID=qwen3-0.6b-q4_0 \
python3 scripts/evals/run_task_intent_sidecar_evals.py
```

The runner writes a JSON report to
`evals/task-intent/macos-default-apps-v1.latest-report.json` by default. That
report is generated output and should normally be treated as a local artifact,
not source data.
