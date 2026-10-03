import sys, os, glob
sys.path.insert(0, os.environ.get("PYLIBS", r"C:\Users\ayko4\AppData\Local\Temp\claude\c--XboxGames-Warhammer-40-000--Darktide-Content\9da40c72-f459-4d9d-ab4b-3023fa21e2f5\scratchpad\pylibs"))
from lupa import LuaRuntime

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
compile_fn = lua.eval("function(src, name) local f, err = (loadstring or load)(src, name) if f then return true, nil else return false, err end end")

bad = 0
files = glob.glob(os.path.join(root, "**", "*.lua"), recursive=True) + [os.path.join(root, "RealmsWaves.mod")]
for path in sorted(files):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    ok, err = compile_fn(src, "@" + os.path.relpath(path, root))
    print(("OK   " if ok else "FAIL ") + os.path.relpath(path, root) + ("" if ok else "  -> " + str(err)))
    bad += 0 if ok else 1
print("files:", len(files), "failures:", bad)
sys.exit(1 if bad else 0)

