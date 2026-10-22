"""Builds the upload zip for mod.io.

The zip holds only what the client runs: plugin.json, main.lua and every
Lua file under src/. Tests, tools and docs are left out.

Usage (from the plugin folder):
    python tools/build.py

Writes dist/bank-organizer-<version>.zip, with the version read from
plugin.json.
"""

import json
import pathlib
import zipfile

# The plugin folder (this file lives in <plugin>/tools/).
ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    """Collect the plugin's files and write the zip."""
    version = json.loads((ROOT / "plugin.json").read_text(encoding="utf-8"))["version"]
    out = ROOT / "dist" / f"bank-organizer-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    files = [ROOT / "plugin.json", ROOT / "main.lua", *sorted((ROOT / "src").rglob("*.lua"))]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            # Paths inside the zip use forward slashes, as the client expects.
            archive.write(path, path.relative_to(ROOT).as_posix())
    print(f"wrote {out} ({len(files)} files)")


if __name__ == "__main__":
    main()
