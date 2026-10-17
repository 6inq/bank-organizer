# mod.io listing answers: Bank Organizer

Copy each field into the mod.io "Create Plugin" form. You're making the listing image yourself (16:9, min 512x288, max 8MB).

---

## Basics

**Plugin name**
```
Bank Organizer
```

**Summary** (250 character max; this is 235)
```
Colour-codes your bank by category and guides you through sorting it, one move at a time. Works on a single tab or your whole bank. Highlights which item to drag and where to drop it. You make every move; nothing is automated. By 6ing.
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
<p>Bank Organizer colour-codes your bank by category and guides you through sorting it, one move at a time. Works on a single tab or your entire bank.</p>

<h2>Features</h2>
<h3>Category overlays</h3>
<p>Every bank slot gets tinted by category: <strong>Teleports, Combat, Potions, Food, Skilling, Materials, Currency</strong> and <strong>Misc</strong>. Pick one category in the filter to dim everything else, so you can see at a glance what belongs together.</p>

<h3>Smart auto-categorize</h3>
<p>Items are sorted into categories automatically using their in-game category and right-click options (Eat, Drink, Wield, Rub, Break and so on). Anything it gets wrong, you can fix in one click.</p>

<h3>Right-click tagging</h3>
<p>Turn on <em>Tag items via right-click</em>, then right-click any bank item and choose <strong>Bank Organizer &gt; Set: Food</strong> (or any category). Your tags are saved and always override the automatic guess. <em>Highlight untagged</em> outlines everything you haven't confirmed yet.</p>

<h3>Guided ordering</h3>
<p>Press <strong>Start Organizing</strong> and the plugin works out the shortest sequence of moves to put the tab in order: by category, then by item ID or by name. It highlights the item to move in green and the drop target in yellow, with a step like <em>"Insert Shark before Rocktail"</em> and a count of moves remaining. Drag the item yourself and the next step appears instantly. Use <strong>Skip item</strong> to leave something where it is.</p>

<h3>Your tab, or your whole bank</h3>
<p>Bank Organizer works on whatever your bank is showing. Open a tab to organize just that tab, or open <em>All items</em> to organize everything. (Tip: ordering in All items can move items between tabs, so organize tab by tab to keep your tabs intact.)</p>

<h3>Customizable</h3>
<p>Every option lives in the settings panel: sort order, overlays, category filter, opacity and right-click tagging. Every colour is yours to change: each category, the MOVE highlight, the drop target, the filter dim and the untagged outline. You can reset all your tags at any time.</p>

<h2>How to use</h2>
<ol>
<li>Open your bank.</li>
<li>Enable the plugin.</li>
<li>Go through the settings (gear icon) and make sure everything is how you want it to be.</li>
<li>Click <strong>Start Organizing</strong>, then follow the highlighted moves.</li>
</ol>
<p>Want to change something? Click <strong>Stop Organizing</strong> (the Start button turns into this while it runs), edit your settings, then start again. Settings are locked while organizing so nothing shifts under you.</p>

<h2>Fair play</h2>
<p>Bank Organizer never moves, withdraws or clicks anything for you. It only reads the items your bank is already showing and draws highlights on top. Every move is made by you. No internet access, no chat access, no tracking.</p>

<h2>Requires</h2>
<p><strong>PrettyUI</strong> (installed automatically as a dependency).</p>

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
- [ ] Test in the live client, then fix anything the reverse-engineered API got wrong.
- [ ] Upload `dist/bank-organizer-1.1.0.zip` as the plugin file.
- [ ] Upload your listing image.
