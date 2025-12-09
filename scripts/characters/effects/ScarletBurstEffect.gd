extends Node2D
class_name ScarletBurstEffect

## Scarlet's burst: Instantly kills all enemies on screen and teleports to one of them
## Creates a dramatic red flash effect
## With Execution talent: Instantly kills non-elite, non-boss enemies
## With Expose Weakness talent: Applies 50% damage taken debuff

@export var duration: float = 0.5
@export var flash_radius: float = 260.0
@export var flash_color: Color = Color(1.0, 0.78, 1.0, 0.85)
@export var enemy_flash_color: Color = Color(1.0, 0.78, 1.0, 0.85)
@export var enemy_flash_radius: float = 130.0

var owner_node: Node2D = null
var teleport_target: Vector2 = Vector2.ZERO
var should_teleport: bool = false

# Talent bonuses
var execute_talent: bool = false  # Instantly kill non-elite/boss enemies
var vuln_talent: bool = false  # Apply 50% damage taken debuff

var _age: float = 0.0
var _killed_positions: Array[Vector2] = []
var _has_executed: bool = false

signal burst_complete(teleport_position: Vector2)

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
	
	# Execute the kill effect on first frame
	if not _has_executed:
		_has_executed = true
		_execute_burst()
	
	if _age >= duration:
		# Emit signal with teleport position before freeing
		if should_teleport and teleport_target != Vector2.ZERO:
			emit_signal("burst_complete", teleport_target)
		queue_free()
		return
	queue_redraw()

func _execute_burst() -> void:
	if not get_tree():
		return
	
	# Get camera view rect if available
	var view_rect := _get_camera_view_rect()
	var filter_by_view := view_rect.size.x > 0.0 and view_rect.size.y > 0.0
	
	var execution_kill_count: int = 0  # Track kills for healing
	
	# Kill all enemies on screen
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
		
		var enemy := node as Node2D
		
		# Check if on screen (if we have view rect)
		if filter_by_view and not view_rect.has_point(enemy.global_position):
			continue
		
		var enemy_position := enemy.global_position
		
		# Check if this is an elite or boss (for execute talent)
		var is_elite_or_boss: bool = enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") in ["elite", "boss"]
		is_elite_or_boss = is_elite_or_boss or enemy.is_in_group("elite") or enemy.is_in_group("boss")
		
		# Determine damage amount
		var damage_amount: int = (owner_node.calc_damage() if owner_node and owner_node.has_method("calc_damage") else 0) * 10
		var will_execute := false
		if execute_talent and not is_elite_or_boss:
			# Execution talent: instant kill for non-elite/boss
			damage_amount = 999999
			will_execute = true
		
		# Apply vulnerability debuff if talent is active
		if vuln_talent:
			_apply_vulnerability(enemy)
		
		# Apply lethal damage with hit direction from player
		var hit_direction := (enemy_position - global_position).normalized()
		var dealt := false
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage_amount, false, hit_direction, true)  # from_burst = true
			dealt = true
		elif enemy.has_method("apply_damage"):
			enemy.apply_damage(damage_amount)
			dealt = true
		
		if dealt:
			_killed_positions.append(enemy_position)
			# Count execution kills for healing
			if will_execute:
				execution_kill_count += 1
			# Register burst hit
			if owner_node and owner_node.has_method("register_burst_hit"):
				owner_node.register_burst_hit(enemy, true)  # from_burst = true
	
	# Heal 15% max HP per execution kill
	if execute_talent and execution_kill_count > 0 and owner_node:
		var heal_amount := int(owner_node.max_hp * 0.15 * execution_kill_count)
		if heal_amount > 0:
			owner_node.hp = mini(owner_node.hp + heal_amount, owner_node.max_hp)
			if owner_node.has_method("_update_health_display"):
				owner_node._update_health_display(heal_amount, false)
	
	# Choose random teleport target from killed enemies and teleport immediately
	if _killed_positions.size() > 0:
		var choice_index := randi() % _killed_positions.size()
		teleport_target = _killed_positions[choice_index]
		should_teleport = true
		# Teleport immediately like original
		if owner_node:
			owner_node.global_position = teleport_target

func _apply_vulnerability(enemy: Node2D) -> void:
	"""Apply 50% increased damage taken debuff to enemy with purple cracked visual."""
	if not is_instance_valid(enemy):
		return
	
	# Set a meta flag that Enemy.gd can check
	enemy.set_meta("damage_vulnerability", 1.5)  # 50% more damage = 1.5x multiplier
	
	# Apply visual shader effect
	var sprite: Node = null
	if enemy.has_node("AnimatedSprite2D"):
		sprite = enemy.get_node("AnimatedSprite2D")
	elif enemy.has_node("Sprite2D"):
		sprite = enemy.get_node("Sprite2D")
	
	var original_material: Material = null
	if sprite and sprite is CanvasItem:
		original_material = sprite.material
		var vuln_shader = load("res://resources/shaders/vulnerability_debuff.gdshader")
		if vuln_shader:
			var shader_mat = ShaderMaterial.new()
			shader_mat.shader = vuln_shader
			shader_mat.set_shader_parameter("intensity", 1.0)
			shader_mat.set_shader_parameter("pulse_speed", 1.5)
			shader_mat.set_shader_parameter("crack_density", 4.0)
			sprite.material = shader_mat
	
	# Create a timer to remove the debuff after 8 seconds
	var debuff_timer := Timer.new()
	debuff_timer.wait_time = 8.0
	debuff_timer.one_shot = true
	debuff_timer.autostart = true
	var enemy_ref := enemy
	var sprite_ref := sprite
	var orig_mat_ref := original_material
	debuff_timer.timeout.connect(func():
		if is_instance_valid(enemy_ref):
			enemy_ref.remove_meta("damage_vulnerability")
		if is_instance_valid(sprite_ref) and sprite_ref is CanvasItem:
			sprite_ref.material = orig_mat_ref
		debuff_timer.queue_free()
	)
	enemy.add_child(debuff_timer)

func _get_camera_view_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	
	var camera := viewport.get_camera_2d()
	if camera == null:
		# Fall back to viewport rect
		var fallback_size := viewport.get_visible_rect().size
		var center := global_position
		return Rect2(center - fallback_size / 2, fallback_size)
	
	var canvas_transform := viewport.get_canvas_transform()
	var vp_size := viewport.get_visible_rect().size
	var camera_center := camera.global_position
	var half_size := vp_size / 2 / canvas_transform.get_scale()
	return Rect2(camera_center - half_size, half_size * 2)

func _draw() -> void:
	if duration <= 0.0:
		return
	
	var progress := clampf(_age / max(duration, 0.0001), 0.0, 1.0)
	var alpha := _get_alpha(progress)
	
	if alpha <= 0.01:
		return
	
	# Draw main flash at origin
	var main_color := Color(flash_color.r, flash_color.g, flash_color.b, flash_color.a * alpha)
	draw_circle(Vector2.ZERO, flash_radius * (1.0 - progress * 0.3), main_color)
	
	# Draw glow layer
	var glow_color := Color(flash_color.r, flash_color.g * 0.8, flash_color.b, flash_color.a * alpha * 0.5)
	draw_circle(Vector2.ZERO, flash_radius * 1.3 * (1.0 - progress * 0.4), glow_color)
	
	# Draw flashes at killed enemy positions
	for pos in _killed_positions:
		var local_pos := pos - global_position
		var enemy_color := Color(enemy_flash_color.r, enemy_flash_color.g, enemy_flash_color.b, enemy_flash_color.a * alpha)
		draw_circle(local_pos, enemy_flash_radius * (1.0 - progress * 0.5), enemy_color)

func _get_alpha(progress: float) -> float:
	if progress < 0.15:
		return lerpf(0.0, 1.0, progress / 0.15)
	if progress < 0.4:
		return 1.0
	return lerpf(1.0, 0.0, (progress - 0.4) / 0.6)
