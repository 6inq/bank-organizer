# Bank Organizer (RS3 plugin) - Design Spec

Author credit: **6ing**. Plugin name: **Bank Organizer**. Target: RS3 official Lua plugin API (Plugin Hub on mod.io, game id 13295).
Dependency: **PrettyUI** (mod.io id `6398181`), exposed to plugins as the global `prettyui`.

## 1. What it does

1. **Scan**: reads every bank slot currently visible in the native bank grid (item id, name, RS3 item category, right-click ops, slot position).
   - Scope = what the bank is showing. Viewing a single tab organizes that tab; viewing *All items* organizes the whole bank. No separate scope setting is needed.
2. **Categorize**: each item gets one category: manual tag (right-click menu) > automatic heuristic > `misc`.
3. **Overlay**: tints each bank slot with its category colour. Filter to one category (others dimmed); "highlight untagged" mode outlines items that only have an automatic guess.
4. **Order**: computes the target order (category order, then item id or name) and guides the player **one move at a time** ("Insert *X* before *Y*"), highlighting the item to move and the drop target. The plugin never moves items itself (Jagex rule: no automation). After each player move the bank is rescanned and the next step recomputed.

Not in v1 (YAGNI): profiles, import/export, High Alch category (needs price data), HTTP of any kind.

## 2. Jagex guideline compliance

- No automated actions: the plugin only draws overlays and text. The player performs every drag.
- Only API-exposed, player-visible information (bank contents the player is looking at).
- No HTTP, so no permissions are needed.

## 3. File layout

```
plugin.json
main.lua                    -- wiring + PluginShutdown()
src/core/categories.lua     -- PURE: ordered category list {key,label,colour}
src/core/classify.lua       -- PURE: classify(info) -> category key
src/core/order.lua          -- PURE: buildTarget, nextMove (LIS planner)
src/core/store.lua          -- PersistentDB wrapper (tags + settings), injectable db
src/game/bank.lua           -- reads live bank slots from the client
src/game/overlay.lua        -- draws/clears ui.Rectangle overlays on bank slots
src/game/tagging.lua        -- right-click "Bank Organizer >" submenu on bank items
src/ui/panel.lua            -- ribbon content panel (ContentLayerReady)
src/ui/settings.lua         -- settings panel (SettingsLayerReady)
src/app.lua                 -- state + event subscriptions + tick loop
tests/run.py                -- runs Lua tests through `lupa` (embedded Lua)
tests/*_test.lua            -- requirement-driven tests for the pure modules + bank/overlay with fakes
```

## 4. plugin.json

```json
{
  "name": "Bank Organizer",
  "version": "1.0.0",
  "author": "6ing",
  "contactEmailAddress": "im6ing@gmail.com",
  "hasRibbonIcon": true,
  "hasSettingsIcon": true,
  "requiredDependencies": { "prettyui": 6398181 },
  "optionalDependencies": {},
  "requiredPermissions": [],
  "optionalPermissions": []
}
```

## 5. Module contracts

### categories.lua
Ordered list (this order is also the default bank order):
`teleports, combat, potions, food, skilling, materials, currency, misc`.
Each entry: `{ key, label, colour }` where colour is a packed `0xRRGGBBAA` integer (the same format as `ui.Rectangle.rgba` and PrettyUI ColourPicker). Exports `list`, `byKey[key]`, `rank(key)`, `isValid(key)`.

### classify.lua: `classify(info) -> key`
`info = { id=int, name=string, category=string|nil (id.Category name), ops={ [lowercase op]=true } }`. The rules run top to bottom and the first match wins (names are lowercased):
1. currency: name is `coins`, or contains `token`, `ticket`, `coins` (but not `coin pouch`)
2. teleports: ops `teleport`/`rub`/`break`, or name contains `teleport`/`tablet`/`lodestone`
3. potions: op `drink`, or name matches `%(%d%)$`, or contains `potion`/`flask`/`brew`
4. food: op `eat`
5. combat: ops `wear`/`wield`/`equip`, or category starts with `WEAPON_`/`ARMOUR_`/`AMMO_`, or name ends with ` rune` / `runes`
6. skilling (tools): name contains one of `pickaxe, hatchet, hammer, chisel, knife, tinderbox, needle, fishing rod, harpoon, lobster pot, secateurs, rake, spade, trowel, saw, mould`
7. materials: name contains/starts with `ore, bar, logs, plank, grimy, clean, herb, seed, hide, leather, uncut, essence, bones, ashes, raw , scale, thread, flax, cloth, gem`
8. otherwise `misc`

It must never error on missing fields (nil name, nil ops, nil category).

### order.lua
- `buildTarget(items, sortMode) -> array of objectIDs`. `items = {{objectID, name, category}}`. Stable sort by `categories.rank(category)`, then by `objectID` (`sortMode="id"`, the default) or lowercase `name` (`"name"`, ties broken by id).
- `nextMove(currentIDs, targetIDs, skipped) -> move|nil`
  - `currentIDs`: object ids in the bank's visual order (row-major). `skipped`: set of ids to ignore, which are removed from both lists first.
  - It returns nil when the bank is already in order.
  - Algorithm (minimal moves = n - LIS): rank each current id by its target index; compute a longest increasing subsequence of the ranks (O(n log n), deterministic); let X be the **lowest-rank id not in the LIS**; let Y be the LIS id with the smallest rank greater than rank(X).
  - Return `{ move=X, before=Y, remaining=n-|LIS| }`. When no such Y exists, return `{ move=X, after=<last current id other than X>, remaining=... }`.
  - Each applied move grows the LIS by one, so repeated application converges in exactly `remaining` moves.
  - Ids that appear in only one list are ignored.

### store.lua
`Store.new(db)` where `db` defaults to the global `PersistentDB`. Structured data is keyed by **string** keys.
- Tags: key `bank-organizer:tags`, value `{ [tostring(objectID)] = categoryKey }`. API: `getTag(id)`, `setTag(id, key)`, `clearTag(id)`, `clearAllTags()`.
- Settings: key `bank-organizer:settings`, value `{ sortMode, overlays(bool), filter(categoryKey|"all"), highlightUntagged(bool), opacity(0..1), colours={[key]=int} }`. API: `get(name)`, `set(name, value)`, `colour(key)`.
- Values are validated on load: an invalid tag or category key is dropped, and an invalid setting falls back to its default.
- Each mutation persists immediately via `SetStructuredData`.

### bank.lua
- `Bank.slotsContainer()`: `ui.Interfaces:GetComponent(id.Component["BANK__BANK_INV"])` if `id.Component.BANK__BANK_INV` is valid (>= 0) and the result has `visibleGlobal` and positive width and height; otherwise nil.
- `Bank.scan() -> slots|nil, reason`:
  - Iterate `container:IterateDynamicComponents(fn)`, where `fn` returns `false` to continue.
  - Keep components with `type == ui.ComponentType.SPRITE`, `associatedObjectID >= 0`, `visible`, and `not hidden`.
  - Each record is `{ objectID, component, x, y, width, height, quantity=associatedObjectQuantity }`, sorted by `y` then `x`.
- `Bank.info(objectID)` (cached per id):
  - `config.Obj.FromID(id)` gives `name` and `category` (resolve with `id.Category.FromID(obj.category)`, which may return nil).
  - `obj.interfaceOpNames` (iterate with `pairs`, lowercase) gives `ops`.
  - Wrap the whole lookup in `pcall`.
- `Bank.searchActive()`: `var.VarClient.BANK_SEARCHMODE_CLIENT` value is truthy and non-zero. Ordering is refused while a search is active ("Clear bank search to order items").
- `Bank.viewSignature()`: a string built from `var.VarPlayer.BANK_CURRENT_TAB`, `var.VarPlayer.BANK_FILTER`, `var.VarClient.BANK_SEARCHMODE_CLIENT` and `var.VarClient.BANK_LASTSEARCHSTRING` values (as in the Quest Helper reference).

### overlay.lua
- Draws children of the slots container with `ui.Rectangle.new(container)`, using `:SetPos(x, y)`, `:SetSize(w, h)`, `.fill`, `.rgba`, `.outlineThickness` and `.clickthrough = true`. They must never eat clicks.
- `Overlay:render(slots, state)` rebuilds only when a signature changes. The signature covers the slot ids and positions, mode, filter, opacity, colours, the current move, and the current target.
  - Category tint: a filled rect whose alpha is `opacity * 255`. With a filter set, non-matching slots get a dark dim (`0x000000AA`) and matching slots get a tint.
  - Highlight untagged: an outline (thickness 2, the category colour fully opaque) on slots without a manual tag.
  - Ordering: the move slot gets a green outline (thickness 3, `0x3CE03CFF`) plus a `ui.Text` label `MOVE`. The target slot gets a yellow outline (`0xF2C94CFF`) plus a label `INSERT BEFORE`, or `AFTER` for an after-move. Labels use font `id.Font.MUSEO_SANS_15PT_REGULAR` and `clickthrough = true`.
- `Overlay:clear()` destroys every created component (`:Destroy()`).
- Overlays are cleared when the bank closes or the container identity changes.

### tagging.lua
- Subscribe to `Event.MiniMenuReady` with the id `bank-organizer:menu`. If tagging is enabled, find the first entry in `event.miniMenu.entries` where `entry.componentData.component` exists, `.interfaceID == id.Interface.BANK` and `.associatedObjectID >= 0`. Wrap the field access in `pcall`.
- Add `prettyui.MiniMenu.AddSubmenu(menu, "Bank Organizer", children)`. `children` contains `{label="Set: <Category label>", action=fn}` for each category, plus `{label="Clear tag", action=fn}` when the item has a tag. Each action calls `store:setTag` or `store:clearTag`, then `app:invalidate()`.
- Add the submenu at most once per menu.

### app.lua
- State: `ordering` (bool), `skipped` (set), `move` (last nextMove result), `status` (string).
- `Event.Logic` (id `bank-organizer:logic`): every 3 ticks while the bank is open, or every 25 ticks while it is closed, scan, classify, render the overlay, and (if ordering) recompute `nextMove`. The work is cheap: up to about 1000 slots.
- `Event.InventoryUpdated` (`event.inv.id == config.Inv.BANK.id`) calls `invalidate()`, which forces a recompute on the next tick.
- When ordering finishes (`nextMove` returns nil), set the status to "Tab organized!", stop ordering, and clear the move highlights.
- Status strings for the panel:
  - "Open your bank."
  - "Clear bank search to order items."
  - "Insert <X name> before <Y name>"
  - "Move <X name> to the end (after <Z name>)"
  - "<n> moves remaining"
- When the bank view is *All items* (`BANK_CURRENT_TAB == 1`) while ordering, show a hint: "Ordering All items can move items between tabs; open a single tab to keep tabs intact."
- `PluginShutdown()` unsubscribes every event, destroys the overlays and panels, and must be safe to call twice.

### panel.lua (ribbon content, `Event.ContentLayerReady`, id `bank-organizer:content`)
- Shows the title, the "by 6ing" credit, and the four user steps:
  1. Open your bank.
  2. Enable the plugin.
  3. Go through the settings.
  4. Click Start Organizing.
- One `AddFancyButton` toggles between **Start Organizing** and **Stop Organizing** (via `:SetText`).
- "Skip item" is disabled unless organizing.
- Live status and hint texts are updated through `app:onChange`.

### settings.lua (`Event.SettingsLayerReady`, id `bank-organizer:settings`)
- **Every option lives here:**
  - sort mode (Item ID / Name)
  - show category colours, highlight untagged, category filter, overlay opacity
  - right-click tagging, per-category colour pickers
  - "Reset all tags" (Confirm dialog)
- **While organizing:** every control is `SetDisabled(true)` and a lock message is shown ("Click Stop Organizing to make changes"). Right-click tagging is also suppressed. Finishing or stopping unlocks automatically.

## 6. Tests (pure Lua, run under `lupa`)
`tests/run.py`:
- `pip install lupa`.
- Set `package.path` to `<root>/?.lua;<root>/tests/?.lua`.
- Run every `tests/*_test.lua`, with each test file returning a table of `name -> function`.
- Report pass/fail and exit non-zero on failure.

Required scenarios:
- **classify**:
  - each category's happy path (e.g. Coins, Varrock teleport, Super restore (4), Shark, Abyssal whip, Rune pickaxe, Yew logs, Air rune, "Ancient lamp" goes to misc)
  - precedence (a teleport tablet with op `break`; a wearable teleport ring classified as teleports; "Rune platebody" with op wear classified as combat, not as a rune)
  - nil and empty info does not error and returns misc
- **order.buildTarget**: category order respected; id sort; name sort with tie-break; unknown category goes to misc; empty input
- **order.nextMove**:
  - already sorted gives nil; empty gives nil; a single item gives nil
  - one item out of place gives the correct X and Y
  - an item belonging at the end returns `after`
  - reverse order converges in exactly n-1 moves via a simulated apply-loop
  - a random permutation property test (200 seeds, n up to 60) where the simulated apply-loop reaches target order in exactly the first `remaining` moves
  - skipped ids are ignored; ids present in only one list are ignored
- **store** (with a fake db table):
  - defaults
  - set/get/clear tag persists (a reload from the same fake db sees it)
  - invalid stored data is sanitized
  - clearAllTags
- **bank.scan** (with fake `ui`/`id` globals): filters non-sprite, hidden, and objectID<0 components; sorts row-major; returns nil plus a reason when the container is missing or invisible
- **overlay** (fake `ui.Rectangle`/`ui.Text` recording creates and destroys): render creates rects; the same signature does not rebuild; clear destroys all; move/target highlight present

## 7. Reverse-engineered API reference
See `RS3_API_NOTES.md` in the rs3-plugins hub repo. The notes were built by reading the six plugins already live on mod.io (Quest Helper, Menu Entry Swapper, Job Gauges, Entity Hider, Tilemarkers, PrettyUI).
