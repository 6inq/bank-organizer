# Bank Organizer

An RS3 plugin for the official Plugin Hub. Created by **6ing**. Version **1.0.0**.

It colour-codes your bank by category and guides you through sorting it, one move at a time. It works on a single tab, or on your whole bank from the *All items* view.

Part of [6ing's RS3 plugins](https://github.com/6inq/rs3-plugins).

## How to use
1. Open your bank.
2. Enable the plugin.
3. Go through the settings (gear icon) and make sure everything is how you want it to be.
4. Click **Start Organizing**.

Want to change something? Click **Stop Organizing**, the Start button turns into this while it runs. Then edit your settings and start again. Settings are locked while organizing, so nothing changes under you mid-sort.

## Features
- **Scan**: reads the item id of every visible bank slot straight from the client and resolves each item's name, RS3 item category and right-click ops.
- **Categories**: Teleports, Combat, Potions, Food, Skilling, Materials, Currency, Misc. Items are classified automatically, and a manual right-click tag always wins.
- **Overlays**: tint per category, a filter that dims everything outside one category, and a highlight for untagged items.
- **Guided organizing**:
  - It shows "Insert X before Y" with green and yellow slot highlights.
  - The planner keeps the longest already-sorted run in place, so it always uses the **fewest possible moves**.
  - It rescans after every move you make.
- **Settings**: sort order (item ID or name), overlays, category filter, opacity, per-category colours, right-click tagging, and a reset for all tags.

## Fair play
The plugin never moves, withdraws or clicks anything for you. It only reads what your bank is already showing and draws highlights. It needs no permissions: no HTTP, no chat, no tracking.

## Layout
```
plugin.json, main.lua        entry point and manifest
src/core/                    pure logic: categories, classify, order (LIS planner), store
src/game/                    client-facing: bank scan, overlays, right-click tagging
src/ui/                      ribbon panel (steps + Start/Stop) and settings panel (PrettyUI)
src/app.lua                  scan -> classify -> plan -> render loop
tests/                       Lua tests run under embedded Lua 5.4
tools/                       build script + real-item fixture generator
docs/                        design spec + mod.io listing answers
```

## Tests
Install the test dependency:
```bash
python -m pip install lupa
```

Then run the suite:
```bash
python tests/run.py
```

The suite has 92 tests:
- the classifier, the planner, persistence, the bank scan and the overlays
- the full user flow through `main.lua`: steps shown, Start turns into Stop, settings lock and unlock, tagging is locked while organizing
- complete organizing sessions on banks of **10, 100, 500 and 1000 real RS3 items**. The ids and names come from the RuneScape Wiki GE table (`tests/fixtures/rs3_items.lua`).

## Building
The upload zip contains only `plugin.json`, `main.lua` and `src/`:
```bash
python tools/build.py
```
The output is `dist/bank-organizer-<version>.zip`.

## Notes
- Jagex had not published plugin docs at the time of writing. The API was reverse-engineered from the plugins already live on mod.io (see `RS3_API_NOTES.md` in the hub repo). Test in the live client before each release.
- Requires [PrettyUI](https://mod.io/g/runescape) (installed automatically as a dependency).
