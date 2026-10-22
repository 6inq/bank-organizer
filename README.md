# Bank Organizer

An RS3 plugin for the official Plugin Hub. Created by **6ing**. Version **1.4.2**.

Bank Organizer works out where everything in your bank belongs. It colours each item with the colour of its tab, then guides you through sorting it, one drag at a time. You make every move yourself.

Part of [6ing's RS3 plugins](https://github.com/6inq/rs3-plugins).

## What it does

- **Plans your bank.** Every item gets a kind (Runes, Potions, Combat Gear and about 30 more) and a tab to live in.
- **Shows the plan on your bank.** Each item is tinted with the colour of the tab it belongs in.
- **Guides you, one move at a time.** The item to drag says **MOVE**, and an arrow points to exactly where it goes.
- **Checks every move.** If you drop something in the wrong place, it tells you and helps you put it back.
- **Never touches your bank.** It only reads what your bank shows and draws on top of it.

## Your first sort, step by step

1. Install Bank Organizer from the Plugin Hub. PrettyUI and the GE Price Library install with it.
2. Open your bank.
3. Open the Bank Organizer sidebar.
4. Under **Organize**, choose how you want to sort:
   - **My tabs** keeps the tabs you already have. Tab 1 (the infinity tab) becomes the place for everything else. Loose items go to the tab that already holds most of their kind.
   - **Whole bank** follows a **Tab Layout**: a list of tabs, each holding the kinds of item you choose. A sensible layout is ready from the start.
5. Press **Analyze Bank**. Your items are tinted with the colour of the tab they belong in.
6. Press **Open Blueprint** if you want to see the plan, one tab at a time.
7. Press **Start Sorting** (green). Then follow the guide:
   - The item to drag says **MOVE**.
   - The arrow ends where it goes: a bar in the gap to drop it into, or an outline around a tab button.
   - The sidebar says what to do in words, and how many moves are left.
8. When everything is in place, the sidebar says **Your bank matches the blueprint**. Press **Stop Sorting** (red) at any time to pause.

Tip: in My tabs, the guide sorts the tab you are looking at. Open the infinity view to sort everything.

## The sidebar

- **Status:** the next step, moves left and how many tabs are sorted.
- **Analyze Bank** and **Start Sorting / Stop Sorting.**
- **Open Blueprint** and **Tab Layout.**
- **Organize:** how you organize and sort. Each choice has a short explanation under it.
- **Your tabs:** one row per tab: its first item, its name in its colour, what it holds and how many items.
- **Tools:** Share or Load a Setup, Bank Cleaner, Custom tags, Custom categories and Settings.

Every section has a **[-]** button to fold it away, and **[+]** to open it again.

## Right-click any bank item: Tags

Right-click an item in your bank and choose **Tags (Bank Organizer)**. You get a menu with:

- **Category...** to say what kind of item it is. Your choice always wins over automatic sorting.
- **Ignore** to leave the item exactly where it is. Everything else sorts around it.
- **Tags** to tick (each one shows [x] when it is on):
  - **Active**: top of the infinity tab
  - **Vanity**: top of the infinity tab, with rares like partyhats, which go there automatically
  - **Favourite**: first in its own tab
  - **Sell**, **Alch**, **Disassemble**, **Trash**: bottom of the infinity tab
  - any tags you made yourself
- **Never label for decanting** (on potions only).
- **More...** opens the full Tags window.

An item can have several tags at once. The tag highest in the priority list (Tools, Custom tags) decides where the item goes and which label shows in its slot.

## Custom categories

Make your own kinds of item in **Tools, Custom categories**.

1. Type a name and press Enter.
2. Add **name rules**, like "Name contains: dragon" or "Name starts with: Super". Matching items join the category automatically. Upper and lower case do not matter.
3. Check the **review list**. It shows every item in your bank the rules matched. Press **Remove** to keep one out, and **Restore** to let it back in.
4. Rename it or change its colour at any time.

New categories start in Tab 1 (infinity). Move them to any tab in **Tab Layout**, or pin them in My tabs. Delete a category and its items go back to automatic sorting.

Order of choices: your own pick from the Tags window wins, then your name rules, then automatic sorting.

## Custom tags

Make your own tags in **Tools, Custom tags**:

- A label of up to 6 characters, shown in the item's slot.
- A colour for the label.
- Where it puts items: top of the infinity tab, bottom of the infinity tab, first in its own tab, or label only (never moves the item).

The same window holds the **priority list** for every tag. Use **Up** and **Down** to choose which tag wins when an item has several.

## Herblore, recipe by recipe

With Smart sort, your herblore items line up like this:

1. Empty vials and flasks, then vials of water, then other vials (bomb, juju and so on).
2. Each potion's recipe in turn: grimy herb, clean herb, unfinished potion, secondary, then the potion from (1) to (4) doses, then flasks from (1) to (6).

The whole overload family stays together. A herb used by several potions sits with the first one.

In **Settings, Sorting** you can move all **Secondaries** to the bottom of the tab instead.

### Decant labels

Part-dose potions you can combine into full ones get a **Decant** label. You choose which doses count. With labels on, part doses that cannot make a full potion wait at the bottom of the herb tab. With labels off, they stay with their potion. To keep some part doses for other potions, tick **Never label for decanting** on them.

## Bank Cleaner

Open it from **Tools**, or from the button that appears when your bank is sorted. It suggests items you might not need, grouped with a reason:

- **Quest leftovers:** untradeable quest items whose quests are all complete. Many can be reclaimed from an NPC if you need them again.
- **Worth more alched:** High Alchemy pays more than the Grand Exchange.
- **Low value:** the whole stack is worth less than your limit (1,000 gp to start; change it in Settings, Cleaner).
- **Review:** items Bank Organizer could not place.

Tick items, then press **Tag as Sell**, **Tag as Alch** or **Tag as Trash** to line them up at the bottom of your infinity tab. Or press **Keep** so they are never suggested again.

The Bank Cleaner never suggests:

- clue scroll items (emote clue STASH items, clue tools, caskets and puzzles)
- rares, and Vanity, Active or Favourite items
- items for quests you have not finished
- coins and tokens
- items you ignored or kept

It never destroys, drops or sells anything for you.

## Tab Layout

- **Whole bank:** pick a tab from the numbered buttons along the top. Then:
  - name it
  - add kinds of item with the dropdown, and order them with **Up** and **Down**
  - **Remove** a kind to send it back to Storage & Cleanup

  The buttons at the bottom add, delete and move tabs. **Copy my current tabs** builds a layout from the bank you already have. **Reset to default** starts over.
- **My tabs:** pick a tab, then:
  - pin a kind of item to it, and **Unpin** or **Remove** pins
  - use **Move left** and **Move right** to rearrange whole tabs. The guide then shows you the one tab drag to make.

## Settings

Open **Tools, Settings**, or the plugin's settings gear. The settings are split into pages:

- **General:** tinting, how sorted tabs look, rearrange mode and resets.
- **Sorting:** sort order, direction (rows or columns), Secondaries and decant labels.
- **Tags & Labels:** clear all tags, and the colour of every label.
- **Colours:** the colour of every kind of item and of the guide.
- **Cleaner:** the low value limit and the Keep list.

Sort orders you can pick:

- **Smart** (the default): every kind has its own sensible order. Gear goes by combat style, then slot, best first. Outfits stay together. Runes follow the game's order.
- **Name** or **Item ID**.
- **Value:** most valuable first, using live GE prices.
- **Quantity:** biggest or smallest stacks first.
- **Keep my order:** only move items between tabs.

## Share or Load a Setup

**Tools, Share or Load a Setup** turns your setup into one line of text. The code holds:

- your tabs and their names
- your custom categories and tags
- how you organize and sort

Post it anywhere. Paste someone else's code and press Enter to use their setup.

Tags on single items, ignored items and your Keep list are never in a code; they stay yours.

## Fair play

Bank Organizer never moves, withdraws or clicks anything for you. It only reads what your bank is showing and draws on top of it. It needs no permissions: no internet access, no chat access and no tracking. Live GE prices come from the GE Price Library plugin.

## Requires

[PrettyUI](https://mod.io/g/runescape) and the GE Price Library (gepl). Both install automatically as dependencies. The right-click Tags menu uses PrettyUI 1.2.0 or newer; with an older PrettyUI it opens the Tags window instead.

## For developers

```
plugin.json, main.lua   manifest and entry point
src/core/               pure logic: kinds, classifier, layouts, blueprint, guide planner, tags, store, share codes, cleaner
src/game/               client-facing: bank reader, overlay, guide arrow, right-click menu, prices, quests
src/ui/                 sidebar, settings and windows (PrettyUI)
src/data/               generated data (clue items)
src/app.lua             analyze, blueprint and guide loop
tests/                  Lua tests under embedded Lua 5.4
tools/                  build, comment check and data generators
```

Every file and function is commented. `tools/check_comments.py` enforces that, and the test runner fails when a comment is missing.

Install the test dependency:

```bash
python -m pip install lupa
```

Run the tests (this also runs the comment check):

```bash
python tests/run.py
```

Build the upload zip (`dist/bank-organizer-<version>.zip`, holding only `plugin.json`, `main.lua` and `src/`):

```bash
python tools/build.py
```

Refresh the clue item list from the RuneScape Wiki:

```bash
python -I tools/gen_clue_items.py
```

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.
