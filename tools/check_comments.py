"""Checks that every source file in the plugin is commented.

The Plugin Hub asks for clearly commented code so the Plugin Moderator
can review it. This check enforces the plugin's own rule:

  * every Lua and Python file starts with a comment (or, for Python, a
    docstring) that says what the file is for
  * every Lua function definition has a comment on the line(s) directly
    above it: "function X(", "local function X(" and "X = function("
  * every Python function and class has a docstring, or a comment on the
    line directly above it

Usage (from the plugin folder):
    python tools/check_comments.py

Prints every problem as "file:line: message" and exits with 1 when there
are any, so it can run in a test or build.
"""

import pathlib
import re
import sys

# The plugin folder (this file lives in <plugin>/tools/).
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Folders that are checked. dist/ holds build output and is skipped.
FOLDERS = ["src", "tests", "tools"]

# Single files at the plugin root that are checked too.
FILES = ["main.lua"]

# A Lua line that defines a named function, in any of the three forms.
LUA_FUNCTION = re.compile(
    r"^\s*(?:local\s+)?function\s+[\w.:]+\s*\("
    r"|^\s*(?:local\s+)?[\w.\[\]\"']+\s*=\s*function\s*\("
)

# A Python line that starts a function or class.
PY_DEFINITION = re.compile(r"^\s*(?:async\s+)?(?:def|class)\s+\w+")


def source_files():
    """Return every .lua and .py file that must be commented, sorted."""
    found = [ROOT / name for name in FILES if (ROOT / name).exists()]
    for folder in FOLDERS:
        for path in sorted((ROOT / folder).rglob("*")):
            if path.suffix in (".lua", ".py") and "__pycache__" not in path.parts:
                found.append(path)
    return found


def previous_code_line(lines, index):
    """Return the nearest non-blank line above lines[index], or ""."""
    for back in range(index - 1, -1, -1):
        if lines[back].strip():
            return lines[back].strip()
    return ""


def first_code_line(lines):
    """Return the first non-blank line of a file, stripped, or ""."""
    for line in lines:
        if line.strip():
            return line.strip()
    return ""


def is_one_liner(line):
    """Return True for a whole function written on one line.

    For example "function db:Get(key) return self.data[key] end".
    """
    return bool(LUA_FUNCTION.match(line)) and re.search(r"\bend[,)]*\s*$", line.strip()) is not None


def lua_comment_above(lines, index):
    """Return True when the Lua function at lines[index] has a comment.

    A run of one-line functions written one after another (small helper
    methods) shares the comment above the first one in the run.
    """
    back = index - 1
    while back >= 0:
        text = lines[back].strip()
        if not text:
            back -= 1
            continue
        if is_one_liner(lines[index]) and is_one_liner(text):
            back -= 1
            continue
        return text.startswith("--")
    return False


def check_lua(path, lines):
    """Return the problems found in one Lua file as (line, message) pairs."""
    problems = []
    if not first_code_line(lines).startswith("--"):
        problems.append((1, "the file needs a header comment"))
    for index, line in enumerate(lines):
        if LUA_FUNCTION.match(line) and not lua_comment_above(lines, index):
            problems.append((index + 1, "this function needs a comment above it"))
    return problems


def has_docstring(lines, index):
    """Return True when the definition at lines[index] has a docstring.

    The definition may span several lines (long argument lists), so the
    docstring is looked for on the first non-blank line after the line
    that ends with ":".
    """
    end = index
    while end < len(lines) and not lines[end].rstrip().endswith(":"):
        end += 1
    for after in range(end + 1, len(lines)):
        text = lines[after].strip()
        if text:
            return text.startswith('"""') or text.startswith("'''")
    return False


def check_python(path, lines):
    """Return the problems found in one Python file as (line, message) pairs."""
    problems = []
    first = first_code_line(lines)
    if not (first.startswith("#") or first.startswith('"""')):
        problems.append((1, "the file needs a header comment or docstring"))
    for index, line in enumerate(lines):
        if PY_DEFINITION.match(line):
            commented = previous_code_line(lines, index).startswith("#")
            if not commented and not has_docstring(lines, index):
                problems.append((index + 1, "this definition needs a docstring or a comment above it"))
    return problems


def main():
    """Check every source file, print the problems, and return the exit code."""
    total = 0
    for path in source_files():
        lines = path.read_text(encoding="utf-8").splitlines()
        checker = check_lua if path.suffix == ".lua" else check_python
        for number, message in checker(path, lines):
            total += 1
            print(path.relative_to(ROOT).as_posix() + ":" + str(number) + ": " + message)
    print(str(total) + " comment problem" + ("" if total == 1 else "s"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
