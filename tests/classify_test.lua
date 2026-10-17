local A = require("assert")
local Classify = require("src/core/classify")
local c = Classify.classify

local function ops(...)
  local set = {}
  for _, op in ipairs({ ... }) do set[op] = true end
  return set
end

local T = {}

-- Happy path: one representative item per category.
function T.currency_coins() A.eq(c({ name = "Coins" }), "currency") end
function T.currency_tokens() A.eq(c({ name = "Platinum token" }), "currency") end
function T.teleport_tablet_by_name() A.eq(c({ name = "Varrock teleport" }), "teleports") end
function T.teleport_by_op() A.eq(c({ name = "Amulet of glory (4)", ops = ops("rub", "wear") }), "teleports") end
function T.potion_by_dose() A.eq(c({ name = "Super restore (4)" }), "potions") end
function T.potion_by_op() A.eq(c({ name = "Saradomin brew flask (6)", ops = ops("drink") }), "potions") end
function T.food_by_op() A.eq(c({ name = "Shark", ops = ops("eat") }), "food") end
function T.combat_weapon() A.eq(c({ name = "Abyssal whip", ops = ops("wield") }), "combat") end
function T.combat_by_category() A.eq(c({ name = "Mystery", category = "ARMOUR_HEAD" }), "combat") end
function T.combat_runes() A.eq(c({ name = "Air rune" }), "combat") end
function T.skilling_pickaxe() A.eq(c({ name = "Rune pickaxe", ops = ops("wield") }), "skilling") end
function T.materials_logs() A.eq(c({ name = "Yew logs" }), "materials") end
function T.materials_ore() A.eq(c({ name = "Iron ore" }), "materials") end
function T.misc_fallback() A.eq(c({ name = "Ancient lamp" }), "misc") end

-- Precedence between overlapping rules.
function T.tablet_break_is_teleport() A.eq(c({ name = "Lumbridge tablet", ops = ops("break") }), "teleports") end
function T.wearable_teleport_ring_is_teleport()
  A.eq(c({ name = "Ring of duelling (8)", ops = ops("rub", "wear") }), "teleports")
end
function T.rune_armour_is_combat_not_rune() A.eq(c({ name = "Rune platebody", ops = ops("wear") }), "combat") end
function T.coin_pouch_not_currency() A.eq(c({ name = "Coin pouch" }), "misc") end
function T.warhammer_not_tool() A.eq(c({ name = "Dragon warhammer", ops = ops("wield") }), "combat") end
function T.barrows_not_bar() A.eq(c({ name = "Barrows totem" }), "misc") end

-- Name fallbacks used when the client exposes no ops (real RS3 names).
function T.combat_by_name_shield() A.eq(c({ name = "Mirror shield" }), "combat") end
function T.combat_by_name_bolts() A.eq(c({ name = "Rune bolts" }), "combat") end
function T.materials_arrowheads_not_arrows() A.eq(c({ name = "Bane arrowheads" }), "materials") end
function T.materials_bolt_tips() A.eq(c({ name = "Amethyst bolt tips" }), "materials") end
function T.materials_salvage() A.eq(c({ name = "Tiny bladed mithril salvage" }), "materials") end
function T.combat_mix_potion_stays_potion() A.eq(c({ name = "Super ranging mix (2)" }), "potions") end

-- Defensive inputs.
function T.nil_info() A.eq(c(nil), "misc") end
function T.empty_info() A.eq(c({}), "misc") end
function T.wrong_types() A.eq(c({ name = 42, ops = "eat", category = 7 }), "misc") end

return T
