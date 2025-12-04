extends Node
class_name BossAI

## Manages boss special attacks: tracking missiles and beam attack

# Attack timing
const MISSILE_COOLDOWN := 8.0  # Seconds between missile barrages
const BEAM_COOLDOWN := 12.0    # Seconds between beam attacks
const ATTACK_START_DELAY := 3.0  # Delay before boss starts attacking

# Missile settings
const MISSILES_PER_SIDE := 4
const MISSILE_SPAWN_OFFSET := 100.0  # Distance from boss to spawn missiles

# Beam settings
const BEAM_CHARGE_TIME := 2.0
const BEAM_FIRE_TIME := 2.0
const BEAM_FADE_TIME := 0.5

# State
var _boss: CharacterBody2D = null
var _player: Node2D = null
var _missile_timer := MISSILE_COOLDOWN / 2.0  # Start with half cooldown
var _beam_timer := BEAM_COOLDOWN
var _initial_delay := ATTACK_START_DELAY
var _beam_active := false
var _current_beam: Node2D = null

# Preload scenes
const BossMissileScene = preload("res://scripts/enemies/BossMissile.gd")
const BossBeamScene = preload("res://scripts/enemies/BossBeam.gd")

func _ready() -> void:
	# Get reference to parent boss
	_boss = get_parent() as CharacterBody2D
	if not _boss:
		push_warning("[BossAI] Parent is not a CharacterBody2D")
		return
	
	# Find player
	_player = get_tree().get_first_node_in_group("player")
	
	print("[BossAI] Boss AI initialized")

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
		_missile_timer = MISSILE_COOLDOWN
	
	# Fire beam
	if _beam_timer <= 0:
		_fire_beam()
		_beam_timer = BEAM_COOLDOWN

func _fire_missile_barrage() -> void:
	if not _boss or not _player:
		return
	
	# Get direction to player for spawning on sides
	var to_player := (_player.global_position - _boss.global_position).normalized()
	var perpendicular := Vector2(-to_player.y, to_player.x)  # 90 degree rotation
	
	# Spawn missiles on both sides
	for side in [-1, 1]:
		var side_offset: Vector2 = perpendicular * float(side) * MISSILE_SPAWN_OFFSET * _boss.scale.x
		
		for i in range(MISSILES_PER_SIDE):
			# Stagger spawn positions along the side
			var height_offset: Vector2 = to_player * (i - MISSILES_PER_SIDE / 2.0) * 50.0 * _boss.scale.x
			var spawn_pos := _boss.global_position + side_offset + height_offset
			
			# Create missile
			_spawn_missile(spawn_pos, i * 0.15)  # Stagger launch times

func _spawn_missile(spawn_pos: Vector2, delay: float) -> void:
	# Create missile node
	var missile := Node2D.new()
	missile.set_script(BossMissileScene)
	missile.name = "BossMissile"
	missile.global_position = spawn_pos
	
	# Initialize with player reference and delay
	if missile.has_method("initialize"):
		missile.initialize(_player, delay)
	
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
	
	# Initialize beam with boss reference and timing
	if _current_beam.has_method("initialize"):
		_current_beam.initialize(_boss, _player, BEAM_CHARGE_TIME, BEAM_FIRE_TIME, BEAM_FADE_TIME, is_true_boss)
	
	# Connect beam finished signal
	if _current_beam.has_signal("beam_finished"):
		_current_beam.beam_finished.connect(_on_beam_finished)
	
	# Add as child of boss so it follows
	_boss.add_child(_current_beam)

func _on_beam_finished() -> void:
	_beam_active = false
	_current_beam = null
