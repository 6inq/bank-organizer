# mod.io listing answers: Bank Organizer

Copy each field into the mod.io "Create Plugin" form. You're making the listing image yourself (16:9, min 512x288, max 8MB).

---

## Basics

**Plugin name**
```
Bank Organizer
```

**Summary** (250 character max; this is 244)
```
Works out where everything in your bank belongs, tints each item with its tab's colour, and guides you through sorting it one drag at a time, with a line to where it goes. Keep your own tabs or design a new layout. You make every move. By 6ing.
```

**Homepage**
```
https://github.com/6inq/bank-organizer
```

**Profile URL**
```
https://mod.io/g/runescape/m/bank-organizer
```

**Community**
- Allow comments: **checked**
- Allow dependants: **unchecked** (this is a standalone plugin, not a library for other plugins)

---

## Description

The editor accepts HTML. Click the `<>` (source code) button in the toolbar and paste this:

```html
<p>Bank Organizer works out where everything in your bank belongs, tints each item with the colour of its tab, and guides you through sorting it, one drag at a time. You make every move.</p>

<h2>Features</h2>
<h3>Analyze, Blueprint, Sorting Guide</h3>
<p>Press <strong>Analyze Bank</strong> and every item is tinted with the colour of the tab it belongs in. <strong>Open Blueprint</strong> shows the plan tab by tab. Press <strong>Start Sorting</strong> and the guide marks the item to <strong>MOVE</strong> and draws an arrow to exactly where it goes: a bar in the gap where it should be inserted, or an outline around the tab button to drop it on. It re-plans from your real bank after every move.</p>

<h3>Keep your tabs, or design new ones</h3>
<p><strong>My tabs</strong> keeps the tabs you already have. Tab 1 (infinity) is the misc catch-all, and loose items go to the tab that already holds most of their kind. Pin any kind of item to a tab, remove it, or swap whole tabs around.</p>
<p><strong>Whole bank</strong> follows your <strong>Tab Layout</strong>. Add, delete, rename and reorder tabs, and choose which kinds of item each one holds and in what order. <strong>Copy my current tabs</strong> starts you from the bank you already have.</p>

<h3>Sorted the way you would sort it</h3>
<p>Inside each tab, <strong>Smart</strong> sorting groups gear by combat style (melee, ranged, magic, necromancy), then by slot (weapon, off-hand, head, body, legs and so on), best items first. Herblore is grouped by recipe chain, so every overload ingredient sits together, herb next to its unfinished potion and the potion it makes. Outfits stay together as sets, runes follow the game's order, potions keep their doses side by side, food goes by healing tier, teleports by type and charges, tools by skill, and clues by tier. Smart is the default. Prefer something simpler? Sort by <strong>Name</strong>, <strong>Item ID</strong> or <strong>Value</strong> (live Grand Exchange prices, or the game's own item value for items the GE does not trade), <strong>Quantity</strong> (highest or lowest first), or choose <strong>Keep my order</strong> to only move items between tabs.</p>

<h3>Share your layout</h3>
<p><strong>Share or Load a Setup</strong> turns your whole bank setup into one line of text. Post it anywhere, and anyone can paste it in to use your layout.</p>

<h3>Tag anything</h3>
<p>Right-click any bank item and choose <strong>Tags</strong>: set its category, keep it <strong>Active</strong> or as <strong>Vanity</strong> at the top of your infinity tab (rares like partyhats go there automatically), make it a <strong>Favourite</strong> first in its tab, or line it up to <strong>Sell</strong>, <strong>Alch</strong>, <strong>Disassemble</strong> or <strong>Trash</strong> at the bottom. Or <strong>Ignore</strong> it entirely.</p>

<h3>Decant labels and vertical sorting</h3>
<p>Part-dose potions you can combine get a <strong>DECANT</strong> label, and you choose which doses count. Prefer your bank in columns? Switch <strong>Sort direction</strong> to <strong>Vertical</strong>.</p>

<h3>Checks every move</h3>
<p>Swapped when you should have inserted, or dropped an item in the wrong spot? The guide notices, tells you <strong>Not quite</strong>, and walks you back before carrying on. Or press <strong>Continue from here</strong> to keep the new layout.</p>

<h3>Ignore anything</h3>
<p>Right-click any bank item and choose <strong>Ignore (Bank Organizer)</strong>. It stays exactly where it is and everything else sorts around it.</p>

<h3>Starting from scratch</h3>
<p>No tabs yet? The guide shows you which item to drop on the <strong>+</strong> button to start each new tab, in order.</p>

<h3>Smart classification</h3>
<p>About 30 kinds of item, including Runes, Summoning, MTX &amp; XP Boosts, Skilling Outfits, Potions and Herbs. Items are recognised from the game's own item categories, their right-click options and their names. Anything it gets wrong, fix it from the right-click <strong>Tags</strong> window: pick its category. Your choice always wins.</p>

<h3>Customizable</h3>
<p>Every tab colour, the MOVE highlight, the drop target and the guide line can be changed, along with tint opacity and insert or swap mode.</p>

<h2>How to use</h2>
<ol>
<li>Open your bank and enable the plugin.</li>
<li>Choose <strong>My tabs</strong> or <strong>Whole bank</strong> in the sidebar.</li>
<li>Press <strong>Analyze Bank</strong>, check the <strong>Blueprint</strong>, then press <strong>Start Sorting</strong> and follow the line.</li>
</ol>

<h2>Fair play</h2>
<p>Bank Organizer never moves, withdraws or clicks anything for you. It only reads the items your bank is already showing and draws on top. Every move is made by you. Bank Organizer itself has no internet access, no chat access and no tracking. Live GE prices come from the GE Price Library, which downloads them from the RuneScape Wiki prices API.</p>

<h2>Requires</h2>
<p><strong>PrettyUI</strong> and the <strong>GE Price Library</strong> (both installed automatically as dependencies).</p>

<p>Created by <strong>6ing</strong>. Feedback and bug reports are welcome in the comments.</p>
```

---

## Tag selection

**Official**
- Jagex recommended: locked (Jagex sets this)

**Gameplay**: none

**Theme**
- Interface: **checked**
- Utility: **checked**
- Items and Inventory: **checked**

**Technical**: none
(Do not tick "Library for other Plugins". This plugin uses a library; it isn't one.)

**Permissions**: **none**
The plugin makes no HTTP requests, doesn't read chat, and does no tracking, so it needs no permissions. Fewer permissions also means a faster review and more user trust.

**Mobile**
- Mobile UI friendly: **unchecked** (Jagex says plugins are PC-only at launch)

---

## Visibility

**Plugin visibility:** start with **Private**. Switch it to **Public** once it has been tested in the live client.

This listing has two parts:
- The mod.io page: Private only hides the page, and you can edit it at any time.
- The plugin itself: it still goes through Jagex review before it reaches the in-game Plugin Hub.

---

## Before you submit (checklist)

- [ ] Confirm `contactEmailAddress` in `plugin.json` (set to im6ing@gmail.com).
- [ ] Test in the beta world (see the testing steps): Analyze, Blueprint, Sorting Guide line, Tab Layout.
- [ ] Upload `dist/bank-organizer-1.3.0.zip` as the plugin file.
- [ ] Upload your listing image.
