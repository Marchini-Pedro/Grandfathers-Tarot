"""Prove the gate fails closed and the collector records executed Lua files."""
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
from tempfile import TemporaryDirectory

from run_tests import ROOT, coverage_report


def main():
    with TemporaryDirectory(prefix="tarot-coverage-contract-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        for name in ("a/same.lua", "b/same.lua"):
            path = runtime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("local value = 1\nreturn value\n", encoding="utf-8")
        policy = {"minimum_percent": 50, "modules": {"a/same.lua": 100, "b/same.lua": 0}}
        parts = [{"sources": {
            "@" + str(runtime / "a/same.lua"): [1, 2, 999],
            "@" + str(root / "foreign/b/same.lua"): [1, 2],
            "<python>": [1, 2],
        }}]
        report = coverage_report(parts, policy, runtime)
        assert report["gate_passed"] and report["coverage_percent"] == 50
        assert report["modules"][1]["covered_lines"] == 0
        assert report["modules"][1]["uncovered_lines"] == [1, 2]
        print("PASS gate: exact recursive paths ignore foreign files, snippets and out-of-range lines")
        policy["modules"]["b/same.lua"] = 1
        assert not coverage_report(parts, policy, runtime)["gate_passed"]
        print("PASS gate: a single module below its floor fails despite adequate overall coverage")
        policy["modules"]["b/same.lua"] = 0
        policy["minimum_percent"] = 51
        assert not coverage_report(parts, policy, runtime)["gate_passed"]
        print("PASS gate: overall threshold fails independently")
        policy["minimum_percent"] = 50
        (runtime / "new.lua").write_text("return true\n", encoding="utf-8")
        assert not coverage_report(parts, policy, runtime)["gate_passed"]
        print("PASS gate: every new Lua module requires an explicit coverage policy")
        (runtime / "new.lua").unlink()
        policy["modules"]["removed.lua"] = 0
        assert not coverage_report(parts, policy, runtime)["gate_passed"]
        del policy["modules"]["removed.lua"]
        print("PASS gate: stale policy entries fail")
        for evidence in ([], [{}], [*parts, {"errors": ["lost VM"]}]):
            assert not coverage_report(evidence, policy, runtime)["gate_passed"]
        print("PASS gate: absent/empty coverage or collector errors fail closed")
        for invalid in (-1, 101, float("nan"), float("inf"), True, "50"):
            bad_policy = {"minimum_percent": invalid, "modules": policy["modules"]}
            try:
                coverage_report(parts, bad_policy, runtime)
            except ValueError:
                pass
            else:
                raise AssertionError(f"accepted invalid threshold: {invalid!r}")
        print("PASS gate: malformed/non-finite thresholds fail closed")
        # Fresh process, two VMs: an uncalled function's body must not count as hit.
        source = root / "probe.lua"
        source.write_text("local function unused()\n  return 'missed'\nend\nreturn 42\n", encoding="utf-8")
        other = root / "other.lua"
        other.write_text("return 7\n", encoding="utf-8")
        destination = root / "part.json"
        environment = os.environ.copy()
        environment["RW_COVERAGE_FILE"] = str(destination)
        environment["RW_PROBE_ROOT"] = str(root)
        code = (
            "import os; from pathlib import Path; import lua_test_runtime as support; "
            "support.RUNTIME_ROOT=Path(os.environ['RW_PROBE_ROOT']); "
            "a=support.LuaRuntime(); b=support.LuaRuntime(); "
            "p=(support.RUNTIME_ROOT/'probe.lua').as_posix(); "
            "a.globals().probe_path=p; b.globals().probe_path=(support.RUNTIME_ROOT/'other.lua').as_posix(); "
            "assert support.BACKEND!='luajit21' or a.eval('not jit.status()'); "
            "assert a.execute('return dofile(probe_path)')==42; "
            "assert b.execute('return dofile(probe_path)')==7"
        )
        subprocess.run([sys.executable, "-c", code], cwd=ROOT / "tools", env=environment, check=True, timeout=30)
        evidence = json.loads(destination.read_text(encoding="utf-8"))
        assert not evidence["errors"]
        assert evidence["runtime"] == environment.get("RW_LUA_RUNTIME", "lua55")
        lines = evidence["sources"]["@" + source.as_posix()]
        assert 4 in lines and 2 not in lines
        assert 1 in evidence["sources"]["@" + other.as_posix()]
        print("PASS collector: merges multiple VMs and excludes unexecuted function bodies")
        # Exercise the actual CLI on a tiny standalone repository, including failures.
        fixture = root / "checkout"
        tools = fixture / "tools"
        tools.mkdir(parents=True)
        modules = fixture / "scripts/mods/RealmsWaves"
        modules.mkdir(parents=True)
        (modules / "probe.lua").write_text("return 42\n", encoding="utf-8")
        for name in ("run_tests.py", "lua_test_runtime.py"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        for name in ("check_lua.py", "check_docs.py"):
            (tools / name).write_text("pass\n", encoding="utf-8")
        (tools / "coverage_policy.json").write_text(json.dumps({"minimum_percent": 100, "modules": {"probe.lua": 100}}), encoding="utf-8")
        behavior = tools / "behavior_test.py"
        body = ("from lua_test_runtime import LuaRuntime, RUNTIME_ROOT\n"
                "lua=LuaRuntime(); lua.globals().probe_path=(RUNTIME_ROOT/'probe.lua').as_posix()\n"
                "assert lua.execute('return dofile(probe_path)')==42\nprint('PASS tiny behavior')\n")
        command = [sys.executable, str(tools / "run_tests.py"), "--runtime", environment.get("RW_LUA_RUNTIME", "lua55"),
                   "--output-dir", str(fixture / "results")]
        behavior.write_text(body, encoding="utf-8")
        assert subprocess.run(command, env=environment, capture_output=True, timeout=30).returncode == 0
        behavior.write_text(body + "raise AssertionError('behavior regression')\n", encoding="utf-8")
        assert subprocess.run(command, env=environment, capture_output=True, timeout=30).returncode != 0
        print("PASS runner: successful suite exits zero and a behavior failure propagates")
        behavior.write_text("import time\ntime.sleep(2)\n", encoding="utf-8")
        assert subprocess.run(command + ["--timeout-seconds", "0.5"], env=environment, capture_output=True, timeout=30).returncode != 0
        assert "Timed out" in (fixture / "results/behavior_test.log").read_text(encoding="utf-8")
        print("PASS runner: a timed-out harness fails and retains its diagnostic")
        behavior.write_text("print('PASS no Lua instrumentation')\n", encoding="utf-8")
        assert subprocess.run(command, env=environment, capture_output=True, timeout=30).returncode != 0
        result = json.loads((fixture / "results/lua-coverage.json").read_text(encoding="utf-8"))
        assert not result["gate_passed"] and any("behavior_test.py" in failure for failure in result["failures"])
        print("PASS runner: a passing harness with missing coverage evidence still fails the gate")


if __name__ == "__main__":
    main()
