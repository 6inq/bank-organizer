"""Runs Bank Organizer's Lua tests under Lua 5.4 (via the lupa package).

Every tests/*_test.lua file returns a table of test functions. Each file
runs in its own fresh Lua runtime, so nothing leaks between files. A test
passes when it returns without an error.

Usage (from the plugin folder):
    python -m pip install lupa
    python tests/run.py

Prints each failure and a summary, and exits with 1 when anything fails.
The comment check (tools/check_comments.py) runs too: code without the
required comments fails the suite.
"""

import pathlib
import subprocess
import sys

from lupa import lua54

# The plugin folder (this file lives in <plugin>/tests/).
ROOT = pathlib.Path(__file__).resolve().parent.parent

# The Lua side of the runner: sets up require() so plugin modules
# ("src/...") and test helpers ("assert", "harness") are found, loads one
# test file and calls every test in name order, catching errors.
RUNNER = r"""
local root, file = ...
package.path = root .. "/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local suite = dofile(file)
local names = {}
for name in pairs(suite) do names[#names + 1] = name end
table.sort(names)
local results = {}
for _, name in ipairs(names) do
  local ok, err = pcall(suite[name])
  results[#results + 1] = { name = name, ok = ok, err = ok and "" or tostring(err) }
end
return results
"""


def run_file(path):
    """Run one test file in a fresh Lua runtime.

    Returns a list of (test name, passed, error text).
    """
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    results = lua.execute(RUNNER, ROOT.as_posix(), path.as_posix())
    return [(r["name"], r["ok"], r["err"]) for r in results.values()]


def main():
    """Run every test file and print failures and a summary.

    Returns 1 when any test failed, 0 otherwise.
    """
    files = sorted((ROOT / "tests").glob("*_test.lua"))
    passed = failed = 0
    for path in files:
        for name, ok, err in run_file(path):
            if ok:
                passed += 1
            else:
                failed += 1
                print(f"FAIL {path.stem} :: {name}\n     {err}")
    print(f"{passed} passed, {failed} failed across {len(files)} files")
    # Every file and function must be commented (Plugin Hub review rule).
    check = subprocess.run([sys.executable, str(ROOT / "tools" / "check_comments.py")], capture_output=True, text=True)
    if check.returncode != 0:
        failed += 1
        print("FAIL comment check")
        print(check.stdout)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
