"""Builds tests/fixtures/rs3_items.lua: 1,000 real RS3 items for tests.

The source is a JSON file mapping item names to item ids (an RS3 item name
list). A fixed random sample is taken so the fixture is the same every time
it is rebuilt from the same list.

Usage (from the plugin folder):
    python tools/gen_fixture.py <path to names.json>
"""

import json
import pathlib
import random
import sys

# How many items the fixture holds.
COUNT = 1000

# The random seed, so the sample never changes.
SEED = 6

# Where the fixture is written.
OUT = pathlib.Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "rs3_items.lua"

# The header written at the top of the fixture.
HEADER = [
    "-- Bank Organizer tests: 1,000 real RS3 items (generated data).",
    "--",
    "-- Made by tools/gen_fixture.py: a fixed random sample (seed 6) of item ids",
    "-- and names from an RS3 item name list. Used by the guide's large session",
    "-- tests (tests/guide_scale_test.lua) and classifier tests. Do not edit by",
    "-- hand; run the tool again to refresh it.",
    "",
]


def lua_string(text):
    """Write text as a Lua string literal, escaping backslashes and quotes."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(source):
    """Read the name list, sample COUNT items and write the fixture.

    Names starting with "%" are placeholders in the source list and entries
    whose id is not a whole number are skipped.
    """
    data = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
    items = sorted(
        (name, item_id) for name, item_id in data.items()
        if not name.startswith("%") and isinstance(item_id, int)
    )
    sample = random.Random(SEED).sample(items, COUNT)
    lines = HEADER + ["return {"]
    lines += [f"  {{ id = {item_id}, name = {lua_string(name)} }}," for name, item_id in sample]
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {COUNT} items to {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
