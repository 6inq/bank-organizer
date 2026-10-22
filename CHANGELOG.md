# Changelog: Bank Organizer

## 1.4.2 (2026-10-22)
### New
- **Tags window by your mouse**: right-click a bank item and choose **Tags (Bank Organizer)**. The Tags window opens right next to your mouse, showing the item, with its category, **Ignore**, every tag and **Never label for decanting** (potions only). Every change applies at once, and the window stays open until you close it.
- **Custom categories** (Tools): make your own kinds of item with a name and colour. Add name rules ("Name contains", "Name starts with") and matching items join automatically. A review list shows every match in your bank, with **Remove** and **Restore**. Custom categories work everywhere built-in ones do: Tab Layout, My tabs pins, tab colours and Smart sort. Your own pick from the Tags window still wins over rules.
- **Custom tags** (Tools): make tags with a label of up to 6 characters, a colour, and a placement: top of infinity, bottom of infinity, first in its tab, or label only.
- **Any combination of tags**: an item can carry several tags. A priority list (Custom tags window) decides which tag places the item and which label shows. Saves from 1.4.1 load unchanged.
- **Herblore, recipe by recipe**: Smart sort puts empty vials and vials of water first, then each potion's grimy herb, clean herb, unfinished potion, secondary, vial doses from (1) to (4) and flask doses from (1) to (6). The whole overload family stays together.
- **Secondaries** setting: with their potion, or all at the bottom of the tab.
- **Bank Cleaner** (Tools, and offered when your bank is sorted): suggests quest leftovers (quests complete), items worth more alched, low value stacks (your limit, 1,000 gp to start) and items to review, each with a reason. Tag them Sell, Alch or Trash, or Keep them. It never suggests clue scroll items (emote clue STASH items, clue tools, caskets), rares, Vanity, Active or Favourite items, items for quests you have not finished, or coins. It never destroys, drops or sells anything.
- **Share codes** now carry custom categories (with rules), custom tags, the tag priority order and the Secondaries setting. Tags on single items, ignores and the Keep list stay yours. Older codes still load.

### Changed
- **New look**: the sidebar has a status card (moves left, sorted tabs), folding sections (Organize, Your tabs, Tools) and an item icon on every tab row. Settings are split into pages (General, Sorting, Tags & Labels, Colours, Cleaner) with a short explanation under every setting, in the settings gear and in a Settings window. The Tab Layout picks one tab at a time from a row of numbered buttons, shows that tab's planned items, and keeps the tab buttons at the bottom.
- Potions now sort from the fewest doses to the most.
- With decant labels off, part doses stay with their potion instead of sinking to the bottom.

### For developers
- Every file and function is commented in detail, as the Plugin Hub asks. `tools/check_comments.py` checks it, and the test runner fails when a comment is missing.
- New tests for custom categories and tags, herblore order, the Bank Cleaner, share codes, the Tags window and the new interface. 234 tests pass.

### Fixed
- The sidebar, settings and every window stay scrolled where they were after a click, instead of jumping back to the top.

## 1.4.1 (2026-10-21)
### New
- **Tags**: right-click any bank item and choose **Tags (Bank Organizer)**. One window holds everything for that item:
  - **Category**: what kind of item it is (this replaces the Assign Categories button).
  - **Placement**: **Active** (very top of the infinity tab), **Vanity** (top of infinity, with rares), **Favourite** (first in its own tab), **Sell**, **Alch**, **Disassemble** and **Trash** (bottom of infinity, in that order). One placement per item.
  - **Ignore**: never move this item.
  - Tagged items show a small label centred inside the slot (Active, Van, Fav, Sell, Alch, Dis, Trash, and Decant), in one small shadowed font. Each label's colour can be changed in settings under **Tag label colours**. The sidebar counts your tags, and settings has **Clear all tags**.
  - **Never label for decanting**: on any potion, for the part doses you keep to make other potions.
- **Vanity & Rares**: classic discontinued rares (partyhats, Halloween masks, Santa hats, Christmas crackers) are recognised automatically and kept at the top of the infinity tab, together with anything you tag Vanity, such as the original Blurite sword.
- **Decant labels**: part-dose potions you can decant get a **DECANT** label. Choose which doses to label (1 to 3 dose vials, 4 and 5 dose flasks) or turn labels off in settings. Part doses that cannot make a full vial or flask go to the bottom of the herb tab instead.
- **Rearrange your tabs with one drag**: in My tabs, **Move left / Move right** in Tab Layout now asks you to drag the tab button itself ("Drag the Tab 3 button onto Tab 2"), with an arrow between the two buttons, instead of moving every item across. Pins and tab colours follow their tab when tabs swap places, whether the guide asked or you rearranged them yourself.
- **Start Sorting / Stop Sorting**: a big button right under Analyze Bank, green to start and red to stop.
- **Sort direction**: **Horizontal (rows)** or **Vertical (columns)**. Vertical fills each tab down the columns, measured from your bank window; if you resize the bank, the plan follows. Share codes include the direction.

### Changed
- The right-click menu has a single Bank Organizer entry, **Tags**, instead of separate Ignore and Assign category entries.

## 1.4.0 (2026-10-20)
### New
- **Sort by quantity**: **Quantity (highest first)** puts the biggest stacks of each tab first, **Quantity (lowest first)** the smallest, with ties by name.
- **Value sort uses live Grand Exchange prices**: **Value (highest first)** now orders each tab by the item's current GE price, the middle of the latest instant buy and sell prices. Items the GE does not trade, or has no price for, keep using the game's own item value.
  - Prices load in the background, so the sidebar and the guide never wait for them. Until they arrive, Value sorts by item value, and once they do the blueprint is rebuilt once by GE price.
  - The sort choice says which is in use: **Value: GE price**, **Value: item value until GE prices load**, or **Value: item value** when GE prices are unavailable or price fetching is turned off.
  - Prices come from the **GE Price Library**, now installed automatically as a dependency. It downloads them from the RuneScape Wiki prices API; Bank Organizer itself still has no internet access.
- **Sorted tabs light up**: once a tab holds exactly the right items in the right order, its items turn green, so you can see your progress. Settings has **Tabs that are sorted**: Green (default), No overlay, or Keep tab colour, plus a colour picker for the green.
- **Infinity first, then your tabs, from the top down**: the guide first empties the infinity tab, starting with the topmost item, each dropped onto its tab's button (or + for a new tab). Once infinity is done, it goes on to sort every tab, in order, without you switching views. Viewing a single tab sorts that tab, and when it is done the guide names the next tab to open. The moves-left count follows that exact order.

### Fixed
- In My tabs, the guide could stop after the infinity tab, or check the wrong tab when your tabs are stored in a different order than shown. It now tells which tab you are viewing from the items on screen.
- Items that do not stack and share one name, such as filled Ushabti, confused the guide. Each slot is now told apart, matched tab by tab as you see them, so the guide never asks you to move a copy that is already in its tab. Ignoring one still ignores them all.
- Right after a move, the old arrow flashed for a moment from the item's new spot. The arrow and MOVE marks now wait until the bank has settled, then show the next step.
- The guide arrow started below the bank when the bank was scrolled down. It now reads the scroll from the bank's scrolling viewport, so it starts at the item you are moving, and points at the top or bottom edge when that item is out of view.
- Daggers, longswords, battleaxes, spears and other melee weapons count as melee when the game gives them no weapon category.

## 1.3.0 (2026-10-20)
### New
- **Sort inside tabs**:
  - **Smart** groups gear by combat style (melee, ranged, magic, necromancy), then slot (weapon, off-hand, head, body, legs, hands, feet, cape, neck, ring, ammo, pocket), most valuable first. Herblore is grouped by recipe chain: everything that goes into overloads sits together (irit, super attack, avantoe, extreme attack, and so on up to the overload), then the prayer and restore chain, brews, antifires and more, each herb next to its unfinished potion and the potion it makes. Outfits stay together as sets, runes follow the game's order, potions keep their doses together, and resources sort by material and tier.
  - Every other kind has its own smart order too: food by healing tier with full portions first, teleports as tablets then jewellery (most charges first) then gear, tools by skill, containers, summoning (shards, charms, pouches, scrolls, contracts), MTX & XP boosts, seeds, compost, ammo components by tier, clues by tier, and boss loot by value.
  - **Smart is the default** for everyone, including existing setups.
  - **Value (highest first)** orders each tab by item value, whatever the kind. This uses the game's own item value; live GE prices are planned.
  - Also **Name**, **Item ID**, or **Keep my order**, which only moves items between tabs and leaves each tab's order alone.
- **Share or load a setup**:
  - **Share my setup** turns your whole setup (tabs and their names, the kinds of item in each, pins, how you organize and how you sort) into one line of text to post anywhere.
  - **Load a setup** applies a code someone else shared.
  - Codes are read, never run, and anything unknown in them is ignored.
- **Move checking**:
  - The guide checks every move you make.
  - If you swap instead of insert, drop on the wrong spot, or move a different item, it says **Not quite** and walks you back one move at a time, then shows the original move again.
  - **Continue from here** accepts the new layout instead.
  - Deposits and withdrawals are never treated as mistakes.
  - Moves are judged from the bank's full item order, which the game updates straight away, rather than its tab sizes, which can lag behind. A correct drag onto a tab is never mistaken for a wrong one, and the plugin uses the tab sizes the move produced until the game catches up.
- **Ignore items**:
  - Right-click any bank item and choose **Ignore (Bank Organizer)** to leave it out of organizing. It is never moved, everything else sorts around it, and it gets a thin grey outline instead of a tint.
  - **Stop ignoring** on the same menu brings it back.
  - Settings has **Stop ignoring all items**.
- **Starting from no tabs**: in My tabs with nothing but the infinity tab, the guide follows your Tab Layout and shows which item to drop on the **+** button to start each new tab.
- **Sidebar** reorganised into setup, actions, status and your tabs, with the sort choice up front.

### Improved
- **Guide arrow**:
  - Has a dark outline so it stands out on any background, and an arrowhead.
  - Starts at the item's edge instead of covering its icon.
  - Ends on a bar in the gap where the item should be inserted, or on an outline around the target item or tab button.
  - Follows the bank as you scroll. If the item to move is scrolled out of view, a short arrow at the top or bottom edge shows which way to scroll.
  - Drawn above the bank so the tab row is never clipped.
- **Tab buttons**: found by walking the bank window the documented way, so the arrow reaches the right tab and the + button.
- Ground mud and miasma runes count as herblore secondaries, not runes.
- **Colour settings** are named by kind of item (Combat Gear, Herblore) instead of tab number.

### Fixed
- **Tabs shown in a different order than the game stores them** (for example after rearranging tabs): the plugin now learns the on-screen order from the infinity view, so tab numbers, arrows, the tab you are viewing and move checks all match what you see. This fixes correct drops onto a tab being called a mistake.

## 1.2.0 (2026-10-20)
Rebuilt around the Bank Architect workflow: **Analyze Bank, Open Blueprint, Sorting Guide**.

### New
- **Two ways to organize**:
  - **My tabs** keeps the tabs you already have. Tab 1 (infinity) is the misc catch-all, and loose items go to the tab that already holds most of their kind.
  - **Whole bank** follows your Tab Layout.
- **Tab Layout (Whole bank)**: add, delete, rename and reorder tabs, and choose which kinds of item each one holds and in what order. **Copy my current tabs** builds a layout from your bank.
- **Tab Layout (My tabs)**: pin any kind of item to a tab, Remove it back to infinity, or swap whole tabs with Move left / Move right.
- **Guide line**: a white line from the item to MOVE to where it goes, either the item to drop it next to or the tab button to drop it on. It stays put while you drag.
- **Blueprint window**: shows the plan one tab at a time, with a tab picker and Previous / Next.
- **Assign Categories**: right-click any bank item to set its kind; your choice always wins.
- **New kinds**: Summoning (pouches, scrolls, binding contracts, spirit gems), MTX & XP Boosts (knowledge bombs, wildcards, protean items, portable packs, Treasure Hunter rewards), and skillcapes as Skilling Outfits.
- Tabs are numbered the way RS3 numbers them (infinity is Tab 1).

### Improved
- **Classification** now uses the game's own item categories first. On a real 1,304-item bank, items left in Storage & Cleanup dropped from 452 to 197. Fixes include:
  - urns, Invention and Archaeology gear
  - Treasure Hunter skilling outfits
  - farming produce
  - boss drops and pet unlocks
- The guide plans one safe move at a time, re-plans from your real bank after every move, and follows your bank's insert or swap setting.
- Guide labels on the top row of slots no longer hide under the tab bar.

### Fixed
- The client could crash when the plugin was turned on or off.
- Herbs no longer match inside other words ("spirit" was read as the herb "irit").
- Dropdowns failed to open in the live client.

## 1.1.0 (2026-10-17)
- Every colour is configurable: each category, the MOVE highlight, the drop target, the filter dim and the untagged outline.

## 1.0.0 (2026-10-17)
- First release: category overlays, automatic classification, right-click tagging, and a guided fewest-moves sort.
