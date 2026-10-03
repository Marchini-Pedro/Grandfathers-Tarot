"""Lists the size of every .md file of the repo and fails (exit 1) when one reaches the limit.

The rule (CLAUDE.md): a .md file must stay under 100 KB; at 100 KB it is split into granular files (the old name stays
as the index). A file above WARN_KB is reported as "getting big" so the split can be planned before it is forced.

    python tools/check_docs.py
"""
import os
import sys

LIMIT_KB = 100
WARN_KB = 80

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rows = []

for folder, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]

    for name in files:
        if name.lower().endswith(".md"):
            path = os.path.join(folder, name)
            rows.append((os.path.getsize(path) / 1024.0, os.path.relpath(path, root)))

rows.sort(reverse=True)
failed = 0

for kb, rel in rows:
    flag = ""

    if kb >= LIMIT_KB:
        flag = "  <-- TOO BIG: split it into granular files"
        failed += 1
    elif kb >= WARN_KB:
        flag = "  <-- getting big (limit %d KB)" % LIMIT_KB

    print("%7.1f KB  %s%s" % (kb, rel, flag))

print("docs: %d files, %d over the %d KB limit" % (len(rows), failed, LIMIT_KB))
sys.exit(1 if failed else 0)
