extends CharacterBody2D

@onready var hp_bar = $ProgressBar

var hp = 1
var max_hp = 1
var speed = 100
var player

# Knockback system - uses velocity-based physics with decay
var knockback_velocity := Vector2.ZERO
const KNOCKBACK_FORCE := 600.0        # Initial knockback speed
const KNOCKBACK_DECAY := 8.0          # How fast knockback slows down (higher = faster decay)
const CONTACT_RADIUS := 50.0          # Distance to trigger damage
const ATTACK_COOLDOWN := 1.0          # Seconds between attacks
const SEPARATION_RADIUS := 40.0       # Hard separation distance
const SEPARATION_FORCE := 300.0       # Force to push apart when overlapping

var attack_cooldown_timer := 0.0

func _ready():
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	player = get_parent().get_node("Player")

func _physics_process(delta: float) -> void:
	if not player:
		return
	
	# Update attack cooldown
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	var dir_to_player: Vector2 = to_player.normalized() if distance > 0 else Vector2.ZERO
	
	# === KNOCKBACK PHYSICS ===
	# Decay knockback over time (exponential decay feels natural)
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_velocity.length() * KNOCKBACK_DECAY * delta)
	
	# === SEPARATION (prevents overlapping) ===
	var separation: Vector2 = Vector2.ZERO
	if distance < SEPARATION_RADIUS and distance > 0:
		# Strong push when too close - scales inversely with distance
		var overlap_factor: float = 1.0 - (distance / SEPARATION_RADIUS)
		separation = -dir_to_player * SEPARATION_FORCE * overlap_factor
	
	# === CHASE MOVEMENT ===
	var chase_velocity: Vector2 = Vector2.ZERO
	if knockback_velocity.length() < 50:  # Only chase when knockback is mostly done
		chase_velocity = dir_to_player * speed
	
	# === COMBINE VELOCITIES ===
	# Knockback takes priority, then separation, then chase
	velocity = knockback_velocity + separation + chase_velocity
	
	move_and_slide()
	
	# === CONTACT DAMAGE ===
	if distance < CONTACT_RADIUS and attack_cooldown_timer <= 0:
		_deal_contact_damage()

func _deal_contact_damage() -> void:
	if not player:
		return
	
	# Deal damage
	player.take_damage(1)
	attack_cooldown_timer = ATTACK_COOLDOWN
	
	# Apply knockback - away from player with slight randomness
	var away_dir: Vector2 = (global_position - player.global_position).normalized()
	if away_dir == Vector2.ZERO:
		away_dir = Vector2.RIGHT.rotated(randf() * TAU)
	away_dir = away_dir.rotated(randf_range(-0.2, 0.2))  # Slight spread
	
	knockback_velocity = away_dir * KNOCKBACK_FORCE
	
	# Instant separation to prevent sticking
	global_position += away_dir * 20.0

func apply_knockback(direction: Vector2, force: float = KNOCKBACK_FORCE) -> void:
	"""External knockback (from player attacks, etc.)"""
	knockback_velocity = direction.normalized() * force

func take_damage(dmg):
	hp -= dmg
	hp_bar.value = hp
	if hp <= 0:
		call_deferred("die")

func die():
	# spawn XP orbs
	for i in 5:
		var orb_scene = preload("res://scenes/effects/XPOrb.tscn")
		var orb = orb_scene.instantiate()
		get_parent().add_child(orb)
		orb.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	call_deferred("queue_free")