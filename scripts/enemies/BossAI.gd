extends Node
class_name BossAI

## Manages boss special attacks: tracking missiles and beam attack

# Attack timing - base values (adjusted per enemy type)
const MISSILE_COOLDOWN_BOSS := 10.0   # Bosses fire every 10s
const MISSILE_COOLDOWN_ELITE := 20.0  # Elites fire half as often (every 20s)
const MISSILE_COOLDOWN_TANK := 30.0   # Tanks fire rarely (every 30s)
const BEAM_COOLDOWN := 12.0           # Seconds between beam attacks
const ATTACK_START_DELAY := 3.0       # Delay before boss starts attacking

# Missile settings - adjusted per enemy type
const MISSILES_BOSS := 4      # Bosses fire 4 missiles (2 per side)
const MISSILES_ELITE := 1     # Elites fire 1 missile
const MISSILES_TANK := 1      # Tanks fire 1 missile
const MISSILE_SPAWN_OFFSET := 30.0  # Distance from boss to spawn missiles (close to body)

# Beam settings
const BEAM_CHARGE_TIME := 2.0
const BEAM_FIRE_TIME := 2.0
const BEAM_FADE_TIME := 0.5

# State
var _boss: CharacterBody2D = null
var _player: Node2D = null
var _missile_timer := 0.0
var _beam_timer := BEAM_COOLDOWN
var _initial_delay := ATTACK_START_DELAY
var _beam_active := false
var _current_beam: Node2D = null

# Enemy type tracking
var _is_tank := false
var _is_elite := false
var _is_boss := false
var _missile_cooldown := MISSILE_COOLDOWN_BOSS
var _missiles_per_barrage := MISSILES_BOSS

# Preload scenes
const BossMissileScene = preload("res://scripts/enemies/BossMissile.gd")
const BossBeamScene = preload("res://scripts/enemies/BossBeam.gd")

func _ready() -> void:
	# Get reference to parent boss
	_boss = get_parent() as CharacterBody2D
	if not _boss:
		push_warning("[BossAI] Parent is not a CharacterBody2D")
		return
	
	# Determine enemy type and adjust settings
	_is_tank = _boss.has_meta("tank_mode") or _boss.is_in_group("tank")
	_is_elite = _boss.has_meta("elite_enhanced") or _boss.is_in_group("elite")
	_is_boss = _boss.is_in_group("boss") and not _is_tank and not _is_elite
	
	# Safety check: Tanks should only have BossAI in Goddess Fall mode
	# If somehow a tank got BossAI in normal mode, disable missile firing
	if _is_tank and not GameState.goddess_fall_mode:
		push_warning("[BossAI] Tank has BossAI but not in Goddess Fall mode - disabling")
		queue_free()
		return
	
	if _is_tank:
		_missile_cooldown = MISSILE_COOLDOWN_TANK
		_missiles_per_barrage = MISSILES_TANK
	elif _is_elite:
		_missile_cooldown = MISSILE_COOLDOWN_ELITE
		_missiles_per_barrage = MISSILES_ELITE
	else:
		# Default to boss behavior
		_is_boss = true
		_missile_cooldown = MISSILE_COOLDOWN_BOSS
		_missiles_per_barrage = MISSILES_BOSS
	
	# Start with half cooldown
	_missile_timer = _missile_cooldown / 2.0
	
	# Goddess Fall: 30% faster attack rates
	if GameState.goddess_fall_mode:
		_missile_cooldown *= 0.7
	
	# Goddess Fall: 30% faster charge times (beam)
	var _beam_charge_time := BEAM_CHARGE_TIME
	if GameState.goddess_fall_mode:
		_beam_charge_time = BEAM_CHARGE_TIME * 0.7
	set_meta("beam_charge_time", _beam_charge_time)
	
	# Find player
	_player = get_tree().get_first_node_in_group("player")
	
	print("[BossAI] Initialized - tank=%s, elite=%s, boss=%s, missiles=%d, cooldown=%.1fs" % [_is_tank, _is_elite, _is_boss, _missiles_per_barrage, _missile_cooldown])

func _process(delta: float) -> void:
	if not _boss or not is_instance_valid(_boss):
		return
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	
	# Initial delay before attacking
	if _initial_delay > 0:
		_initial_delay -= delta
		return
	
	# Don't process other attacks while beam is active
	if _beam_active:
		return
	
	# Update timers
	_missile_timer -= delta
	_beam_timer -= delta
	
	# Fire missiles
	if _missile_timer <= 0:
		_fire_missile_barrage()
		_missile_timer = _missile_cooldown
	
	# Fire beam (only true bosses fire beams, not tanks or elites)
	if _beam_timer <= 0 and _is_boss:
		_fire_beam()
		_beam_timer = BEAM_COOLDOWN

func _fire_missile_barrage() -> void:
	if not _boss or not _player:
		return
	
	# Get direction to player for spawning
	var to_player := (_player.global_position - _boss.global_position).normalized()
	var perpendicular := Vector2(-to_player.y, to_player.x)  # 90 degree rotation
	
	# Set total missiles for this barrage
	_total_missiles_in_volley = _missiles_per_barrage
	_missile_index = 0
	
	if _missiles_per_barrage == 1:
		# Single missile - spawn at boss position
		var spawn_pos := _boss.global_position + to_player * MISSILE_SPAWN_OFFSET * _boss.scale.x
		_spawn_missile(spawn_pos, 0.0)
	else:
		# Multiple missiles - spawn on both sides (2 per side for bosses = 4 total)
		var missiles_per_side: int = _missiles_per_barrage / 2
		for side in [-1, 1]:
			var side_offset: Vector2 = perpendicular * float(side) * MISSILE_SPAWN_OFFSET * _boss.scale.x
			
			for i in range(missiles_per_side):
				# Stagger spawn positions along the side
				var height_offset: Vector2 = to_player * (i - missiles_per_side / 2.0) * 50.0 * _boss.scale.x
				var spawn_pos := _boss.global_position + side_offset + height_offset
				
				# Create missile with staggered launch
				_spawn_missile(spawn_pos, i * 0.15)

var _missile_index := 0
var _total_missiles_in_volley := 0

func _spawn_missile(spawn_pos: Vector2, delay: float) -> void:
	# Create missile node
	var missile := Node2D.new()
	missile.set_script(BossMissileScene)
	missile.name = "BossMissile"
	missile.global_position = spawn_pos
	
	# Initialize with player reference, delay, and spread index
	if missile.has_method("initialize"):
		var damage: int = _boss.base_damage if "base_damage" in _boss else 1
		missile.initialize(_player, delay, _missile_index, _total_missiles_in_volley, damage)
	_missile_index += 1
	
	# Add to scene (same level as boss)
	if _boss.get_parent():
		_boss.get_parent().add_child(missile)

func _fire_beam() -> void:
	if not _boss or not _player:
		return
	
	_beam_active = true
	
	# Create beam node
	_current_beam = Node2D.new()
	_current_beam.set_script(BossBeamScene)
	_current_beam.name = "BossBeam"
	
	# Check if this is a true boss (not an elite)
	var is_true_boss: bool = _boss.has_meta("enemy_tier") and _boss.get_meta("enemy_tier") == "boss"
	
	# Get charge time (reduced by 30% in Goddess Fall)
	var charge_time: float = get_meta("beam_charge_time") if has_meta("beam_charge_time") else BEAM_CHARGE_TIME
	
	# Initialize beam with boss reference and timing
	if _current_beam.has_method("initialize"):
		var damage: int = _boss.base_damage if "base_damage" in _boss else 1
		
		# Only N01 / Rapture Queen does oil burn
		var enable_oil_burn: bool = false
		if "N01" in _boss.name or "Queen" in _boss.name or "RaptureQueen" in _boss.name or (_boss.scene_file_path and "RaptureQueen" in _boss.scene_file_path):
			enable_oil_burn = true
			
		_current_beam.initialize(_boss, _player, charge_time, BEAM_FIRE_TIME, BEAM_FADE_TIME, is_true_boss, damage, enable_oil_burn)
	
	# Connect beam finished signal
	if _current_beam.has_signal("beam_finished"):
		_current_beam.beam_finished.connect(_on_beam_finished)
	
	# Add as child of boss so it follows
	_boss.add_child(_current_beam)

func _on_beam_finished() -> void:
	_beam_active = false
	_current_beam = null
