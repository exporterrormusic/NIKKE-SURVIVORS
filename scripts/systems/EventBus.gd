extends Node
## Global event bus for decoupled communication between game systems.
##
## Usage:
##   # Emit an event
##   EventBus.enemy_killed.emit(enemy, "player")
##
##   # Listen to an event
##   EventBus.enemy_killed.connect(_on_enemy_killed)
##
## This decouples systems that need to react to game events from the
## systems that generate those events. For example:
## - Score system listens to enemy_killed
## - Achievement system listens to enemy_killed
## - XP system listens to enemy_killed
## Without needing to know about each other.

# =============================================================================
# COMBAT EVENTS
# =============================================================================

## Emitted when an enemy is killed
## @param enemy: The enemy node that died
## @param killer_source: String identifying what killed it ("player", "projectile", "summon", etc.)
signal enemy_killed(enemy: Node, killer_source: String)

## Emitted when the player takes damage
## @param amount: Damage amount
## @param source: Optional source of damage
signal player_damaged(amount: int, source: Node)

## Emitted when the player is healed
## @param amount: Heal amount
signal player_healed(amount: int)

## Emitted when any entity takes damage (for combat juice, etc.)
## @param target: The entity that took damage
## @param info: DamageInfo with full damage details
signal damage_dealt(target: Node, info: DamageInfo)

## Emitted when a critical hit occurs
## @param target: Entity that received the crit
## @param damage: Crit damage amount
signal critical_hit(target: Node, damage: int)

# =============================================================================
# PROGRESSION EVENTS
# =============================================================================

## Emitted when the player gains XP
## @param amount: XP gained
## @param new_total: New total XP
signal xp_gained(amount: int, new_total: int)

## Emitted when the player levels up
## @param new_level: The new level
signal player_leveled_up(new_level: int)

## Emitted when a skill point is spent
## @param character_id: Which character the skill was for
## @param skill_id: Which skill was upgraded
signal skill_unlocked(character_id: int, skill_id: String)

## Emitted when burst ability is activated
## @param character_id: Which character activated burst
signal burst_activated(character_id: int)

## Emitted when burst gauge is full and ready
signal burst_ready

# =============================================================================
# WAVE/GAME FLOW EVENTS
# =============================================================================

## Emitted when a run starts on a specific map
## @param map_id: The ID of the map being played
signal run_started(map_id: String)

## Emitted when a run ends (win or lose)
## @param is_win: True if the run was won
## @param map_id: The ID of the map played
## @param duration: Run duration in seconds
signal run_completed(is_win: bool, map_id: String, duration: float)

## Emitted when a new wave starts
## @param wave_number: The wave number starting
signal wave_started(wave_number: int)

## Emitted when a wave is completed
## @param wave_number: The wave that was completed
signal wave_completed(wave_number: int)

## Emitted when a boss spawns
## @param boss: The boss enemy node
signal boss_spawned(boss: Node)

## Emitted when a boss is defeated
## @param boss: The boss that was defeated
signal boss_defeated(boss: Node)

## Emitted when game is paused/unpaused
## @param is_paused: True if game is now paused
signal game_paused(is_paused: bool)

# =============================================================================
# CHARACTER EVENTS
# =============================================================================

## Emitted when the active character changes
## @param slot_index: The new active character slot (0, 1, 2)
## @param character_id: Registry ID of the character
signal character_switched(slot_index: int, character_id: int)

## Emitted when a character is unlocked during gameplay
## @param slot_index: Which slot was unlocked
signal character_unlocked(slot_index: int)

# =============================================================================
# ENVIRONMENT EVENTS
# =============================================================================

## Emitted when time of day changes
## @param is_night: True if it's now night time
signal time_of_day_changed(is_night: bool)

## Emitted when ambient light modulate changes
## @param color: New modulate color
signal modulate_changed(color: Color)

## Emitted when biome changes
## @param biome_id: ID of the new biome
signal biome_changed(biome_id: StringName)

# =============================================================================
# PICKUP EVENTS
# =============================================================================

## Emitted when player picks up an XP orb
## @param value: XP value of the orb
signal xp_orb_collected(value: int)

## Emitted when player picks up a Pristine Core
## @param value: Number of cores
signal pristine_core_collected(value: int)

## Emitted when player picks up a health pickup
## @param amount: Health restored
signal health_pickup_collected(amount: int)

# =============================================================================
# UI EVENTS
# =============================================================================

## Emitted when a menu is opened
## @param menu_name: Name of the menu
signal menu_opened(menu_name: String)

## Emitted when a menu is closed
## @param menu_name: Name of the menu
signal menu_closed(menu_name: String)

## Emitted when shop purchase is made
## @param upgrade_id: ID of purchased upgrade
## @param cost: Cost paid
signal shop_purchase(upgrade_id: String, cost: int)
