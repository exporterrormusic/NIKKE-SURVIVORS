extends Control
class_name TalentTree

## Talent Tree UI System - Clean container-based architecture
## Shows 3 character portraits, clicking opens their skill tree

signal talent_unlocked(character_id: int, talent_id: String)
signal tree_closed

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

# Preload portraits at class level to avoid runtime loading issues
var _portraits: Array[Texture2D] = []
var _burst_portraits: Array[Texture2D] = []

# UI References
var _main_panel: PanelContainer = null
var _character_panel: VBoxContainer = null
var _tree_panel: VBoxContainer = null
var _current_character: int = -1

# Character data - loaded from CharacterRegistry
var CHARACTER_NAMES: Array[String] = []
var PORTRAIT_PATHS: Array[String] = []
var BURST_PORTRAIT_PATHS: Array[String] = []
var _character_registry = null
var _game_state = null

# Which characters to show in shop cards (indices into CHARACTER_NAMES/TALENT_DATA)
# This is now loaded from GameState to sync with character selection
var _shop_character_order: Array[int] = [8, 9, 4]  # Default: Cecil, Nayuta, Marian

# Talent definitions - Simplified: 3 main abilities + 4 upgrades (2 per special/burst)
# Layout: UNLOCK (row 0) -> SPECIAL (row 1) -> BURST (row 2)
# Side upgrades: 2 for special (row 1, cols 0,2), 2 for burst (row 2, cols 0,2)
# IMPORTANT: Indices match CharacterRegistry order:
# 0=snow_white, 1=scarlet, 2=rapunzel, 3=nayuta, 4=commander, 5=marian, 6=crown, 7=kilo, 8=cecil, 9=sin
var TALENT_DATA := {
	0: [  # Snow White - Sniper with Turret
		{"id": "unlock", "name": "Unlock Snow White", "desc": "Add Snow White to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Sniper with piercing shots. 7 ammo, 1.5s reload."},
		{"id": "special", "name": "Auto-Turret", "desc": "Deploy auto-targeting turrets", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Deploys turret with 4 missiles. 1 charge, 8s recharge."},
		{"id": "special_capacity", "name": "Ammo Cache", "desc": "+2 turret missile capacity", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "+2 missiles per turret. Max: 10 missiles."},
		{"id": "special_count", "name": "More Turrets", "desc": "+2 max turret charges", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "+2 charges per level. Max: 7 turrets."},
		{"id": "burst", "name": "Seven Dwarves", "desc": "BURST: Freezing storm", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "90° ice beam dealing 50 damage. Massive range."},
		{"id": "burst_burn", "name": "Incendiary Rounds", "desc": "Burns enemies for 34% max HP/s", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "3s burn. Bosses take 12% max HP/s instead."},
		{"id": "burst_gauge", "name": "Fully Active", "desc": "Kills during burst refill gauge", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Burst kills generate burst gauge for chaining."},
	],
	1: [  # Scarlet - Melee DPS
		{"id": "unlock", "name": "Unlock Scarlet", "desc": "Add Scarlet to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Melee warrior who loses 3% max HP per attack but deals high damage."},
		{"id": "special", "name": "Dash Slash", "desc": "Dash leaves a damaging wave", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Dash releases a piercing wave dealing 8 damage. 4s cooldown."},
		{"id": "special_cd", "name": "Quick Dash", "desc": "-1s special cooldown", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "-1s cooldown per level. At max: 1s cooldown."},
		{"id": "special_heal", "name": "Vampiric Slash", "desc": "Heals 5/15/25% max HP per hit", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Wave heals per enemy hit while still dealing damage."},
		{"id": "burst", "name": "Scarlet Flash", "desc": "BURST: Devastating slash wave", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Costs 50% HP. Hits all enemies on screen. Teleports to last target."},
		{"id": "burst_execute", "name": "Execution", "desc": "Instant kill + heals 15% max HP per kill", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Regular enemies die instantly. Heals 15% max HP per kill. Elites/bosses take normal damage."},
		{"id": "burst_vuln", "name": "Expose Weakness", "desc": "Surviving targets take 50% more damage", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Marked enemies take +50% damage from all sources."},
	],
	2: [  # Rapunzel - Support Healer
		{"id": "unlock", "name": "Unlock Rapunzel", "desc": "Add Rapunzel to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Support with explosive missiles and healing abilities."},
		{"id": "special", "name": "Divine Blessing", "desc": "Create a healing zone", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Heals 3% max HP/s for 9s. 10s cooldown."},
		{"id": "special_power", "name": "Rejuvenation", "desc": "Healing: 10/17.5/25% max HP/s", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Increases healing power dramatically."},
		{"id": "special_size", "name": "Expanding Aura", "desc": "Zone size +50/150/300%", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Larger healing radius."},
		{"id": "burst", "name": "Garden of Shangri-La", "desc": "BURST: Massive heal + stun", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Full heal + 4s stun on all enemies."},
		{"id": "burst_stun", "name": "Blinding Radiance", "desc": "Stun duration increased to 8s", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Doubles stun from 4s to 8s."},
		{"id": "burst_invuln", "name": "Divine Protection", "desc": "8 seconds of invincibility", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Grants 8s invincibility on burst."},
	],
	3: [  # Nayuta - SMG with Clone Summoning & Galaxy Burst
		{"id": "unlock", "name": "Unlock Nayuta", "desc": "Add Nayuta to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "SMG user. 30 ammo, high fire rate. Summons clones."},
		{"id": "special", "name": "Summon Clone", "desc": "Summon a fighting clone", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Summons clone with 1/2 HP/attack. Lives until killed. 8s cooldown."},
		{"id": "special_heal", "name": "NIMPH Return", "desc": "Clone death heals 20/35/50%", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "When clone dies, gold sparkles travel to you and heal % max HP."},
		{"id": "special_weapon", "name": "WEAPON MASTER", "desc": "Clones can use +sword/rocket/sniper", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Adds new weapons to clone pool. Random selection on summon."},
		{"id": "burst", "name": "Asceticism", "desc": "BURST: Massive space explosion", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Purple galaxy explosion damages all enemies on screen."},
		{"id": "burst_stun", "name": "Nirvana", "desc": "Stun bosses/elites 8s", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Bosses and elites hit by burst are stunned for 8 seconds."},
		{"id": "burst_debuff", "name": "Impermanence", "desc": "Bosses/elites take 50% more damage", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Marked enemies take +50% damage. Purple star effect shows debuff."},
	],
	4: [  # Commander - Assault Rifle with Time Freeze & Ally Summons
		{"id": "unlock", "name": "Commander", "desc": "Already in your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 0, "unlock": true, "default": true,
		 "tooltip": "Leader with assault rifle. Stuns enemies and summons allies."},
		{"id": "special", "name": "I've Got a Meeting", "desc": "Stun all enemies in time", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Stuns all enemies on screen for 3s. 12s cooldown."},
		{"id": "special_duration", "name": "Hold That Thought", "desc": "+1s stun duration", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "+1s duration per level. Max: 6s stun."},
		{"id": "special_cooldown", "name": "Enikk is Calling", "desc": "-2s special cooldown", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "-2s cooldown per level. Min: 6s cooldown."},
		{"id": "burst", "name": "Goddess Squad", "desc": "BURST: Summon AI allies", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Summons 1 random ally (Scarlet/Snow White/Rapunzel) for 10s."},
		{"id": "burst_left", "name": "Reinforcements I", "desc": "Summon +1 ally", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Summons 2 allies instead of 1."},
		{"id": "burst_right", "name": "Reinforcements II", "desc": "Summon +1 ally", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Summons 3 allies instead of 2. All 3 types available."},
	],
	5: [  # Marian - Minigun with Charm & Epic Beam
		{"id": "unlock", "name": "Unlock Marian", "desc": "Add Marian to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Minigun user. 100 ammo, high fire rate. Charms enemies and fires epic beams."},
		{"id": "special", "name": "Rapture Queen", "desc": "AoE charm converts enemies", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Charms normal enemies in area to fight for you. 10s cooldown."},
		{"id": "special_size", "name": "Queen Gene", "desc": "AoE + enemy types", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "AoE +50/100/200%. Lv1: Also affects Tanks. Lv2: Also affects Elites. Lv3: Stuns Bosses for 3s."},
		{"id": "special_cooldown", "name": "Royal Dominion", "desc": "-2s special cooldown", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "-2s cooldown per level. At max: 4s cooldown."},
		{"id": "burst", "name": "New World", "desc": "BURST: Epic 5s laser beam", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "5 second aimable purple laser beam. Follow mouse to aim."},
		{"id": "burst_left", "name": "Missile Barrage", "desc": "Fire 4 homing missiles every 2.5s", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "During burst, fires 4 homing missiles at random enemies twice."},
		{"id": "burst_right", "name": "Queen Beam", "desc": "Beam leaves purple fire", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Beam leaves a 5s burning trail that damages enemies."},
	],
	6: [  # Crown - Minigun with Cavalry Charge & Golden Nova
		{"id": "unlock", "name": "Unlock Crown", "desc": "Add Crown to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Minigun user. 100 ammo, high fire rate. Cavalry charge and golden nova."},
		{"id": "special", "name": "Summon Trombe", "desc": "Summon Trombe, charge forward", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Summon Trombe, charge forward with V-damage. Invincible. 2.5s duration, 10s cooldown."},
		{"id": "special_cooldown", "name": "Swift Steed", "desc": "-2s charge cooldown", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "-2s cooldown per level. At max: 4s cooldown."},
		{"id": "special_explosion", "name": "Royal Charge", "desc": "Survivors explode after 1.5s", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Enemies hit but not killed glow gold, explode for 2x ATK. +50% dmg, +20% range per level."},
		{"id": "burst", "name": "Last Kingdom", "desc": "BURST: Screen-wide blast", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Massive golden AoE blast fills the screen for massive damage."},
		{"id": "burst_charge", "name": "One for All", "desc": "Burst generates burst gauge", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Burst damage now contributes to burst gauge charging."},
		{"id": "burst_beam", "name": "Naked King", "desc": "Adds 3s forward beam", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Adds massive golden frontal beam lasting 3s dealing huge damage."},
	],
	7: [  # Kilo - Shotgun DPS
		{"id": "unlock", "name": "Unlock Kilo", "desc": "Add Kilo to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Shotgun wielder. 8 ammo, 5 pellets per shot. Pilot of T.A.L.O.S."},
		{"id": "special", "name": "Explosive Shells", "desc": "Pellets create explosive beams", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Pellet hits trigger V-shaped explosions behind enemies. 3s cooldown."},
		{"id": "special_burn", "name": "Searing Beams", "desc": "Beams burn for 15/25/35% HP/s", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "3s burn. Elites/bosses take 5/10/15% instead."},
		{"id": "special_size", "name": "Amplified Blast", "desc": "Explosion +50/100/200% size & +30/60/100% dmg", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Bigger and more damaging explosions."},
		{"id": "burst", "name": "Assign Priority", "desc": "BURST: Rapid fire frenzy", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Infinite ammo, rapid fire, 2.2x damage for 5s."},
		{"id": "burst_duration", "name": "Extended Assault", "desc": "Burst lasts 10 seconds", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Doubles burst duration from 5s to 10s."},
		{"id": "burst_invuln", "name": "T.A.L.O.S. Shield", "desc": "Invincible during burst", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Grants invincibility for burst duration."},
	],
	8: [  # Cecil - SMG with Drones & Hacking Burst
		{"id": "unlock", "name": "Unlock Cecil", "desc": "Add Cecil to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "SMG user. 30 ammo, high fire rate. Drone robots and hacking burst."},
		{"id": "special", "name": "Drone Deploy", "desc": "Deploy 2 companion drones", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Deploys 2 invincible drones. Right-click toggles Hunt/Shield modes."},
		{"id": "special_speed", "name": "Overclock", "desc": "Drone speed +50/100/200%", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Drones move and attack faster per level."},
		{"id": "special_shield", "name": "Barrier Protocol", "desc": "Shield absorbs +1 hit", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Shield mode absorbs +1 hit per level. Max: 4 hits."},
		{"id": "burst", "name": "System Hack", "desc": "BURST: Freeze & convert enemies", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Freeze all enemies 1.5s. Non-elite/boss become permanent allies."},
		{"id": "burst_damage", "name": "Malware", "desc": "Hacked allies +50% damage", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Converted enemies deal 50% more damage."},
		{"id": "burst_boss", "name": "Exploit", "desc": "25% max HP to elites/bosses", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Elites and bosses take 25% of their max HP as damage after stun."},
	],
	9: [  # Sin - SMG with Charm & Life Drain
		{"id": "unlock", "name": "Unlock Sin", "desc": "Add Sin to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "SMG user. 30 ammo, high fire rate. Charms enemies and drains life."},
		{"id": "special", "name": "Heavy Talker", "desc": "AoE charm converts enemies", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Charms normal enemies in area to fight for you. 10s cooldown."},
		{"id": "special_size", "name": "Loud Talker", "desc": "Charm AoE +50/100/200%", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Increases charm area of effect."},
		{"id": "special_cooldown", "name": "Captivating", "desc": "Charmed deaths empower Sin", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Lv1: Charmed enemy deaths explode. Lv2: Also heal 1 HP. Lv3: Can charm Tanks."},
		{"id": "burst", "name": "Words Can Kill", "desc": "BURST: ATK DOT that heals", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "4s DOT dealing 10x ATK damage every second. Heals 5% max HP per enemy hit per tick."},
		{"id": "burst_charge", "name": "You'll Steal for Me", "desc": "Kills during burst charge gauge", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Enemy kills during burst contribute to burst gauge."},
		{"id": "burst_explode", "name": "You'll Die for Me", "desc": "Enemies explode on death", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Enemies dying during burst explode for 4 damage. Scales with ATK."},
	]
}

# Tooltip UI reference
var _tooltip: PanelContainer = null

# Stats panel reference
var _stats_panel: PanelContainer = null
var _player_ref: Node = null  # Reference to player for stats
var _hovered_character: int = -1  # Which character card is being hovered (-1 = none/current)
var _last_hovered_character: int = -1  # Last character that was hovered (for sticky display)

# Player's unlocked talents
var _unlocked_talents: Dictionary = {0: {}, 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}, 8: {}, 9: {}}
var _skill_points: int = 0: set = set_skill_points
var _talent_buttons: Array = []
var _lines_control: Control = null

# Animation state for scanline effect
var _scanline_overlay: Control = null
var _anim_state := 0  # 0=hidden, 1=animating in, 2=showing, 3=animating out
var _anim_progress := 0.0
var _anim_time := 0.0
const ANIM_DURATION := 0.5
var _pending_unpause := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure TalentTree is rendered above all other UI
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # Process during pause
	
	# Load character data from registry
	_load_character_data()
	
	# Preload all portraits (both regular and burst)
	for path in PORTRAIT_PATHS:
		var tex = load(path)
		_portraits.append(tex)
	
	for i in range(BURST_PORTRAIT_PATHS.size()):
		var path = BURST_PORTRAIT_PATHS[i]
		var tex = null
		if ResourceLoader.exists(path):
			tex = load(path)
		else:
			# Fallback to regular portrait if burst doesn't exist
			if i < PORTRAIT_PATHS.size():
				tex = load(PORTRAIT_PATHS[i])
		_burst_portraits.append(tex)
	
	_build_ui()
	_build_scanline_overlay()
	visible = false
	_apply_default_talents()
	_refresh_character_cards()  # Refresh after defaults are applied

func _load_character_data() -> void:
	# Get registry using class_name directly
	_character_registry = CharacterRegistry.get_instance()
	
	# Get GameState for shop character order (it's an autoload singleton)
	var game_state_node = get_node_or_null("/root/GameState")
	if game_state_node:
		_game_state = game_state_node
		_shop_character_order = _game_state.get_shop_character_order()
	
	# Load character names and portrait paths from registry
	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		for id in char_ids:
			var char_data = _character_registry.get_character(id)
			if char_data:
				CHARACTER_NAMES.append(char_data.display_name)
				# Build portrait path from id
				var folder_name: String = id.replace("_", "-")
				PORTRAIT_PATHS.append("res://assets/characters/%s/portrait-sq.png" % folder_name)
				# Build burst portrait path - try burst.png first, then character-specific name
				var burst_path: String = "res://assets/characters/%s/burst.png" % folder_name
				BURST_PORTRAIT_PATHS.append(burst_path)
	else:
		# Fallback if registry not available
		CHARACTER_NAMES = ["Scarlet", "Commander", "Rapunzel", "Kilo", "Marian", "Crown", "Snow White", "Sin", "Cecil", "Nayuta"]
		PORTRAIT_PATHS = [
			"res://assets/characters/scarlet/portrait-sq.png",
			"res://assets/characters/commander/portrait-sq.png",
			"res://assets/characters/rapunzel/portrait-sq.png",
			"res://assets/characters/kilo/portrait-sq.png",
			"res://assets/characters/marian/portrait-sq.png",
			"res://assets/characters/crown/portrait-sq.png",
			"res://assets/characters/snow-white/portrait-sq.png",
			"res://assets/characters/sin/portrait-sq.png",
			"res://assets/characters/cecil/portrait-sq.png",
			"res://assets/characters/nayuta/portrait-sq.png"
		]
		BURST_PORTRAIT_PATHS = [
			"res://assets/characters/scarlet/burst.png",
			"res://assets/characters/commander/burst.png",
			"res://assets/characters/rapunzel/burst.png",
			"res://assets/characters/kilo/burst.png",
			"res://assets/characters/marian/burst.png",
			"res://assets/characters/crown/burst.png",
			"res://assets/characters/snow-white/burst.png",
			"res://assets/characters/sin/burst.png",
			"res://assets/characters/cecil/burst.png",
			"res://assets/characters/nayuta/burst.png"
		]

func _build_ui() -> void:
	# Full screen dark overlay
	var overlay := ColorRect.new()
	overlay.color = UI.BG_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# Main centered container - above the overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	# Outer HBox to hold stats panel + main panel
	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 15)
	center.add_child(outer_hbox)
	
	# Stats panel on the left (HoloCure style)
	_stats_panel = _build_stats_panel()
	outer_hbox.add_child(_stats_panel)
	
	# Main panel with border
	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(1000, 750)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI.BG_DEEP
	panel_style.border_color = UI.ACCENT_PRIMARY_DIM
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(15)
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	outer_hbox.add_child(_main_panel)
	
	# Content container (switches between character select and tree view)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_panel.add_child(content)
	
	# Character selection panel
	_character_panel = VBoxContainer.new()
	_character_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_character_panel.add_theme_constant_override("separation", 10)
	content.add_child(_character_panel)
	_build_character_panel()
	
	# Tree panel (hidden initially)
	_tree_panel = VBoxContainer.new()
	_tree_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree_panel.add_theme_constant_override("separation", 15)
	_tree_panel.visible = false
	content.add_child(_tree_panel)
	
	# Create tooltip (added last so it renders on top)
	_create_tooltip()

func _build_scanline_overlay() -> void:
	# Create scanline overlay for cyberpunk animation effect - positioned over the main panel
	_scanline_overlay = Control.new()
	_scanline_overlay.name = "ScanlineOverlay"
	_scanline_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scanline_overlay.z_index = 200
	_scanline_overlay.visible = false
	_scanline_overlay.clip_contents = true  # Clip to bounds
	add_child(_scanline_overlay)
	_scanline_overlay.draw.connect(_draw_scanline_overlay)

func _draw_scanline_overlay() -> void:
	if _anim_state == 0 or _anim_state == 2:
		return
	
	# Draw relative to overlay size (which matches main panel)
	var panel_size := _scanline_overlay.size
	var intensity := 0.0
	
	if _anim_state == 1:  # Animating in
		intensity = 1.0 - _anim_progress
	elif _anim_state == 3:  # Animating out
		intensity = _anim_progress
	
	# Fine scanline effect - more detail as requested
	var scanline_count := 40  # More scanlines for finer detail
	var scanline_color := Color(0.3, 0.8, 1.0, intensity * 0.5)
	var glow_color := Color(0.2, 0.6, 0.9, intensity * 0.25)
	
	for i in range(scanline_count):
		var y_base := (float(i) / scanline_count) * panel_size.y
		var wave := sin(_anim_time * 15.0 + float(i) * 0.5) * 2.0
		var y := y_base + wave
		
		# Flickering scanlines - faster, finer
		var flicker := (sin(_anim_time * 30.0 + float(i) * 1.8) + 1.0) * 0.5
		if flicker > 0.3:
			_scanline_overlay.draw_line(Vector2(0, y), Vector2(panel_size.x, y), glow_color, 4.0)
			_scanline_overlay.draw_line(Vector2(0, y), Vector2(panel_size.x, y), scanline_color, 1.0)
	
	# Digital noise pixels - small glitchy squares
	var pixel_count := int(intensity * 30)
	for i in range(pixel_count):
		var px := fmod(_anim_time * 80.0 * (float(i) + 1.0) + float(i) * 23.0, panel_size.x)
		var py := fmod(_anim_time * 60.0 * (float(i) + 0.5) + float(i) * 37.0, panel_size.y)
		var pixel_size := randf_range(2.0, 6.0) * intensity
		var pixel_color := Color(0.4, 0.9, 1.0, intensity * 0.6)
		_scanline_overlay.draw_rect(Rect2(px, py, pixel_size, pixel_size), pixel_color)
	
	# Horizontal glitch bars - smaller, more subtle
	var glitch_count := int(intensity * 4)
	for i in range(glitch_count):
		var glitch_y := fmod(_anim_time * 200.0 + float(i) * 80.0, panel_size.y)
		var glitch_width := randf_range(40.0, 120.0) * intensity
		var glitch_x := fmod(_anim_time * 150.0 * (float(i) + 1.0), panel_size.x)
		var glitch_color := Color(0.3, 0.9, 1.0, intensity * 0.4)
		_scanline_overlay.draw_rect(Rect2(glitch_x, glitch_y, glitch_width, 2.0), glitch_color)
	
	# Edge glow on panel borders
	var edge_glow := Color(0.2, 0.7, 1.0, intensity * 0.5)
	_scanline_overlay.draw_rect(Rect2(0, 0, panel_size.x, 3), edge_glow)
	_scanline_overlay.draw_rect(Rect2(0, panel_size.y - 3, panel_size.x, 3), edge_glow)
	_scanline_overlay.draw_rect(Rect2(0, 0, 3, panel_size.y), edge_glow)
	_scanline_overlay.draw_rect(Rect2(panel_size.x - 3, 0, 3, panel_size.y), edge_glow)

func _process(delta: float) -> void:
	if _anim_state == 0:
		return
	
	_anim_time += delta
	
	if _anim_state == 1:  # Animating in
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_anim_state = 2
			if _scanline_overlay:
				_scanline_overlay.visible = false
		else:
			if _scanline_overlay:
				_scanline_overlay.queue_redraw()
		# Fade in content
		modulate.a = _anim_progress
		
	elif _anim_state == 3:  # Animating out
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_finish_close()
		else:
			if _scanline_overlay:
				_scanline_overlay.queue_redraw()
		# Fade out content
		modulate.a = 1.0 - _anim_progress

func _finish_close() -> void:
	_anim_state = 0
	visible = false
	modulate.a = 1.0
	if _scanline_overlay:
		_scanline_overlay.visible = false
	# Always unpause on close to resume gameplay
	_pending_unpause = false
	get_tree().paused = false
	emit_signal("tree_closed")

func _build_stats_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 750)
	
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY_DIM
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(15)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	vbox.add_child(title)
	
	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)
	
	# Character name display (shows which character stats are for)
	var char_label := Label.new()
	char_label.name = "CharLabel"
	char_label.text = "Current"
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.add_theme_font_size_override("font_size", 16)
	char_label.add_theme_color_override("font_color", UI.TALENT_HOVER_BORDER)
	vbox.add_child(char_label)
	
	# Small spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer1)
	
	# Level display
	var level_row := _create_stat_row("LVL", "1", Color(1.0, 0.85, 0.3))
	level_row.name = "LevelRow"
	vbox.add_child(level_row)
	
	# Small spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# ATK stat (multiplier based on level)
	var atk_row := _create_stat_row("ATK", "1x", Color(1.0, 0.4, 0.4))
	atk_row.name = "AtkRow"
	vbox.add_child(atk_row)
	
	# HP stat
	var hp_row := _create_stat_row("HP", "10", Color(0.4, 1.0, 0.4))
	hp_row.name = "HpRow"
	vbox.add_child(hp_row)
	
	# Burst Gen Rate stat (% per hit)
	var burst_row := _create_stat_row("BURST GEN", "5%", Color(0.4, 0.7, 1.0))
	burst_row.name = "BurstRow"
	vbox.add_child(burst_row)
	
	# Speed stat (actual value)
	var speed_row := _create_stat_row("SPEED", "400", Color(0.9, 0.7, 1.0))
	speed_row.name = "SpeedRow"
	vbox.add_child(speed_row)
	
	# Crit Rate stat
	var crit_row := _create_stat_row("CRIT RATE", "20%", Color(1.0, 0.6, 0.2))
	crit_row.name = "CritRow"
	vbox.add_child(crit_row)
	
	# Fill remaining space
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(filler)
	
	return panel

func _create_stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	
	# Stat name
	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	
	# Stat value
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", value_color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	
	return row

func _update_stats_panel(char_id: int = -1) -> void:
	if _stats_panel == null:
		return
	
	# Determine which character to show stats for
	# Priority: passed char_id > last hovered > main character (slot 1 in shop order)
	var display_char: int = char_id
	if display_char < 0:
		if _last_hovered_character >= 0:
			display_char = _last_hovered_character
		elif _shop_character_order.size() > 1:
			display_char = _shop_character_order[1]  # Main character is middle slot
		elif _shop_character_order.size() > 0:
			display_char = _shop_character_order[0]
		else:
			display_char = 1  # Fallback to Commander
	
	# Update character label
	var char_name: String = CHARACTER_NAMES[display_char] if display_char >= 0 and display_char < CHARACTER_NAMES.size() else "Current"
	_set_char_label(char_name)
	
	# Get base character stats from CharacterRegistry for the hovered character
	# This shows the character's BASE stats, not the current player's in-game stats
	var current_level: int = 1
	var display_damage: int = 1
	var display_hp: int = 10
	var display_speed: int = 400
	var display_crit: float = 0.2
	var burst_rate: float = 1.0
	
	# Get level from player if in-game
	if _player_ref and is_instance_valid(_player_ref) and "level" in _player_ref:
		current_level = _player_ref.level
	
	# Always get base stats from the hovered character's data (not the player)
	if _character_registry:
		var char_data = _character_registry.get_character_by_index(display_char)
		if char_data:
			display_damage = int(char_data.base_damage)
			display_hp = char_data.base_hp
			display_speed = int(char_data.base_speed)
			display_crit = char_data.crit_chance if "crit_chance" in char_data else 0.2
			
			# Get burst rate from BurstConfig based on weapon type
			var weapon_type := _get_weapon_type_for_index(display_char)
			burst_rate = BurstConfig.get_rate(weapon_type)
	
	# Update labels with current values
	# Apply level damage multiplier (25% per level) to ATK display
	var level_damage_mult := 1.0 + (current_level - 1) * 0.25
	var scaled_damage := int(display_damage * level_damage_mult)
	
	_set_stat_value("LevelRow", str(current_level))
	_set_stat_value("AtkRow", str(scaled_damage))
	_set_stat_value("HpRow", str(display_hp))
	_set_stat_value("BurstRow", "%.1f%%" % burst_rate if burst_rate < 1.0 else "%.0f%%" % burst_rate)
	@warning_ignore("integer_division")
	_set_stat_value("SpeedRow", str(display_speed / 10))  # Display as /10 for readability
	_set_stat_value("CritRow", "%.0f%%" % (display_crit * 100.0))

func _set_char_label(char_name: String) -> void:
	if _stats_panel == null:
		return
	var vbox := _stats_panel.get_child(0)
	var char_label := vbox.get_node_or_null("CharLabel")
	if char_label != null:
		char_label.text = char_name

func _set_stat_value(row_name: String, value: String) -> void:
	if _stats_panel == null:
		return
	var vbox := _stats_panel.get_child(0)
	var row := vbox.get_node_or_null(row_name)
	if row != null:
		var value_label := row.get_node_or_null("Value")
		if value_label != null:
			value_label.text = value

func _get_weapon_type_for_index(char_index: int) -> String:
	# Map character index to weapon type for BurstConfig lookup
	# Indices: 0=snow_white, 1=scarlet, 2=rapunzel, 3=nayuta, 4=commander, 
	#          5=marian, 6=crown, 7=kilo, 8=cecil, 9=sin
	match char_index:
		0:  # Snow White
			return "sniper"
		1:  # Scarlet
			return "sword"
		2:  # Rapunzel
			return "rocket"
		3:  # Nayuta
			return "smg"
		4:  # Commander
			return "assault"
		5:  # Marian
			return "minigun"
		6:  # Crown
			return "minigun"
		7:  # Kilo
			return "shotgun"
		8:  # Cecil
			return "smg"
		9:  # Sin
			return "smg"
		_:
			return "smg"

func _build_character_panel() -> void:
	# Skill points display - enhanced and prominent
	var points_container := HBoxContainer.new()
	points_container.name = "PointsContainer"
	points_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_panel.add_child(points_container)
	
	# Decorative left element
	var deco_left := Label.new()
	deco_left.text = "◆ ─────"
	deco_left.add_theme_font_size_override("font_size", 20)
	deco_left.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 0.6))
	points_container.add_child(deco_left)
	
	# Main skill points label
	var points := Label.new()
	points.name = "SkillPoints"
	points.text = "   AVAILABLE SKILL POINTS: %d   " % _skill_points
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 32)
	points.add_theme_color_override("font_color", UI.TALENT_HOVER_BORDER)
	points_container.add_child(points)
	
	# Decorative right element
	var deco_right := Label.new()
	deco_right.text = "───── ◆"
	deco_right.add_theme_font_size_override("font_size", 20)
	deco_right.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 0.6))
	points_container.add_child(deco_right)
	
	# Small spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 15)
	_character_panel.add_child(spacer1)
	
	# Character cards row
	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 40)
	_character_panel.add_child(cards_row)
	
	for i in range(3):
		var char_id: int = _shop_character_order[i]
		var card := _create_character_card(char_id)
		cards_row.add_child(card)
	
	# Spacer (smaller to raise close button)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	_character_panel.add_child(spacer2)
	
	# Close button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_panel.add_child(btn_row)
	
	var close_btn := Button.new()
	close_btn.text = "✕ CLOSE"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.custom_minimum_size = Vector2(160, 50)
	close_btn.pressed.connect(_on_close)
	_style_button(close_btn)
	btn_row.add_child(close_btn)

func _create_character_card(char_id: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 520)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(140, 260)  # Center pivot for scale animation
	card.set_meta("char_id", char_id)
	
	# Connect mouse hover signals for stats panel update and animation
	card.mouse_entered.connect(_on_card_mouse_entered.bind(char_id, card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
	
	# Card style with white rounded border - add content margins so border is visible
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.02, 0.02, 0.04, 1.0)
	card_style.border_color = Color(1.0, 1.0, 1.0, 1.0)  # Pure white border
	card_style.set_border_width_all(4)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(4)  # Margin so content doesn't cover border
	card.add_theme_stylebox_override("panel", card_style)
	
	# Main container for layering (portrait + overlays) - offset to show border
	var main_container := Control.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.offset_left = 4
	main_container.offset_top = 4
	main_container.offset_right = -4
	main_container.offset_bottom = -4
	main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(main_container)
	
	# Clip container to keep portrait within rounded corners
	var clip_container := Control.new()
	clip_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_container.clip_contents = true
	clip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_container.add_child(clip_container)
	
	# Portrait - fills the entire card
	var portrait_rect := TextureRect.new()
	portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if char_id < _burst_portraits.size() and _burst_portraits[char_id] != null:
		portrait_rect.texture = _burst_portraits[char_id]
	elif char_id < _portraits.size() and _portraits[char_id] != null:
		portrait_rect.texture = _portraits[char_id]
	clip_container.add_child(portrait_rect)
	
	# === TOP OVERLAY: Name bar ===
	var name_bar := ColorRect.new()
	name_bar.color = Color(0.0, 0.0, 0.0, 0.75)
	name_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_bar.offset_bottom = 44
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_container.add_child(name_bar)
	
	var name_label := Label.new()
	var char_name: String = CHARACTER_NAMES[char_id]
	name_label.text = char_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_size: int = 22 if char_name.length() <= 12 else 16
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bar.add_child(name_label)
	
	# === BOTTOM OVERLAY: Status + Button ===
	var bottom_bar := ColorRect.new()
	bottom_bar.color = Color(0.0, 0.0, 0.0, 0.8)
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -130  # Raised to show more button
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_container.add_child(bottom_bar)
	
	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_vbox.add_theme_constant_override("separation", 2)
	bottom_vbox.alignment = BoxContainer.ALIGNMENT_END  # Push content toward bottom
	bottom_bar.add_child(bottom_vbox)
	
	# Button with padding (moved above count for better layout)
	var btn_margin := MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_left", 16)
	btn_margin.add_theme_constant_override("margin_right", 16)
	btn_margin.add_theme_constant_override("margin_top", 8)
	bottom_vbox.add_child(btn_margin)
	
	var click_btn := Button.new()
	click_btn.text = "View Talents"
	click_btn.add_theme_font_size_override("font_size", 20)
	click_btn.custom_minimum_size = Vector2(0, 44)
	click_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_btn.pressed.connect(_on_character_selected.bind(char_id))
	_style_button(click_btn)
	btn_margin.add_child(click_btn)
	
	# Unlock count (below button)
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1.0))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vbox.add_child(count_label)
	_update_card_count(count_label, char_id)
	
	# Status (below count, with margin at bottom)
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vbox.add_child(status_label)
	_update_card_status(status_label, char_id)
	
	# Bottom spacer for margin
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	bottom_vbox.add_child(spacer)
	
	return card

func _update_card_count(label: Label, char_id: int) -> void:
	# Count total talent points unlocked for this character (including unlock)
	var char_talents: Dictionary = _unlocked_talents.get(char_id, {})
	var unlocked: int = 0
	for talent_id in char_talents.keys():
		unlocked += char_talents[talent_id]  # Add the level/points spent
	# Total possible talent points = sum of all max levels (including unlock)
	var talent_list: Array = TALENT_DATA.get(char_id, [])
	var total: int = 0
	for talent in talent_list:
		total += talent.get("max", 1)
	label.text = "%d / %d Talents" % [unlocked, total]
	label.add_theme_color_override("font_color", UI.TALENT_UNLOCKED if unlocked == total else UI.TEXT_SECONDARY)

func _update_card_status(label: Label, char_id: int) -> void:
	# Check if character is unlocked via their talent tree "unlock" talent
	var is_unlocked: bool = _unlocked_talents.get(char_id, {}).has("unlock")
	if is_unlocked:
		label.text = "★ UNLOCKED"
		label.add_theme_color_override("font_color", UI.TALENT_UNLOCKED)
	else:
		# Don't show LOCKED text - just show nothing or a subtle indicator
		label.text = ""
		label.add_theme_color_override("font_color", UI.TALENT_LOCKED)

func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	normal.border_color = UI.ACCENT_PRIMARY_DIM
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	hover.border_color = UI.TALENT_HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

func _on_character_selected(char_id: int) -> void:
	_current_character = char_id
	_character_panel.visible = false
	_tree_panel.visible = true
	_build_tree_view(char_id)

func _build_tree_view(char_id: int) -> void:
	# Clear previous
	for child in _tree_panel.get_children():
		child.queue_free()
	_talent_buttons.clear()
	_lines_control = null
	
	# Title bar with character name
	var title_bar := HBoxContainer.new()
	title_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_panel.add_child(title_bar)
	
	var title := Label.new()
	title.text = CHARACTER_NAMES[char_id] + " - TALENTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	title_bar.add_child(title)
	
	# Skill points
	var points := Label.new()
	points.name = "TreeSkillPoints"
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 22)
	points.add_theme_color_override("font_color", UI.TALENT_HOVER_BORDER)
	points.text = "Skill Points: %d" % _skill_points
	_tree_panel.add_child(points)
	
	# Tree container panel (holds lines and nodes)
	var tree_panel := PanelContainer.new()
	tree_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tree_panel.custom_minimum_size = Vector2(720, 440)
	var tree_style := StyleBoxFlat.new()
	tree_style.bg_color = Color(0.03, 0.03, 0.05, 1.0)
	tree_style.border_color = Color(0.5, 0.5, 0.55, 1.0)
	tree_style.set_border_width_all(2)
	tree_style.set_corner_radius_all(8)
	tree_style.set_content_margin_all(10)
	tree_panel.add_theme_stylebox_override("panel", tree_style)
	_tree_panel.add_child(tree_panel)
	
	var tree_holder := Control.new()
	tree_holder.custom_minimum_size = Vector2(700, 420)
	tree_panel.add_child(tree_holder)
	
	# Lines layer (behind nodes) - uses custom drawing
	_lines_control = Control.new()
	_lines_control.name = "Lines"
	_lines_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_control.set_script(preload("res://scripts/ui/TalentTreeLines.gd"))
	# Set meta AFTER script is applied to ensure it's not cleared
	_lines_control.set_meta("tree_ref", self)
	_lines_control.set_meta("char_id", char_id)
	tree_holder.add_child(_lines_control)
	
	# Create talent nodes in a grid
	var talents: Array = TALENT_DATA[char_id]
	var node_width: float = 180.0
	var node_height: float = 90.0
	var h_spacing: float = 230.0
	var v_spacing: float = 155.0  # Increased from 105 to fill tree_holder height better
	var grid_width: float = 3.0 * h_spacing
	var start_x: float = (700.0 - grid_width) / 2.0 + (h_spacing - node_width) / 2.0
	
	for talent in talents:
		var col: int = talent["col"]
		var row: int = talent["row"]
		var node := _create_talent_button(talent, char_id)
		node.position = Vector2(start_x + col * h_spacing, row * v_spacing + 5)
		node.size = Vector2(node_width, node_height)
		tree_holder.add_child(node)
		_talent_buttons.append(node)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_panel.add_child(spacer)
	
	# Back button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_panel.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.text = "← BACK"
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.custom_minimum_size = Vector2(160, 50)
	back_btn.pressed.connect(_on_back_to_characters)
	_style_button(back_btn)
	btn_row.add_child(back_btn)

func _create_talent_button(talent: Dictionary, char_id: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.set_meta("talent", talent)
	btn.set_meta("char_id", char_id)
	btn.pressed.connect(_on_talent_clicked.bind(btn))
	btn.draw.connect(_draw_talent_button.bind(btn))
	btn.mouse_entered.connect(func(): 
		btn.set_meta("hovered", true)
		btn.queue_redraw()
		_show_tooltip(talent, btn)
	)
	btn.mouse_exited.connect(func(): 
		btn.set_meta("hovered", false)
		btn.queue_redraw()
		_hide_tooltip()
	)
	return btn

func _create_tooltip() -> void:
	# Create tooltip panel - NOT using anchors so it sizes to content
	_tooltip = PanelContainer.new()
	_tooltip.name = "Tooltip"
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 200  # Above everything
	_tooltip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tooltip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.02, 0.02, 0.04, 0.98)
	tooltip_style.border_color = Color(1.0, 0.85, 0.2, 1.0)  # Golden border
	tooltip_style.set_border_width_all(2)
	tooltip_style.set_corner_radius_all(8)
	tooltip_style.set_content_margin_all(12)
	tooltip_style.shadow_color = Color(0, 0, 0, 0.5)
	tooltip_style.shadow_size = 4
	_tooltip.add_theme_stylebox_override("panel", tooltip_style)
	
	var vbox := VBoxContainer.new()
	vbox.name = "TooltipVBox"
	vbox.add_theme_constant_override("separation", 6)
	_tooltip.add_child(vbox)
	
	# Title label
	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))  # Golden title
	vbox.add_child(title_label)
	
	# Short description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # White
	vbox.add_child(desc_label)
	
	# Separator
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)
	
	# Detailed tooltip text - use Label instead of RichTextLabel for proper sizing
	var tooltip_label := Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.custom_minimum_size = Vector2(250, 0)
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))  # Slightly dimmer white
	vbox.add_child(tooltip_label)
	
	add_child(_tooltip)

func _show_tooltip(talent: Dictionary, btn: Button) -> void:
	if _tooltip == null:
		return
	
	# Update tooltip content
	var title_label: Label = _tooltip.get_node_or_null("TooltipVBox/TitleLabel")
	var desc_label: Label = _tooltip.get_node_or_null("TooltipVBox/DescLabel")
	var tooltip_label: Label = _tooltip.get_node_or_null("TooltipVBox/TooltipLabel")
	
	if title_label:
		title_label.text = talent["name"]
	
	if desc_label:
		desc_label.text = talent["desc"]
	
	if tooltip_label:
		var full_description: String = talent.get("tooltip", "")
		tooltip_label.text = full_description
	
	# Reset size so it recalculates
	_tooltip.size = Vector2.ZERO
	
	# Position tooltip near the button
	var btn_global_pos := btn.global_position
	var btn_size := btn.size
	
	# Make visible first
	_tooltip.visible = true
	
	# Position to the right of the button by default
	var tooltip_pos := Vector2(btn_global_pos.x + btn_size.x + 10, btn_global_pos.y)
	
	# Wait one frame for size to update
	await get_tree().process_frame
	
	var tooltip_size := _tooltip.size
	var viewport_size := get_viewport_rect().size
	
	# If tooltip would go off the right edge, position it to the left of the button
	if tooltip_pos.x + tooltip_size.x > viewport_size.x - 20:
		tooltip_pos.x = btn_global_pos.x - tooltip_size.x - 10
	
	# If tooltip would go off the bottom edge, move it up
	if tooltip_pos.y + tooltip_size.y > viewport_size.y - 20:
		tooltip_pos.y = viewport_size.y - tooltip_size.y - 20
	
	# Make sure it doesn't go off the top
	if tooltip_pos.y < 20:
		tooltip_pos.y = 20
	
	_tooltip.global_position = tooltip_pos

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

func _draw_talent_button(btn: Button) -> void:
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")
	var hovered: bool = btn.get_meta("hovered", false)
	
	var talent_id: String = talent["id"]
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent_id, 0)
	var max_level: int = talent["max"]
	var is_unlocked := current_level > 0
	var is_maxed := current_level >= max_level
	var can_unlock := _can_unlock_talent(char_id, talent)
	
	# Colors - default for regular talents
	var bg_color := Color(0.08, 0.08, 0.1, 1.0)  # Dark gray when locked
	var border_color := UI.TALENT_LOCKED
	
	# Determine talent type
	var is_special: bool = talent.get("special", false)
	var is_burst: bool = talent.get("burst", false)
	var is_unlock: bool = talent.get("unlock", false)
	
	# Set colors based on state and type
	if is_burst:
		# Red/Crimson for burst
		if is_maxed:
			bg_color = Color(0.6, 0.15, 0.15, 1.0)  # Bright red
			border_color = Color(1.0, 0.4, 0.4, 1.0)
		elif is_unlocked:
			bg_color = Color(0.45, 0.1, 0.1, 1.0)  # Medium red
			border_color = Color(0.9, 0.3, 0.3, 1.0)
		else:
			bg_color = Color(0.15, 0.05, 0.05, 1.0)  # Dark red
	elif is_special:
		# Yellow/Gold for special
		if is_maxed:
			bg_color = Color(0.5, 0.4, 0.1, 1.0)  # Bright gold
			border_color = Color(1.0, 0.85, 0.3, 1.0)
		elif is_unlocked:
			bg_color = Color(0.4, 0.3, 0.08, 1.0)  # Medium gold
			border_color = Color(0.9, 0.75, 0.25, 1.0)
		else:
			bg_color = Color(0.12, 0.1, 0.03, 1.0)  # Dark gold
	elif is_unlock:
		# White/Silver for character unlock
		if is_maxed:
			bg_color = Color(0.35, 0.35, 0.4, 1.0)  # Bright silver
			border_color = Color(0.9, 0.9, 1.0, 1.0)
		elif is_unlocked:
			bg_color = Color(0.25, 0.25, 0.3, 1.0)  # Medium silver
			border_color = Color(0.8, 0.8, 0.9, 1.0)
		else:
			bg_color = Color(0.1, 0.1, 0.12, 1.0)  # Dark
	else:
		# Green for regular upgrades
		if is_maxed:
			bg_color = Color(0.15, 0.4, 0.15, 1.0)  # Bright green
			border_color = UI.TALENT_UNLOCKED
		elif is_unlocked:
			bg_color = Color(0.1, 0.25, 0.1, 1.0)  # Medium green
			border_color = Color(0.6, 0.8, 0.3, 1.0)
		elif can_unlock:
			border_color = UI.TALENT_HOVER_BORDER if hovered else border_color
			if hovered:
				bg_color = Color(0.12, 0.12, 0.15, 1.0)
	
	# Draw background
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	btn.draw_style_box(style, Rect2(Vector2.ZERO, btn.size))
	
	# Text
	var font := btn.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	
	var name_text: String = talent["name"]
	var name_color := UI.TEXT_PRIMARY if (is_unlocked or can_unlock) else UI.TALENT_LOCKED
	var name_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var name_x := (btn.size.x - name_size.x) / 2.0
	btn.draw_string(font, Vector2(name_x, 32), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)
	
	# Level
	var level_text := "%d / %d" % [current_level, max_level]
	var level_color := UI.TALENT_UNLOCKED if is_maxed else (UI.TEXT_SECONDARY if is_unlocked else UI.TALENT_LOCKED)
	var level_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var level_x := (btn.size.x - level_size.x) / 2.0
	btn.draw_string(font, Vector2(level_x, 56), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, level_color)
	
	# Cost
	if not is_maxed and can_unlock:
		var cost_text := "Cost: %d" % talent["cost"]
		var cost_size := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var cost_x := (btn.size.x - cost_size.x) / 2.0
		btn.draw_string(font, Vector2(cost_x, 78), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TALENT_HOVER_BORDER)

func _can_unlock_talent(char_id: int, talent: Dictionary) -> bool:
	var talent_id: String = talent["id"]
	
	print("[TalentTree] Checking can unlock: char=%d, talent=%s" % [char_id, talent_id])
	print("[TalentTree] Skill points: %d, cost: %d" % [_skill_points, talent["cost"]])
	
	if _skill_points < talent["cost"]:
		print("[TalentTree] BLOCKED: Not enough skill points")
		return false
	
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent_id, 0)
	print("[TalentTree] Current level: %d, max: %d" % [current_level, talent["max"]])
	if current_level >= talent["max"]:
		print("[TalentTree] BLOCKED: Already at max level")
		return false
	
	var requires: Array = talent.get("requires", [])
	print("[TalentTree] Requires: %s" % [requires])
	print("[TalentTree] Unlocked talents for char %d: %s" % [char_id, _unlocked_talents.get(char_id, {})])
	for req_id in requires:
		var req_level: int = _unlocked_talents.get(char_id, {}).get(req_id, 0)
		print("[TalentTree] Requirement '%s' level: %d" % [req_id, req_level])
		if req_level <= 0:
			print("[TalentTree] BLOCKED: Missing requirement '%s'" % req_id)
			return false
	
	print("[TalentTree] CAN UNLOCK!")
	return true

func _on_talent_clicked(btn: Button) -> void:
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")
	
	print("[TalentTree] CLICK on talent: char=%d, id=%s" % [char_id, talent["id"]])
	
	if not _can_unlock_talent(char_id, talent):
		print("[TalentTree] Cannot unlock - blocked")
		return
	
	var talent_id: String = talent["id"]
	if not _unlocked_talents.has(char_id):
		_unlocked_talents[char_id] = {}
	
	var current_level: int = _unlocked_talents[char_id].get(talent_id, 0)
	_unlocked_talents[char_id][talent_id] = current_level + 1
	_skill_points -= talent["cost"]
	
	# Play confirm sound for successful purchase
	UISounds.play_confirm()
	
	print("[TalentTree] UNLOCKED %s! New state: %s" % [talent_id, _unlocked_talents[char_id]])
	
	# Track skill purchase for achievement
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").on_skill_purchased(char_id, talent_id)
	
	emit_signal("talent_unlocked", char_id, talent_id)
	
	# Refresh the tree UI to show updated state
	_refresh_tree()
	
	# Only close if no skill points remaining - with delay for player to prepare
	if _skill_points <= 0:
		_on_close(true)  # true = with delay before unpause

func _refresh_tree() -> void:
	var points := _tree_panel.get_node_or_null("TreeSkillPoints")
	if points:
		points.text = "   AVAILABLE SKILL POINTS: %d   " % _skill_points
	
	for btn in _talent_buttons:
		if is_instance_valid(btn):
			btn.queue_redraw()
	
	# Redraw lines
	if _lines_control:
		_lines_control.queue_redraw()
	
	# Update stats (talents may modify player stats)
	_update_stats_panel()

func _on_back_to_characters() -> void:
	UISounds.play_back()
	_tree_panel.visible = false
	_character_panel.visible = true
	_current_character = -1
	_refresh_character_cards()

func _refresh_character_cards() -> void:
	# cards_row is child index 2: [PointsContainer(0), spacer1(1), cards_row(2), spacer2(3), btn_row(4)]
	var cards_row := _character_panel.get_child(2) if _character_panel.get_child_count() > 2 else null
	if not cards_row:
		return
	
	for i in range(cards_row.get_child_count()):
		var char_id: int = _shop_character_order[i] if i < _shop_character_order.size() else i
		var card: PanelContainer = cards_row.get_child(i)
		# Structure: card -> main_container -> [clip_container, name_bar, bottom_bar]
		# bottom_bar -> bottom_vbox -> [btn_margin, count_label, status_label, spacer]
		var main_container := card.get_child(0) if card.get_child_count() > 0 else null
		if main_container and main_container.get_child_count() >= 3:
			var bottom_bar := main_container.get_child(2)  # Third child is bottom_bar overlay
			if bottom_bar and bottom_bar.get_child_count() > 0:
				var bottom_vbox := bottom_bar.get_child(0)
				if bottom_vbox:
					var count_label := bottom_vbox.get_node_or_null("CountLabel")
					if count_label:
						_update_card_count(count_label, char_id)
					var status_label := bottom_vbox.get_node_or_null("StatusLabel")
					if status_label:
						_update_card_status(status_label, char_id)
	
	var points_container := _character_panel.get_node_or_null("PointsContainer")
	if points_container:
		var char_points := points_container.get_node_or_null("SkillPoints")
		if char_points:
			char_points.text = "   AVAILABLE SKILL POINTS: %d   " % _skill_points

func _on_close(with_delay: bool = false) -> void:
	UISounds.play_back()
	# Start close animation
	_anim_state = 3
	_anim_progress = 0.0
	_anim_time = 0.0
	_pending_unpause = with_delay
	_hovered_character = -1
	
	# Position scanline overlay over main panel
	if _scanline_overlay and _main_panel:
		_scanline_overlay.global_position = _main_panel.global_position
		_scanline_overlay.size = _main_panel.size
		_scanline_overlay.visible = true
		_scanline_overlay.queue_redraw()

func _on_card_mouse_entered(char_id: int, card: PanelContainer) -> void:
	# Get actual character id from shop order (char_id is already the correct index)
	_hovered_character = char_id
	_last_hovered_character = char_id  # Remember for sticky display
	_update_stats_panel(char_id)
	
	# Hover animation - scale up slightly
	var tween := create_tween()
	tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Update border to glow
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	style.border_color = UI.TALENT_HOVER_BORDER
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(4)  # Keep content margin for border visibility
	card.add_theme_stylebox_override("panel", style)

func _on_card_mouse_exited(card: PanelContainer) -> void:
	_hovered_character = -1
	_update_stats_panel(-1)  # Show last hovered or main character stats
	
	# Hover animation - scale back to normal
	var tween := create_tween()
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Reset border
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	style.border_color = Color(1.0, 1.0, 1.0, 1.0)  # Pure white stroke
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(4)  # Keep content margin for border visibility
	card.add_theme_stylebox_override("panel", style)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel"):
		if _tree_panel.visible:
			_on_back_to_characters()
		else:
			_on_close()
		get_viewport().set_input_as_handled()

# Public API
func show_tree(player: Node = null) -> void:
	if player != null:
		_player_ref = player
	else:
		# Try to find player automatically
		_player_ref = get_tree().get_first_node_in_group("player")
		if _player_ref == null:
			_player_ref = get_node_or_null("/root/Level/Player")
	
	# Start open animation
	visible = true
	modulate.a = 0.0
	_anim_state = 1
	_anim_progress = 0.0
	_anim_time = 0.0
	
	# Pause the game (and timers)
	get_tree().paused = true
	_pending_unpause = true
	
	# Position scanline overlay over main panel after a frame so layout is computed
	if _scanline_overlay and _main_panel:
		await get_tree().process_frame
		_scanline_overlay.global_position = _main_panel.global_position
		_scanline_overlay.size = _main_panel.size
		_scanline_overlay.visible = true
		_scanline_overlay.queue_redraw()
	
	_character_panel.visible = true
	_tree_panel.visible = false
	_refresh_character_cards()
	_update_stats_panel()

func add_skill_points(amount: int) -> void:
	_skill_points += amount
	_refresh_character_cards()

func get_skill_points() -> int:
	return _skill_points

func get_talent_level(char_id: int, talent_id: String) -> int:
	return _unlocked_talents.get(char_id, {}).get(talent_id, 0)

func is_talent_unlocked(char_id: int, talent_id: String) -> bool:
	return get_talent_level(char_id, talent_id) > 0

func get_unlocked_talents() -> Dictionary:
	return _unlocked_talents.duplicate(true)

func set_unlocked_talents(data: Dictionary) -> void:
	_unlocked_talents = data.duplicate(true)

# Helper methods for TalentTreeLines drawing
func get_talent_data(char_id: int) -> Array:
	return TALENT_DATA.get(char_id, [])

func get_unlocked_for_char(char_id: int) -> Dictionary:
	return _unlocked_talents.get(char_id, {})

func _apply_default_talents() -> void:
	# Auto-unlock only the MAIN character from GameState (slot 0)
	# Support characters (slots 1 and 2) must be unlocked by spending skill points
	if not _game_state:
		return
	
	var selected: Array[int] = _game_state.selected_character_indices.duplicate()
	if selected.size() == 0:
		return
	
	var main_char_idx: int = selected[0]  # Only unlock main character
	
	# Apply 'default': true talents ONLY to the main character
	if TALENT_DATA.has(main_char_idx):
		var talents: Array = TALENT_DATA[main_char_idx]
		for talent in talents:
			if talent.get("default", false):
				if not _unlocked_talents.has(main_char_idx):
					_unlocked_talents[main_char_idx] = {}
				var talent_id: String = talent["id"]
				if not _unlocked_talents[main_char_idx].has(talent_id):
					_unlocked_talents[main_char_idx][talent_id] = 1
	
	# Ensure the "unlock" talent is applied for main character
	if TALENT_DATA.has(main_char_idx):
		if not _unlocked_talents.has(main_char_idx):
			_unlocked_talents[main_char_idx] = {}
		if not _unlocked_talents[main_char_idx].has("unlock"):
			_unlocked_talents[main_char_idx]["unlock"] = 1
			print("[TalentTree] Auto-unlocked main character %d" % main_char_idx)

func set_skill_points(amount: int) -> void:
	_skill_points = amount
	
	# Update UI if valid
	if _character_panel:
		var points_container = _character_panel.get_node_or_null("PointsContainer")
		if points_container:
			var points_label = points_container.get_node_or_null("SkillPoints")
			if points_label:
				points_label.text = "   AVAILABLE SKILL POINTS: %d   " % _skill_points
