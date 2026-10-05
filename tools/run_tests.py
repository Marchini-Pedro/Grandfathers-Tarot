"""Run every offline harness and enforce the repository's Lua coverage policy."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = ROOT / "scripts/mods/GrandfathersTarot"
POLICY = ROOT / "tools/coverage_policy.json"


def source_lines(path):
    # Same source-line proxy as BetterInventory; this is not branch coverage.
    return {number for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
            if line.strip() and not line.lstrip().startswith("--")}


def coverage_report(parts, policy, runtime_root=RUNTIME_ROOT):
    paths = {path.relative_to(runtime_root).as_posix(): path for path in runtime_root.rglob("*.lua")}
    floors = policy["modules"]
    failures = []
    if set(paths) != set(floors):
        failures.append(f"Coverage policy inventory mismatch: unassigned={sorted(set(paths)-set(floors))}, stale={sorted(set(floors)-set(paths))}")
    for name, floor in {"overall": policy["minimum_percent"], **floors}.items():
        if isinstance(floor, bool) or not isinstance(floor, (int, float)) or not math.isfinite(floor) or not 0 <= floor <= 100:
            raise ValueError(f"Invalid coverage threshold for {name}: {floor!r}")
    hits = {}
    for part in parts:
        if part.get("errors"):
            failures.append(f"Coverage collector errors: {part['errors']}")
        if not part.get("sources"):
            failures.append("Missing Lua coverage evidence")
        for source, lines in part.get("sources", {}).items():
            if not source.startswith("@"):
                continue
            try:
                name = Path(source[1:]).resolve().relative_to(runtime_root.resolve()).as_posix()
            except ValueError:
                continue
            if name in paths:
                hits.setdefault(name, set()).update(lines)
    if not parts:
        failures.append("No Lua coverage parts supplied")
    modules = []
    for name, path in sorted(paths.items()):
        eligible = source_lines(path)
        covered = eligible & hits.get(name, set())
        percent = len(covered) * 100 / len(eligible) if eligible else 100
        floor = floors.get(name)
        passed = floor is not None and percent >= floor
        if not passed:
            failures.append(f"{name}: {percent:.2f}% below {floor}%")
        modules.append({"module": name, "source_lines": len(eligible), "covered_lines": len(covered),
                        "coverage_percent": round(percent, 2), "minimum_percent": floor,
                        "gate_passed": passed, "uncovered_lines": sorted(eligible-covered)})
    total = sum(module["source_lines"] for module in modules)
    covered = sum(module["covered_lines"] for module in modules)
    percent = covered * 100 / total if total else 100
    if percent < policy["minimum_percent"]:
        failures.append(f"Overall coverage {percent:.2f}% below {policy['minimum_percent']}%")
    return {"method": "Lua debug.sethook line events / nonblank, non-comment source lines (not branch coverage)",
            "source_lines": total, "covered_lines": covered, "coverage_percent": round(percent, 2),
            "minimum_percent": policy["minimum_percent"], "modules": modules,
            "failures": failures, "gate_passed": not failures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", choices=("lua55", "luajit21"), default="lua55")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "test-results")
    parser.add_argument("--timeout-seconds", type=float, default=120)
    args = parser.parse_args()
    if not math.isfinite(args.timeout_seconds) or args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be finite and positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    tests = sorted((ROOT / "tools").glob("*_test.py"))
    checks = [ROOT / "tools/check_lua.py", *tests, ROOT / "tools/check_docs.py"]
    results, parts = [], []
    with TemporaryDirectory(prefix="tarot-coverage-") as directory:
        for path in checks:
            environment = os.environ.copy()
            environment["RW_LUA_RUNTIME"] = args.runtime
            environment["PYTHONIOENCODING"] = "utf-8"
            environment.pop("RW_COVERAGE_FILE", None)
            # Python contracts test the collector in their own child process.
            instrument = path in tests and path.name != "coverage_test.py"
            part_path = Path(directory) / (path.stem + ".json")
            if instrument:
                environment["RW_COVERAGE_FILE"] = str(part_path)
            started = time.perf_counter()
            try:
                result = subprocess.run([sys.executable, str(path)], cwd=ROOT, env=environment,
                                        capture_output=True, text=True, encoding="utf-8",
                                        errors="replace", timeout=args.timeout_seconds)
                output = result.stdout + result.stderr
                passed = result.returncode == 0
            except subprocess.TimeoutExpired:
                output, passed = f"Timed out after {args.timeout_seconds} seconds\n", False
            except OSError as error:
                output, passed = str(error), False
            assertions = sum(line.startswith("PASS ") for line in output.splitlines())
            (args.output_dir / (path.stem + ".log")).write_text(output, encoding="utf-8")
            results.append({"test": path.name, "passed": passed, "assertions": assertions,
                            "seconds": round(time.perf_counter()-started, 3)})
            print(f"{'PASS' if passed else 'FAIL'} {path.name}: {assertions} assertions ({results[-1]['seconds']:.2f}s)", flush=True)
            if not passed:
                print(output[-4000:], file=sys.stderr)
            if instrument:
                try:
                    part = json.loads(part_path.read_text(encoding="utf-8"))
                    if part.get("runtime") != args.runtime:
                        raise ValueError("Coverage runtime mismatch")
                    parts.append(part)
                except (OSError, ValueError) as error:
                    parts.append({"errors": [f"{path.name}: {error}"]})
    try:
        coverage = coverage_report(parts, json.loads(POLICY.read_text(encoding="utf-8")))
    except (OSError, ValueError, KeyError, TypeError) as error:
        coverage = {"gate_passed": False, "failures": [f"Invalid coverage evidence/policy: {error}"]}
    report = {"runtime": args.runtime, "tests": results, "assertions": sum(r["assertions"] for r in results),
              "passed": all(r["passed"] for r in results) and coverage["gate_passed"]}
    (args.output_dir / "test-results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (args.output_dir / "lua-coverage.json").write_text(json.dumps(coverage, indent=2), encoding="utf-8")
    print(f"Lua source-line coverage: {coverage.get('coverage_percent', 0):.2f}%")
    for failure in coverage["failures"]:
        print(f"FAIL {failure}", file=sys.stderr)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(f"### {args.runtime}: {'passed' if report['passed'] else 'failed'}\n\n"
                         f"Assertions: {report['assertions']}; source-line coverage: {coverage.get('coverage_percent', 0):.2f}%.\n\n"
                         "Module | Coverage | Minimum\n--- | ---: | ---:\n")
            for module in coverage.get("modules", []):
                stream.write(f"{module['module']} | {module['coverage_percent']}% | {module['minimum_percent']}%\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
