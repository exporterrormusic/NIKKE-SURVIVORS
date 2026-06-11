class_name ShopData
extends RefCounted

## Static data for Shop upgrades.
## Extracted from ShopMenu.gd for modularity.
## Character signature upgrades were migrated to the in-run talent trees
## (see TalentData.gd, row 2) in the Phase 3 rework.

const GENERAL_UPGRADES := [
	{"id": "atk", "name": "ATK", "desc": "+25% Attack Damage", "max_level": 99, "base_cost": 1, "icon": "⚔️"},
	{"id": "hp", "name": "HP", "desc": "+1 Max HP", "max_level": 99, "base_cost": 1, "icon": "❤️"},
	{"id": "speed", "name": "SPD", "desc": "+5% Movement Speed", "max_level": 99, "base_cost": 1, "icon": "👟"},
	{"id": "crit", "name": "CRIT", "desc": "+2% Critical Chance", "max_level": 99, "base_cost": 1, "icon": "💥"},
	{"id": "xp", "name": "XP", "desc": "+5% Experience Gain", "max_level": 99, "base_cost": 2, "icon": "⭐"},
]
