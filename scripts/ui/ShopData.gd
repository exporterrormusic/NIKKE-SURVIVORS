class_name ShopData
extends RefCounted

## Static data for Shop upgrades.
## Extracted from ShopMenu.gd for modularity.
## Character signature upgrades were migrated to the in-run talent trees
## (see TalentData.gd, row 2) in the Phase 3 rework.
##
## Display fields (NIKKE supply-terminal shop):
##   glyph/tint  - flat icon-tile glyph + its color
##   per_level   - bonus gained per level, in `unit` ("%" or "HP")

const GENERAL_UPGRADES := [
	{"id": "atk", "name": "Attack", "desc": "+25% Attack Damage per level", "max_level": 99,
		"base_cost": 1, "glyph": "▲", "tint": Color(1.0, 0.824, 0.247), "per_level": 25, "unit": "%"},
	{"id": "hp", "name": "HP", "desc": "+1 Max HP per level", "max_level": 99,
		"base_cost": 1, "glyph": "✚", "tint": Color(1.0, 0.42, 0.38), "per_level": 1, "unit": "HP"},
	{"id": "speed", "name": "Speed", "desc": "+5% Movement Speed per level", "max_level": 99,
		"base_cost": 1, "glyph": "≫", "tint": Color(0.5, 0.878, 0.659), "per_level": 5, "unit": "%"},
	{"id": "crit", "name": "Critical", "desc": "+2% Critical Chance per level", "max_level": 99,
		"base_cost": 1, "glyph": "✦", "tint": Color(1.0, 0.647, 0.302), "per_level": 2, "unit": "%"},
	{"id": "xp", "name": "Experience", "desc": "+5% Experience Gain per level", "max_level": 99,
		"base_cost": 2, "glyph": "◈", "tint": Color(0.357, 0.824, 0.969), "per_level": 5, "unit": "%"},
]


## "+125%" / "+3 HP" style bonus text for a given level
static func format_bonus(upgrade: Dictionary, level: int) -> String:
	var amount: int = upgrade["per_level"] * level
	if upgrade["unit"] == "%":
		return "+%d%%" % amount
	return "+%d %s" % [amount, upgrade["unit"]]
