#!/usr/bin/env python3
"""Run task-intent JSONL evals through the local LLM sidecar protocol.

This script intentionally stays outside the Swift test target. It invokes a
sidecar command over stdin/stdout using the same request envelope as Donkey's
local task-intent runtime and scores the returned structured JSON.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_EVAL_PATH = Path("evals/task-intent/macos-default-apps-v1.jsonl")
DEFAULT_REPORT_PATH = Path("evals/task-intent/macos-default-apps-v1.latest-report.json")
DEFAULT_SIDECAR = Path("scripts/local-runtime-runners/donkey_runtime_runner.py")
DEFAULT_MODEL_ID = "qwen3-0.6b-q4_0"
SCHEMA_ID = "task_intent_v1"


TASK_DEFINITIONS = [
    {
        "taskType": "app_open",
        "targetApp": {
            "appName": "Local Item",
            "bundleIdentifier": None,
            "titleContains": None,
            "metadata": {"dynamicTarget": "true"},
        },
        "triggerTerms": [],
        "entityRules": [
            {"name": "appName", "required": True, "aliases": {}, "metadata": {}},
        ],
        "workflowSteps": [
            {
                "id": "launch",
                "role": "launchOrFocusApp",
                "summary": "Launch or focus the model-selected local app or item",
                "metadata": {},
            }
        ],
        "observationStrategies": ["accessibility", "windowMetadata"],
        "verificationEntityName": "appName",
        "metadata": {
            "dynamicTarget": "true",
            "modelPlanned": "false",
            "catalogEntry": "generic-app-open",
        },
    },
    {
        "taskType": "local_app_interaction",
        "targetApp": {
            "appName": "Local App",
            "bundleIdentifier": None,
            "titleContains": None,
            "metadata": {"dynamicTarget": "true"},
        },
        "triggerTerms": [],
        "entityRules": [
            {"name": "appName", "required": True, "aliases": {}, "metadata": {}},
            {"name": "goal", "required": True, "aliases": {}, "metadata": {}},
            {"name": "query", "required": False, "aliases": {}, "metadata": {}},
        ],
        "workflowSteps": [
            {
                "id": "launch",
                "role": "launchOrFocusApp",
                "summary": "Launch or focus the target app",
                "metadata": {},
            },
            {
                "id": "observe",
                "role": "observeApp",
                "summary": "Observe the target app state",
                "metadata": {},
            },
            {
                "id": "focus-input",
                "role": "focusControl",
                "summary": "Focus the model-selected search, address, or text control",
                "metadata": {"controlID": "search", "key": "Command+F"},
            },
            {
                "id": "set-text",
                "role": "enterText",
                "summary": "Enter the model-selected text entity",
                "metadata": {"entityName": "query"},
            },
            {
                "id": "return",
                "role": "submit",
                "summary": "Submit the model-planned action",
                "metadata": {"key": "Return"},
            },
        ],
        "observationStrategies": [
            "accessibility",
            "windowMetadata",
            "screenshotForLocalModel",
        ],
        "verificationEntityName": "query",
        "metadata": {
            "dynamicTarget": "true",
            "modelPlanned": "true",
            "plan.allowedTools": ",".join(
                [
                    "app.openOrFocus",
                    "app.observe",
                    "ui.newDocument",
                    "ui.focusSearch",
                    "ui.focusAddressBar",
                    "ui.focusTextEntry",
                    "ui.setText",
                    "ui.pressReturn",
                    "app.verifyCommand",
                    "app.verifyVisibleText",
                ]
            ),
        },
    },
]


@dataclass
class EvalResult:
    case_id: str
    command: str
    expected_app: str
    status: str
    issues: list[str]
    latency_ms: float
    intent: dict[str, Any] | None
    sidecar_metadata: dict[str, str]
    raw_output: str
    stderr: str


def load_cases(path: Path) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            cases.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}:{line_number}: invalid JSONL: {exc}") from exc
    return cases


def context_snippets(cases: list[dict[str, Any]]) -> dict[str, str]:
    snippets: dict[str, str] = {}
    for case in cases:
        app_info = case.get("app") or {}
        app_name = str(app_info.get("name") or "")
        bundle_id = str(app_info.get("bundleIdentifier") or "")
        if not app_name:
            continue
        snippet = f"{app_name} application {bundle_id}".strip()
        snippets.setdefault(app_name, snippet)
    return snippets


def build_request(case: dict[str, Any], model_id: str, snippets: dict[str, str]) -> dict[str, Any]:
    app_info = case.get("app") or {}
    expected = case.get("expected") or {}
    app_name = str(app_info.get("name") or "")
    preferred_app_names = [
        *[str(item) for item in expected.get("requiredAppChain", [])],
        app_name,
    ]
    local_context: list[str] = []
    seen_context: set[str] = set()
    for preferred_name in preferred_app_names:
        snippet = snippets.get(preferred_name)
        if snippet and snippet not in seen_context:
            seen_context.add(snippet)
            local_context.append(snippet)
    fallback_context = [item for item in snippets.values() if item not in seen_context]
    return {
        "command": case["command"],
        "taskDefinitions": TASK_DEFINITIONS,
        "contextSnippets": (local_context + fallback_context)[:8],
        "sourceTraceID": case["id"].replace("/", "-"),
        "modelID": model_id,
        "metadata": {
            "schemaID": SCHEMA_ID,
            "evalCaseID": case["id"],
            "evalSuiteID": case.get("suiteID", ""),
        },
    }


def run_sidecar(
    sidecar: Path,
    request: dict[str, Any],
    *,
    model_id: str,
    timeout_seconds: int,
    python_executable: str,
    extra_env: dict[str, str],
) -> tuple[dict[str, Any], str, float]:
    environment = os.environ.copy()
    environment.update(extra_env)
    environment.setdefault("DONKEY_RUNTIME_ID", "local-llm")
    environment.setdefault("DONKEY_MODEL_ID", model_id)
    environment.setdefault("DONKEY_RUNTIME_ROLE", "taskIntent")
    environment.setdefault("DONKEY_LOCAL_LLM_TIMEOUT_SECONDS", str(timeout_seconds))

    command = [str(sidecar)]
    if sidecar.suffix == ".py":
        command = [python_executable, str(sidecar)]

    started = time.monotonic()
    completed = subprocess.run(
        command,
        input=json.dumps(request),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
        timeout=timeout_seconds + 5,
        check=False,
    )
    latency_ms = (time.monotonic() - started) * 1_000
    if completed.returncode != 0:
        return (
            {
                "outputText": "",
                "metadata": {
                    "reason": "sidecarProcessFailed",
                    "returnCode": str(completed.returncode),
                },
            },
            completed.stderr,
            latency_ms,
        )
    try:
        return json.loads(completed.stdout or "{}"), completed.stderr, latency_ms
    except json.JSONDecodeError:
        return (
            {
                "outputText": "",
                "metadata": {
                    "reason": "sidecarInvalidJSON",
                    "stdoutPreview": completed.stdout[:500],
                },
            },
            completed.stderr,
            latency_ms,
        )


def decode_intent(output_text: str) -> dict[str, Any] | None:
    if not output_text.strip():
        return None
    try:
        value = json.loads(output_text)
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        start = output_text.find("{")
        end = output_text.rfind("}")
        if start >= 0 and end > start:
            try:
                value = json.loads(output_text[start : end + 1])
                return value if isinstance(value, dict) else None
            except json.JSONDecodeError:
                return None
    return None


def score_case(case: dict[str, Any], sidecar_response: dict[str, Any], stderr: str, latency_ms: float) -> EvalResult:
    expected = case["expected"]
    output_text = str(sidecar_response.get("outputText") or "")
    metadata = stringify_metadata(sidecar_response.get("metadata") or {})
    intent = decode_intent(output_text)
    issues: list[str] = []

    if intent is None:
        issues.append("invalid-or-empty-intent-json")
        return EvalResult(
            case_id=case["id"],
            command=case["command"],
            expected_app=expected["targetAppName"],
            status="failed",
            issues=issues,
            latency_ms=latency_ms,
            intent=None,
            sidecar_metadata=metadata,
            raw_output=output_text,
            stderr=stderr,
        )

    task_type = str(intent.get("taskType") or "")
    target_app_name = str(intent.get("targetAppName") or "")
    entities = intent.get("entities") if isinstance(intent.get("entities"), dict) else {}
    normalized_entities = intent.get("normalizedEntities") if isinstance(intent.get("normalizedEntities"), dict) else {}
    intent_metadata = intent.get("metadata") if isinstance(intent.get("metadata"), dict) else {}
    action_plan = intent.get("actionPlan") if isinstance(intent.get("actionPlan"), dict) else {}
    tools = action_plan.get("tools") if isinstance(action_plan.get("tools"), list) else []
    confidence = numeric_confidence(intent.get("confidence"))

    if task_type != expected["taskType"]:
        issues.append(f"task-type expected={expected['taskType']} actual={task_type}")
    if normalize_app_name(target_app_name) != normalize_app_name(expected["targetAppName"]):
        issues.append(f"target-app expected={expected['targetAppName']} actual={target_app_name}")

    app_entity = str(normalized_entities.get("appName") or entities.get("appName") or "")
    if app_entity and normalize_app_name(app_entity) != normalize_app_name(expected["appName"]):
        issues.append(f"app-entity expected={expected['appName']} actual={app_entity}")

    minimum_confidence = float(expected.get("confidenceAtLeast", 0))
    if confidence < minimum_confidence:
        issues.append(f"confidence expected>={minimum_confidence:.2f} actual={confidence:.2f}")

    expected_response_mode = expected.get("responseMode", "action")
    actual_response_mode = str(intent_metadata.get("responseMode") or "action")
    if actual_response_mode != expected_response_mode:
        issues.append(f"response-mode expected={expected_response_mode} actual={actual_response_mode}")

    missing_tools = [tool for tool in expected.get("requiredTools", []) if tool not in tools]
    if missing_tools:
        issues.append(f"missing-tools {','.join(missing_tools)}")

    unexpected_tools = [tool for tool in tools if tool not in allowed_tools()]
    if unexpected_tools:
        issues.append(f"unexpected-tools {','.join(unexpected_tools)}")

    required_app_chain = expected.get("requiredAppChain")
    if required_app_chain:
        actual_app_chain = extract_app_chain(intent)
        if not app_chain_satisfies(actual_app_chain, required_app_chain):
            issues.append(
                "app-chain expected="
                + "->".join(required_app_chain)
                + " actual="
                + ("->".join(actual_app_chain) if actual_app_chain else "<none>")
            )

    query = str(
        normalized_entities.get(action_plan.get("inputEntity") or "query")
        or normalized_entities.get("query")
        or entities.get(action_plan.get("inputEntity") or "query")
        or entities.get("query")
        or ""
    )
    if expected.get("queryOptional") is not True:
        if not query.strip():
            issues.append("missing-query")
        elif not query_matches_any(query, expected.get("queryContainsAny") or []):
            issues.append(f"query-mismatch expected-any={expected.get('queryContainsAny')} actual={query[:120]}")

    status = "passed" if not issues else "failed"
    return EvalResult(
        case_id=case["id"],
        command=case["command"],
        expected_app=expected["targetAppName"],
        status=status,
        issues=issues,
        latency_ms=latency_ms,
        intent=compact_intent(intent),
        sidecar_metadata=metadata,
        raw_output=output_text,
        stderr=stderr,
    )


def numeric_confidence(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def normalize_app_name(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def query_matches_any(query: str, hints: list[str]) -> bool:
    normalized_query = normalize_text(query)
    return any(normalize_text(hint) in normalized_query for hint in hints)


def normalize_text(value: str) -> str:
    return " ".join("".join(character.lower() if character.isalnum() else " " for character in value).split())


def extract_app_chain(intent: dict[str, Any]) -> list[str]:
    candidates: list[Any] = []
    for key in ["appChain", "appSequence", "requiredAppChain"]:
        if key in intent:
            candidates.append(intent.get(key))

    metadata = intent.get("metadata") if isinstance(intent.get("metadata"), dict) else {}
    for key in ["appChain", "appSequence", "requiredAppChain", "sourceApps"]:
        if key in metadata:
            candidates.append(metadata.get(key))

    for candidate in candidates:
        parsed = parse_app_chain(candidate)
        if parsed:
            return parsed
    return []


def parse_app_chain(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not isinstance(value, str) or not value.strip():
        return []
    raw_value = value.strip()
    try:
        decoded = json.loads(raw_value)
    except json.JSONDecodeError:
        decoded = None
    if isinstance(decoded, list):
        return [str(item).strip() for item in decoded if str(item).strip()]
    for separator in ["->", ">", "|", ","]:
        if separator in raw_value:
            return [part.strip() for part in raw_value.split(separator) if part.strip()]
    return [raw_value]


def app_chain_satisfies(actual: list[str], expected: list[str]) -> bool:
    if len(actual) < len(expected):
        return False
    actual_normalized = [normalize_app_name(item) for item in actual]
    expected_normalized = [normalize_app_name(item) for item in expected]
    search_start = 0
    for expected_app in expected_normalized:
        try:
            match_index = actual_normalized.index(expected_app, search_start)
        except ValueError:
            return False
        search_start = match_index + 1
    return True


def allowed_tools() -> set[str]:
    tools: set[str] = set()
    for definition in TASK_DEFINITIONS:
        raw_tools = (definition.get("metadata") or {}).get("plan.allowedTools")
        if isinstance(raw_tools, str):
            tools.update(item.strip() for item in raw_tools.split(",") if item.strip())
    tools.add("app.openOrFocus")
    tools.add("app.verifyCommand")
    return tools


def compact_intent(intent: dict[str, Any]) -> dict[str, Any]:
    return {
        "taskType": intent.get("taskType"),
        "targetAppName": intent.get("targetAppName"),
        "confidence": intent.get("confidence"),
        "needsConfirmation": intent.get("needsConfirmation"),
        "entities": intent.get("entities"),
        "normalizedEntities": intent.get("normalizedEntities"),
        "actionPlan": intent.get("actionPlan"),
        "metadata": intent.get("metadata"),
        "appChain": extract_app_chain(intent),
    }


def stringify_metadata(value: dict[str, Any]) -> dict[str, str]:
    return {str(key): str(item) for key, item in value.items()}


def select_cases(cases: list[dict[str, Any]], app: str | None, limit: int | None) -> list[dict[str, Any]]:
    selected = cases
    if app:
        selected = [
            case for case in selected
            if normalize_app_name(str((case.get("app") or {}).get("name") or "")) == normalize_app_name(app)
        ]
    if limit is not None:
        selected = selected[:limit]
    return selected


def summarize(results: list[EvalResult], suite_id: str, model_id: str, dry_run: bool) -> dict[str, Any]:
    passed = [result for result in results if result.status == "passed"]
    failed = [result for result in results if result.status != "passed"]
    by_app: dict[str, dict[str, int]] = {}
    for result in results:
        item = by_app.setdefault(result.expected_app, {"passed": 0, "failed": 0})
        item[result.status] = item.get(result.status, 0) + 1
    return {
        "suiteID": suite_id,
        "modelID": model_id,
        "dryRun": dry_run,
        "caseCount": len(results),
        "passed": len(passed),
        "failed": len(failed),
        "passRate": (len(passed) / len(results)) if results else 0,
        "averageLatencyMS": average([result.latency_ms for result in results]),
        "byApp": dict(sorted(by_app.items())),
        "failures": [
            {
                "id": result.case_id,
                "command": result.command,
                "expectedApp": result.expected_app,
                "issues": result.issues,
                "intent": result.intent,
                "sidecarMetadata": result.sidecar_metadata,
            }
            for result in failed[:50]
        ],
    }


def average(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def write_report(path: Path, summary: dict[str, Any], results: list[EvalResult]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "summary": summary,
        "results": [
            {
                "id": result.case_id,
                "command": result.command,
                "expectedApp": result.expected_app,
                "status": result.status,
                "issues": result.issues,
                "latencyMS": result.latency_ms,
                "intent": result.intent,
                "sidecarMetadata": result.sidecar_metadata,
                "stderr": result.stderr[-1_000:] if result.stderr else "",
            }
            for result in results
        ],
    }
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evals", type=Path, default=DEFAULT_EVAL_PATH)
    parser.add_argument("--sidecar", type=Path, default=DEFAULT_SIDECAR)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    parser.add_argument("--timeout-seconds", type=int, default=35)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--app", help="run only cases for one app name")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument("--dry-run", action="store_true", help="build requests and validate case selection without invoking sidecar")
    parser.add_argument("--print-failures", action="store_true")
    args = parser.parse_args()

    all_cases = load_cases(args.evals)
    cases = select_cases(all_cases, args.app, args.limit)
    snippets = context_snippets(all_cases)
    if not cases:
        print("No eval cases selected.", file=sys.stderr)
        return 2

    results: list[EvalResult] = []
    extra_env = {"DONKEY_LOCAL_LLM_TIMEOUT_SECONDS": str(args.timeout_seconds)}
    for index, case in enumerate(cases, start=1):
        request = build_request(case, args.model_id, snippets)
        if args.dry_run:
            intent = {
                "taskType": case["expected"]["taskType"],
                "targetAppName": case["expected"]["targetAppName"],
                "confidence": 1.0,
                "needsConfirmation": False,
                "entities": {"appName": case["expected"]["appName"], "query": " ".join(case["expected"].get("queryContainsAny") or [])},
                "normalizedEntities": {"appName": case["expected"]["appName"], "query": " ".join(case["expected"].get("queryContainsAny") or [])},
                "actionPlan": {
                    "tools": case["expected"]["requiredTools"],
                    "inputEntity": "query",
                    "controlID": "",
                    "focusKey": "",
                    "verification": "commandAttempted",
                },
                "metadata": {},
            }
            if case["expected"].get("requiredAppChain"):
                intent["metadata"]["appChain"] = json.dumps(case["expected"]["requiredAppChain"])
                intent["metadata"]["sourceApps"] = json.dumps(case["expected"].get("requiredSourceApps", []))
            response = {"outputText": json.dumps(intent), "metadata": {"dryRun": "true"}}
            stderr = ""
            latency_ms = 0.0
        else:
            print(f"[{index}/{len(cases)}] {case['id']} :: {case['command']}", file=sys.stderr)
            response, stderr, latency_ms = run_sidecar(
                args.sidecar,
                request,
                model_id=args.model_id,
                timeout_seconds=args.timeout_seconds,
                python_executable=args.python,
                extra_env=extra_env,
            )
        results.append(score_case(case, response, stderr, latency_ms))

    suite_id = str(cases[0].get("suiteID") or args.evals.stem)
    summary = summarize(results, suite_id, args.model_id, args.dry_run)
    write_report(args.report, summary, results)
    print(json.dumps(summary, indent=2, sort_keys=True))
    print(f"report: {args.report}")

    if args.print_failures:
        for failure in summary["failures"]:
            print(json.dumps(failure, indent=2, sort_keys=True), file=sys.stderr)

    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
