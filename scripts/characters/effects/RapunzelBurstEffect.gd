extends Node2D
class_name RapunzelBurstEffect

## Rapunzel's burst: Stuns all enemies and heals the player for 75% of max HP
## Creates a warm golden healing aura effect
## With talents: 8s stun duration, 8s invincibility

@export var duration: float = 0.65
@export var stun_duration: float = 4.0
@export var heal_percent: float = 1.0
@export var flash_radius: float = 320.0
@export var flash_color: Color = Color(1.0, 0.94, 0.72, 0.92)
@export var glow_color: Color = Color(1.0, 0.85, 0.5, 0.6)
@export var heal_ring_color: Color = Color(0.4, 1.0, 0.5, 0.7)

var owner_node: Node2D = null

# Talent bonuses
var grant_invuln: bool = false  # Divine Protection talent
var invuln_duration: float = 8.0

var _age: float = 0.0
var _has_executed: bool = false

func _ready() -> void:
	set_process(true)
	z_index = 500
	queue_redraw()
	
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 500

func _process(delta: float) -> void:
	_age += delta
	
	# Execute the heal/stun effect on first frame
	if not _has_executed:
		_has_executed = true
		_execute_burst()
	
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _execute_burst() -> void:
	if owner_node == null:
		return
	
	# Heal the player
	if owner_node.has_method("heal"):
		var max_hp = owner_node.max_hp if "max_hp" in owner_node else 100
		var heal_amount := int(float(max_hp) * heal_percent)
		owner_node.heal(heal_amount)
	elif "hp" in owner_node and "max_hp" in owner_node:
		var heal_amount := int(float(owner_node.max_hp) * heal_percent)
		owner_node.hp = mini(owner_node.hp + heal_amount, owner_node.max_hp)
		# Update HP bar if exists
		if "hp_bar" in owner_node and owner_node.hp_bar:
			owner_node.hp_bar.value = owner_node.hp
		# Update HUD if exists
		if "player_hud" in owner_node and owner_node.player_hud:
			owner_node.player_hud.update_health(owner_node.hp, owner_node.max_hp, heal_amount, true)
	
	# Grant invincibility if Divine Protection talent is unlocked
	if grant_invuln and owner_node:
		if "invincible" in owner_node:
			owner_node.invincible = true
		# Create a timer to remove invincibility after duration
		var invuln_timer := Timer.new()
		invuln_timer.wait_time = invuln_duration
		invuln_timer.one_shot = true
		invuln_timer.autostart = true
		var player_ref := owner_node
		invuln_timer.timeout.connect(func():
			if is_instance_valid(player_ref) and "invincible" in player_ref:
				player_ref.invincible = false
			invuln_timer.queue_free()
		)
		owner_node.add_child(invuln_timer)
	
	# Stun all enemies
	if not get_tree():
		return
	
	for node in TargetCache.get_enemies():
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
		
		var enemy := node as Node2D
		
		# Apply stun effect
		if enemy.has_method("apply_stun"):
			enemy.apply_stun(stun_duration)
		
		# Register burst hit
		if owner_node and owner_node.has_method("register_burst_hit"):
			owner_node.register_burst_hit(enemy, true)  # from_burst = true

func _draw() -> void:
	if duration <= 0.0:
		return
	
	var progress := clampf(_age / max(duration, 0.0001), 0.0, 1.0)
	var alpha := _get_alpha(progress)
	
	if alpha <= 0.01:
		return
	
	# Draw expanding glow
	var glow_scale := 1.0 + progress * 0.5
	var glow_alpha := alpha * 0.5
	var glow := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * glow_alpha)
	draw_circle(Vector2.ZERO, flash_radius * glow_scale, glow)
	
	# Draw main flash
	var main_color := Color(flash_color.r, flash_color.g, flash_color.b, flash_color.a * alpha)
	draw_circle(Vector2.ZERO, flash_radius * (1.0 - progress * 0.2), main_color)
	
	# Draw inner bright core
	var core_alpha := alpha * (1.0 - progress)
	var core_color := Color(1.0, 1.0, 0.95, core_alpha * 0.9)
	draw_circle(Vector2.ZERO, flash_radius * 0.4 * (1.0 - progress * 0.3), core_color)
	
	# Draw healing ring particles
	_draw_heal_particles(progress, alpha)

func _draw_heal_particles(progress: float, alpha: float) -> void:
	var particle_count := 12
	var ring_radius := flash_radius * (0.5 + progress * 0.4)
	
	for i in range(particle_count):
		var angle := (float(i) / float(particle_count)) * TAU + progress * TAU * 0.5
		var offset := Vector2(cos(angle), sin(angle)) * ring_radius
		
		# Rising particle effect
		offset.y -= progress * 60.0
		
		var particle_alpha := alpha * (1.0 - progress * 0.5)
		var particle_color := Color(heal_ring_color.r, heal_ring_color.g, heal_ring_color.b, heal_ring_color.a * particle_alpha)
		var particle_size := 8.0 + sin(progress * PI) * 4.0
		
		draw_circle(offset, particle_size, particle_color)

func _get_alpha(progress: float) -> float:
	if progress < 0.15:
		return lerpf(0.0, 1.0, progress / 0.15)
	if progress < 0.5:
		return 1.0
	return lerpf(1.0, 0.0, (progress - 0.5) / 0.5)
