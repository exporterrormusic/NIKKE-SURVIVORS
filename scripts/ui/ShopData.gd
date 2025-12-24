class_name ShopData
extends RefCounted

## Static data for Shop upgrades.
## Extracted from ShopMenu.gd for modularity.

const GENERAL_UPGRADES := [
	{"id": "atk", "name": "ATK", "desc": "+25% Attack Damage", "max_level": 99, "base_cost": 1, "icon": "⚔️"},
	{"id": "hp", "name": "HP", "desc": "+1 Max HP", "max_level": 99, "base_cost": 1, "icon": "❤️"},
	{"id": "speed", "name": "SPD", "desc": "+5% Movement Speed", "max_level": 99, "base_cost": 1, "icon": "👟"},
	{"id": "crit", "name": "CRIT", "desc": "+2% Critical Chance", "max_level": 99, "base_cost": 1, "icon": "💥"},
	{"id": "xp", "name": "XP", "desc": "+5% Experience Gain", "max_level": 99, "base_cost": 2, "icon": "⭐"},
]

const CHARACTER_UPGRADES := {
	"snow_white": [
		{"id": "basic_attack", "name": "Best Girl", "desc": "Attacks leave burning trails for 1.5s. Enemies take 3% HP/s burn damage for 10s. Bosses take 1% HP/s.", "max_level": 1, "base_cost": 10, "icon": "🔥"},
		{"id": "master_mechanic", "name": "Master Mechanic", "desc": "Ammo Capacity: +100% for Rocket/Sniper, +50% for Minigun/SMG/Shotgun. Applies to Squad.", "max_level": 1, "base_cost": 10, "icon": "🔧"},
	],
	"scarlet": [
		{"id": "basic_attack", "name": "Rose's Core", "desc": "Sword slashes release 5 rose petal projectiles dealing full damage.", "max_level": 1, "base_cost": 10, "icon": "🌹"},
		{"id": "low_hp_damage", "name": "Scraping the Bottle", "desc": "Deal up to +100% damage based on missing HP (max bonus at 15% HP).", "max_level": 1, "base_cost": 20, "icon": "🩸"},
	],
	"rapunzel": [
		{"id": "basic_attack", "name": "I'm a Healer, But...", "desc": "All squad kills heal player for 2% max HP.", "max_level": 1, "base_cost": 10, "icon": "💖"},
		{"id": "burning_sensation", "name": "A Burning Sensation", "desc": "Healing Aura also burns enemies for equivalent damage (3-25% HP/s). Bosses capped at 3%.", "max_level": 1, "base_cost": 20, "icon": "🔥"},
	],
	"nayuta": [
		{"id": "basic_attack", "name": "Duplicity", "desc": "10% chance to spawn a Nayuta clone when ANY squad member kills an enemy.", "max_level": 1, "base_cost": 10, "icon": "👥"},
	],
	"commander": [
		{"id": "basic_attack", "name": "Obviously Anderson", "desc": "All squad attacks generate Burst gauge at 2x rate.", "max_level": 1, "base_cost": 10, "icon": "⚡"},
		{"id": "wave_heal", "name": "Good Genes", "desc": "Commander heals at wave end (or every 30s in timerless modes). Heals 2-10 based on Burst gauge: lower gauge = more healing.", "max_level": 1, "base_cost": 20, "icon": "💚"},
	],
	"marian": [
		{"id": "basic_attack", "name": "Main Heroine", "desc": "Replace minigun with a continuous purple beam cannon.", "max_level": 1, "base_cost": 10, "icon": "💜"},
		{"id": "beam_absorb", "name": "She'll Eat Anything", "desc": "Boss beams deal no damage to Marian. Instead, grants 5s of +100% damage and enhanced beam.", "max_level": 1, "base_cost": 20, "icon": "🍽️"},
	],
	"crown": [
		{"id": "basic_attack", "name": "Royal Knowledge", "desc": "All squad members earn XP at 2x rate.", "max_level": 1, "base_cost": 10, "icon": "👑"},
		{"id": "trombe_stacking", "name": "How Does This Keep Working?", "desc": "Trombe +35% size per use. Max 3 stacks, 12s each.", "max_level": 1, "base_cost": 20, "icon": "🐴"},
	],
	"kilo": [
		{"id": "talos_ammo", "name": "Build-a-Bullet", "desc": "Every 3rd bullet fired regenerates 1 ammo. Applies to Squad.", "max_level": 1, "base_cost": 10, "icon": "🤖"},
		{"id": "core_drop", "name": "Filling Crown's Ball Pit", "desc": "+50% core drop chance. Bosses have 50% chance for extra core.", "max_level": 1, "base_cost": 20, "icon": "🔴"},
	],
	"cecil": [
		{"id": "basic_attack", "name": "Three Wishes...", "desc": "Gain 3 extra lives. Revive at full HP with 5s invincibility.", "max_level": 1, "base_cost": 10, "icon": "✨"},
		{"id": "eden_shield", "name": "Noah's Defiance", "desc": "Kills by player (not summons) generate shield. Max 50% of HP.", "max_level": 1, "base_cost": 20, "icon": "🛡️"},
	],
	"sin": [
		{"id": "basic_attack", "name": "Magnetic Personality", "desc": "Passive aura permanently mind-controls nearby regular enemies.", "max_level": 1, "base_cost": 10, "icon": "🔮"},
		{"id": "wish_save", "name": "I WISH They Were Gone", "desc": "Once per match: When you would die, freeze time and destroy all non-boss enemies. Grants 3s invulnerability.", "max_level": 1, "base_cost": 20, "icon": "✨"},
	],
	"wells": [
		{"id": "ally_speed", "name": "I Can't Predict the Future", "desc": "All summoned allies move 50% faster.", "max_level": 1, "base_cost": 10, "icon": "⏰"},
		{"id": "chrono_intangibility", "name": "Chrono-\nIntangibility", "desc": "Player bullets phase through shields and boulders.", "max_level": 1, "base_cost": 20, "icon": "👻"},
	],
}
