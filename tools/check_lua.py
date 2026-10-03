import sys, os, glob
from lua_test_runtime import LuaRuntime

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

