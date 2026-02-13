#!/usr/bin/env python3
"""Q&A quality test runner for sandbox configuration validation.

Usage:
    python tests/qa_quality/run_quality_test.py run --sandbox <path> [--label <label>]
    python tests/qa_quality/run_quality_test.py compare <baseline.json> <current.json>

The test runner:
1. Reads questions from questions.json
2. Sends each question to the Q&A system via the sandbox
3. Records the response, timing, and token usage
4. Outputs results to results/<label>_<timestamp>.json
5. Optionally compares two result sets for regression detection
"""

import argparse
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


TESTS_DIR = Path(__file__).parent
QUESTIONS_FILE = TESTS_DIR / "questions.json"
QUALITY_FILE = TESTS_DIR / "expected_quality.json"
RESULTS_DIR = TESTS_DIR / "results"


def load_questions() -> dict:
    """Load test questions from questions.json."""
    with open(QUESTIONS_FILE) as f:
        return json.load(f)


def load_quality_config() -> dict:
    """Load quality scoring configuration."""
    with open(QUALITY_FILE) as f:
        return json.load(f)


def ask_question(sandbox_path: str, question: str) -> dict:
    """Send a question to the Q&A system and capture the response.

    Uses claude-mpm run in the sandbox directory, matching the
    production invocation in chat_service.py:706-720.

    Returns:
        Dict with keys: response, elapsed_seconds, input_tokens,
        output_tokens, error
    """
    start = time.monotonic()

    try:
        result = subprocess.run(
            [
                "claude-mpm",
                "run",
                "--non-interactive",
                "--no-hooks",
                "--no-tickets",
                "--launch-method",
                "subprocess",
                "-i",
                question,
                "--",
                "--output-format",
                "json",
                "--verbose",
            ],
            cwd=sandbox_path,
            capture_output=True,
            text=True,
            timeout=120,
        )

        elapsed = time.monotonic() - start

        # Parse JSON output for token usage
        output = result.stdout.strip()
        input_tokens = 0
        output_tokens = 0
        response_text = output

        try:
            parsed = json.loads(output)
            if isinstance(parsed, dict):
                response_text = parsed.get("result", output)
                usage = parsed.get("usage", {})
                input_tokens = usage.get("input_tokens", 0)
                output_tokens = usage.get("output_tokens", 0)
        except json.JSONDecodeError:
            pass  # Non-JSON output, use raw text

        return {
            "response": response_text,
            "elapsed_seconds": round(elapsed, 2),
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "error": None if result.returncode == 0 else result.stderr,
        }

    except subprocess.TimeoutExpired:
        elapsed = time.monotonic() - start
        return {
            "response": "",
            "elapsed_seconds": round(elapsed, 2),
            "input_tokens": 0,
            "output_tokens": 0,
            "error": "Timeout after 120 seconds",
        }
    except Exception as e:
        elapsed = time.monotonic() - start
        return {
            "response": "",
            "elapsed_seconds": round(elapsed, 2),
            "input_tokens": 0,
            "output_tokens": 0,
            "error": str(e),
        }


def check_keywords(response: str, expected_keywords: list[str]) -> dict:
    """Check if expected keywords appear in the response.

    Returns:
        Dict with found/missing keyword lists and match ratio.
    """
    response_lower = response.lower()
    found = [kw for kw in expected_keywords if kw.lower() in response_lower]
    missing = [kw for kw in expected_keywords if kw.lower() not in response_lower]
    total = len(expected_keywords) if expected_keywords else 1

    return {
        "found": found,
        "missing": missing,
        "match_ratio": round(len(found) / total, 2),
    }


def run_tests(sandbox_path: str, label: str) -> dict:
    """Run all test questions and collect results."""
    questions_data = load_questions()
    quality_config = load_quality_config()

    results = {
        "metadata": {
            "label": label,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "sandbox_path": sandbox_path,
            "questions_version": questions_data["version"],
            "quality_version": quality_config["version"],
            "total_questions": len(questions_data["questions"]),
        },
        "results": [],
        "summary": {},
    }

    for q in questions_data["questions"]:
        print(f"  [{q['id']}] {q['question'][:60]}...", flush=True)

        answer = ask_question(sandbox_path, q["question"])
        keyword_check = check_keywords(
            answer["response"], q.get("expected_keywords", [])
        )

        results["results"].append(
            {
                "question_id": q["id"],
                "category": q["category"],
                "question": q["question"],
                "response": answer["response"],
                "elapsed_seconds": answer["elapsed_seconds"],
                "input_tokens": answer["input_tokens"],
                "output_tokens": answer["output_tokens"],
                "error": answer["error"],
                "keyword_match": keyword_check,
                "manual_scores": {
                    "accuracy": None,
                    "completeness": None,
                    "citation_quality": None,
                },
            }
        )

    # Compute summary statistics
    total_time = sum(r["elapsed_seconds"] for r in results["results"])
    total_input = sum(r["input_tokens"] for r in results["results"])
    total_output = sum(r["output_tokens"] for r in results["results"])
    error_count = sum(1 for r in results["results"] if r["error"])
    avg_keyword_match = sum(
        r["keyword_match"]["match_ratio"] for r in results["results"]
    ) / len(results["results"])

    results["summary"] = {
        "total_questions": len(results["results"]),
        "errors": error_count,
        "total_elapsed_seconds": round(total_time, 2),
        "avg_elapsed_seconds": round(total_time / len(results["results"]), 2),
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "avg_input_tokens": total_input // max(len(results["results"]), 1),
        "avg_keyword_match_ratio": round(avg_keyword_match, 2),
    }

    return results


def compare_results(baseline_path: str, current_path: str) -> dict:
    """Compare two result sets for regression detection."""
    with open(baseline_path) as f:
        baseline = json.load(f)
    with open(current_path) as f:
        current = json.load(f)

    comparison = {
        "baseline_label": baseline["metadata"]["label"],
        "current_label": current["metadata"]["label"],
        "regressions": [],
        "improvements": [],
        "token_changes": {},
    }

    # Compare token usage
    bl_tokens = baseline["summary"]["avg_input_tokens"]
    cu_tokens = current["summary"]["avg_input_tokens"]
    comparison["token_changes"] = {
        "baseline_avg_input_tokens": bl_tokens,
        "current_avg_input_tokens": cu_tokens,
        "change_tokens": cu_tokens - bl_tokens,
        "change_percent": (round((cu_tokens - bl_tokens) / max(bl_tokens, 1) * 100, 1)),
    }

    # Compare keyword match ratios per question
    bl_results = {r["question_id"]: r for r in baseline["results"]}
    cu_results = {r["question_id"]: r for r in current["results"]}

    for qid in bl_results:
        if qid not in cu_results:
            continue
        bl_match = bl_results[qid]["keyword_match"]["match_ratio"]
        cu_match = cu_results[qid]["keyword_match"]["match_ratio"]

        if cu_match < bl_match - 0.1:
            comparison["regressions"].append(
                {
                    "question_id": qid,
                    "baseline_match": bl_match,
                    "current_match": cu_match,
                    "delta": round(cu_match - bl_match, 2),
                }
            )
        elif cu_match > bl_match + 0.1:
            comparison["improvements"].append(
                {
                    "question_id": qid,
                    "baseline_match": bl_match,
                    "current_match": cu_match,
                    "delta": round(cu_match - bl_match, 2),
                }
            )

    return comparison


def main():
    parser = argparse.ArgumentParser(description="Q&A quality test runner")
    subparsers = parser.add_subparsers(dest="command")

    # Run tests
    run_parser = subparsers.add_parser("run", help="Run quality tests")
    run_parser.add_argument(
        "--sandbox", required=True, help="Path to sandbox directory"
    )
    run_parser.add_argument(
        "--label",
        default="test",
        help="Label for this test run (e.g., 'old-config', 'new-config')",
    )

    # Compare results
    compare_parser = subparsers.add_parser("compare", help="Compare two result sets")
    compare_parser.add_argument("baseline", help="Path to baseline results JSON")
    compare_parser.add_argument("current", help="Path to current results JSON")

    args = parser.parse_args()

    if args.command == "run":
        print(f"Running Q&A quality tests on {args.sandbox}")
        print(f"Label: {args.label}")
        print()

        results = run_tests(args.sandbox, args.label)

        # Save results
        RESULTS_DIR.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = RESULTS_DIR / f"{args.label}_{timestamp}.json"
        with open(output_path, "w") as f:
            json.dump(results, f, indent=2)

        print()
        print(f"Results saved to {output_path}")
        print()
        print("Summary:")
        for key, value in results["summary"].items():
            print(f"  {key}: {value}")
        print()
        print(
            "NOTE: Manual scoring (accuracy, completeness, citation_quality) "
            "must be filled in by reviewing each response in the results file."
        )

    elif args.command == "compare":
        comparison = compare_results(args.baseline, args.current)

        print("Comparison Results:")
        print(f"  Baseline: {comparison['baseline_label']}")
        print(f"  Current:  {comparison['current_label']}")
        print()
        print("Token Changes:")
        tc = comparison["token_changes"]
        print(f"  Baseline avg input tokens: {tc['baseline_avg_input_tokens']}")
        print(f"  Current avg input tokens:  {tc['current_avg_input_tokens']}")
        print(f"  Change: {tc['change_tokens']} ({tc['change_percent']}%)")
        print()
        print(f"Regressions: {len(comparison['regressions'])}")
        for r in comparison["regressions"]:
            print(
                f"  {r['question_id']}: "
                f"{r['baseline_match']} -> {r['current_match']} "
                f"({r['delta']:+.2f})"
            )
        print(f"Improvements: {len(comparison['improvements'])}")
        for i in comparison["improvements"]:
            print(
                f"  {i['question_id']}: "
                f"{i['baseline_match']} -> {i['current_match']} "
                f"({i['delta']:+.2f})"
            )

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
