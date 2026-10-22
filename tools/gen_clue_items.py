# Bank Organizer: builds src/data/clue_items.lua, the list of items the Bank
# Cleaner must never suggest because Treasure Trails need them.
#
# Where the names come from:
#   * stash: every item the RuneScape Wiki's "Hidey-holes" page lists as
#     required for an emote clue's hidey-hole (STASH). The page is fetched
#     from the wiki's public API.
#   * tools: a short curated list of clue tools.
#
# The downloaded page is treated as untrusted text: it is never executed or
# saved, and only names made of letters, digits, spaces and simple
# punctuation are kept. Names that start with a lower-case letter are links
# inside sentences (for example "steel nails" in building instructions), not
# required items, so they are skipped.
#
# If the wiki cannot be reached, the curated FALLBACK_STASH list is used
# instead so the plugin always has something sensible.
#
# Usage (from the plugin folder):
#   python -I tools/gen_clue_items.py

import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

# The plugin folder (this file lives in <plugin>/tools/).
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Where the generated Lua data file is written.
OUTPUT = ROOT / "src" / "data" / "clue_items.lua"

# The wiki API endpoint and the page that lists every hidey-hole's items.
API = "https://runescape.wiki/api.php"
PAGE = "Hidey-holes"

# A polite, identifiable User-Agent, as the wiki asks API users to send.
USER_AGENT = "bank-organizer-clue-list-generator (RS3 plugin by 6ing)"

# Only names made of these characters survive, 1 to 60 characters long.
SAFE_NAME = re.compile(r"[A-Za-z0-9 '()+.,-]{1,60}")

# Clue tools every Treasure Trails player keeps.
TOOLS = [
    "Spade",
    "Sextant",
    "Watch",
    "Chart",
    "Meerkats pouch",
    "Puzzle box",
    "Lockbox",
    "Strange device",
]

# Used only when the wiki cannot be reached: a small set of common
# hidey-hole items so the cleaner still keeps the most likely ones.
FALLBACK_STASH = [
    "Bronze dagger",
    "Iron full helm",
    "Gold ring",
    "Leather gloves",
    "Iron med helm",
    "Emerald ring",
    "Steel platebody",
    "Amulet of glory",
    "Blue dragonhide body",
    "Rune platebody",
]


def fetch_wikitext():
    """Download the Hidey-holes page source from the wiki.

    Returns the page's wikitext as a string, or None when the request
    fails for any reason (no network, the wiki is down, bad reply).
    """
    query = urllib.parse.urlencode({
        "action": "parse",
        "page": PAGE,
        "prop": "wikitext",
        "formatversion": "2",
        "format": "json",
    })
    request = urllib.request.Request(API + "?" + query, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as reply:
            data = json.loads(reply.read().decode("utf-8"))
    except Exception as error:
        print("Could not reach the wiki (" + type(error).__name__ + "); using the fallback list.")
        return None
    return data.get("parse", {}).get("wikitext")


def stash_names(wikitext):
    """Pick the required item names out of the page source.

    Items on the page are written as {{plink|Item name}}. Only names that
    pass SAFE_NAME and start with an upper-case letter are kept.
    Returns a sorted list without repeats.
    """
    found = set()
    for raw in re.findall(r"\{\{plink\|([^}|]+)", wikitext):
        name = raw.strip()
        if SAFE_NAME.fullmatch(name) and name[0].isupper():
            found.add(name)
    return sorted(found)


def lua_string(text):
    """Write text as a Lua string literal in double quotes.

    Backslashes and double quotes are escaped so any name stays valid Lua.
    """
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(stash, source):
    """Build the full contents of src/data/clue_items.lua.

    stash   the list of hidey-hole item names
    source  a short note on where the names came from, for the header
    Returns the file contents as a string.
    """
    lines = [
        "-- Bank Organizer: items Treasure Trails need (generated data).",
        "--",
        "-- Made by tools/gen_clue_items.py from " + source + ". Do not edit by hand;",
        "-- run the tool again to refresh it. Read by src/core/clues.lua.",
        "--",
        "--   stash  items required by emote clue hidey-holes (STASH units)",
        "--   tools  clue tools every Treasure Trails player keeps",
        "",
        "return {",
        "  stash = {",
    ]
    lines += ["    " + lua_string(name) + "," for name in stash]
    lines += ["  },", "  tools = {"]
    lines += ["    " + lua_string(name) + "," for name in TOOLS]
    lines += ["  },", "}", ""]
    return "\n".join(lines)


def main():
    """Fetch the names, fall back if needed, and write the data file.

    Returns 0 so the script can be used in a build.
    """
    wikitext = fetch_wikitext()
    stash = stash_names(wikitext) if wikitext else []
    source = "the RuneScape Wiki page \"" + PAGE + "\""
    if not stash:
        stash, source = sorted(FALLBACK_STASH), "the curated fallback list"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(stash, source), encoding="utf-8", newline="\n")
    print("Wrote " + str(len(stash)) + " hidey-hole items and " + str(len(TOOLS)) + " tools to " + str(OUTPUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
