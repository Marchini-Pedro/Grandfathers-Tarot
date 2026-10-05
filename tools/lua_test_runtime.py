"""Select the test VM and optionally collect real Lua source line events."""
import atexit
import importlib
import json
import os
from pathlib import Path
import sys

if os.environ.get("PYLIBS"):
    sys.path.insert(0, os.environ["PYLIBS"])

RUNTIME_ROOT = Path(__file__).resolve().parents[1] / "scripts/mods/GrandfathersTarot"
BACKEND = os.environ.get("RW_LUA_RUNTIME", "lua55")
if BACKEND not in ("lua55", "luajit21"):
    raise ValueError("RW_LUA_RUNTIME must be lua55 or luajit21")
_LuaRuntime = importlib.import_module(f"lupa.{BACKEND}").LuaRuntime
_runtimes = []


def LuaRuntime(*args, **kwargs):
    runtime = _LuaRuntime(*args, **kwargs)
    if os.environ.get("RW_COVERAGE_FILE"):
        # LuaJIT traces can bypass line hooks. Coverage runs must use the interpreter.
        runtime.execute(r'''
            local root = ...
            if jit then jit.off() end
            __rw_coverage = {}
            debug.sethook(function(_, line)
                local source = debug.getinfo(2, "S").source
                if line > 0 and source:sub(1, #root) == root then
                    local lines = __rw_coverage[source]
                    if not lines then lines = {}; __rw_coverage[source] = lines end
                    lines[line] = true
                end
            end, "l")
        ''', "@" + RUNTIME_ROOT.as_posix() + "/")
        _runtimes.append(runtime)
    return runtime


@atexit.register
def write_coverage():
    destination = os.environ.get("RW_COVERAGE_FILE")
    if not destination:
        return
    sources = {}
    errors = []
    for runtime in _runtimes:
        try:
            snapshot = runtime.execute("debug.sethook(); return __rw_coverage")
            for source, lines in snapshot.items():
                sources.setdefault(source, set()).update(int(line) for line in lines)
        except Exception as error:
            errors.append(str(error))
    path = Path(destination)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "runtime": BACKEND,
        "sources": {source: sorted(lines) for source, lines in sorted(sources.items())},
        "errors": errors,
    }, indent=2), encoding="utf-8")
