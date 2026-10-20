import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent

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
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    results = lua.execute(RUNNER, ROOT.as_posix(), path.as_posix())
    return [(r["name"], r["ok"], r["err"]) for r in results.values()]


def main():
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
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
