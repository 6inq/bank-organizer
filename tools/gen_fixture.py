import json
import pathlib
import random
import sys

COUNT = 1000
SEED = 6
OUT = pathlib.Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "rs3_items.lua"


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(source):
    data = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
    items = sorted(
        (name, item_id) for name, item_id in data.items()
        if not name.startswith("%") and isinstance(item_id, int)
    )
    sample = random.Random(SEED).sample(items, COUNT)
    lines = [
        "return {",
    ]
    lines += [f"  {{ id = {item_id}, name = {lua_string(name)} }}," for name, item_id in sample]
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {COUNT} items to {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
