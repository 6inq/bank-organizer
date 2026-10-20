# Bank Organizer

An RS3 plugin for the official Plugin Hub. Created by **6ing**. Version **1.3.0**.

It works out where everything in your bank belongs, tints each item with the colour of its tab, and guides you through sorting it, one drag at a time. It is built on the workflow of the RuneLite plugin Bank Architect: **Analyze, Blueprint, Sorting Guide**.

Part of [6ing's RS3 plugins](https://github.com/6inq/rs3-plugins).

## How to use
1. Open your bank and enable the plugin.
2. In the sidebar, choose how to **Organize**:
   - **My tabs**: keeps the tabs you already have. Tab 1 (infinity) is the misc catch-all. Loose items go to the tab that already holds most of their kind.
   - **Whole bank**: follows your **Tab Layout**, which is a list of tabs in bank order, each with the kinds of item it holds.
3. Press **Analyze Bank**. Every item is tinted with the colour of the tab it belongs in.
4. Press **Open Blueprint** to review the plan, one tab at a time.
5. Press **Sorting Guide** and follow it:
   - The item to drag says **MOVE**.
   - An arrow runs to exactly where it goes: a bar in the gap where it should be inserted, or an outline around the tab button (the + button for a new tab).
   - In My tabs mode it sorts the tab you are looking at.

## Features
- **Classification**: about 30 kinds of item (Runes, Summoning, MTX & XP Boosts, Skilling Outfits, Potions, Herbs and more). It uses the client's own item category first, then right-click options and name families. Anything it cannot place goes to Storage & Cleanup for review.
- **Sort inside tabs**: Smart (gear by combat style, then slot, best first; outfits by set; runes and herbs in game order; potions by family and dose; resources by material and tier), Name, Item ID, or Keep my order (only move items between tabs).
- **No tabs yet**: the guide starts each new tab by showing which item to drop on the + button.
- **Corrections**: press **Assign Categories**, right-click any bank item and pick its kind. Your choice always wins.
- **Tab Layout (Whole bank)**: add, delete, rename and reorder tabs, and choose the kinds of item each one holds and their order. **Copy my current tabs** builds a layout from the bank you already have.
- **Tab Layout (My tabs)**:
  - Pin a kind of item to any tab, or Remove it back to infinity.
  - Move left / Move right swaps whole tabs; the guide then walks you through moving the items.
- **Sorting Guide**:
  - Plans one safe manual move at a time.
  - Re-plans from your real bank after every move, and uses the fewest moves in insert mode.
  - Supports insert and swap mode (it follows your bank's own setting).
- **Every colour is yours**: each tab colour, the MOVE highlight, the drop target and the guide line, with a reset.

## Fair play
The plugin never moves, withdraws or clicks anything for you. It only reads what your bank is already showing and draws on top of it. It needs no permissions: no HTTP, no chat, no tracking.

## Layout
```
plugin.json, main.lua        entry point and manifest
src/core/                    pure logic: tags, classifier, layout, blueprint, guide planner, store
src/game/                    client-facing: bank reader, overlay (tints, marks, guide line), right-click
src/ui/                      sidebar panel, settings, Blueprint / Tab Layout / picker windows (PrettyUI)
src/app.lua                  analyze -> blueprint -> guide loop
tests/                       Lua tests run under embedded Lua 5.4
tools/                       build script + real-item fixture generator
docs/                        mod.io listing answers
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

The suite has 90 tests, covering:
- tags, layouts (including custom tab orders and old saves), the classifier (with cases from a real bank) and the blueprint
- sorting (styles, slots, families, keep my order) and the guide line's geometry
- the guide planner, including complete sorting sessions on banks of 10, 100, 500 and 1000 real RS3 items
- the full user flow through `main.lua` against a stubbed client: panel, windows, dropdowns, corrections, the guide line, My tabs pins and tab reordering, persistence and shutdown

## Building
The upload zip contains only `plugin.json`, `main.lua` and `src/`:
```bash
python tools/build.py
```
The output is `dist/bank-organizer-<version>.zip`.

## Notes
- Requires [PrettyUI](https://mod.io/g/runescape) (installed automatically as a dependency).
- See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.
