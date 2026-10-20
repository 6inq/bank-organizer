# Changelog: Bank Organizer

## 1.3.0 (2026-10-20)
### New
- **Sort inside tabs**:
  - **Smart** groups gear by combat style (melee, ranged, magic, necromancy), then slot (weapon, off-hand, head, body, legs, hands, feet, cape, neck, ring, ammo, pocket), most valuable first. Herblore is grouped by recipe chain: everything that goes into overloads sits together (irit, super attack, avantoe, extreme attack, and so on up to the overload), then the prayer and restore chain, brews, antifires and more, each herb next to its unfinished potion and the potion it makes. Outfits stay together as sets, runes follow the game's order, potions keep their doses together, and resources sort by material and tier.
  - Every other kind has its own smart order too: food by healing tier with full portions first, teleports as tablets then jewellery (most charges first) then gear, tools by skill, containers, summoning (shards, charms, pouches, scrolls, contracts), MTX & XP boosts, seeds, compost, ammo components by tier, clues by tier, and boss loot by value.
  - **Smart is the default** for everyone, including existing setups.
  - Also **Name**, **Item ID**, or **Keep my order**, which only moves items between tabs and leaves each tab's order alone.
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
