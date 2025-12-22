extends Node2D
class_name ScarletBurstEffect

## Scarlet's burst: Instantly kills all enemies on screen and teleports to one of them
## Creates a dramatic red flash effect
## With Execution talent: Instantly kills non-elite, non-boss enemies
## With Expose Weakness talent: Applies 50% damage taken debuff

@export var duration: float = 0.5
@export var flash_radius: float = 260.0
@export var flash_color: Color = Color(1.0, 0.1, 0.1, 0.85)
@export var enemy_flash_color: Color = Color(1.0, 0.1, 0.1, 0.85)
@export var enemy_flash_radius: float = 130.0

var owner_node: Node2D = null
var teleport_target: Vector2 = Vector2.ZERO
var should_teleport: bool = false

# Talent bonuses
var execute_talent: bool = false # Instantly kill non-elite/boss enemies
var vuln_talent: bool = false # Apply 50% damage taken debuff

var _age: float = 0.0
var _killed_positions: Array[Vector2] = []
var _has_executed: bool = false
var _pending_kills: Array[Dictionary] = [] # Stores {enemy, damage, direction, execute}

var _filter_rect: ColorRect = null
var _original_z: int = 0
var _original_process_mode: int = 0
var _owner_original_process_mode: int = 0
var _restored_paused: bool = false

signal burst_complete(teleport_position: Vector2)

func _ready() -> void:
	set_process(true)
	z_index = 500
	queue_redraw()
	
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")
	
	# Start the sequential burst logic
	call_deferred("_start_sequence")

## Safety: Ensure game is unpaused if this node is forcibly deleted
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Emergency cleanup - ensure game isn't left paused
		if _restored_paused and get_tree():
			get_tree().paused = false
		# Clean up filter if still exists
		if is_instance_valid(_filter_rect):
			_filter_rect.queue_free()

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

var _is_dashing: bool = false
var _current_dash_dir: Vector2 = Vector2.ZERO
var _owner_sprite: Node2D = null
var _owner_orig_flip_h: bool = false
var _owner_orig_rotation: float = 0.0
var _owner_orig_scale: Vector2 = Vector2.ONE

# Store component modes for restoration
var _orig_movement_mode: int = 0
var _orig_weapons_mode: int = 0

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	
	if _is_dashing:
		_spawn_ghost()

func _start_sequence() -> void:
	if not get_tree() or not owner_node:
		queue_free()
		return
	
	# Collect valid targets
	var targets: Array[Node2D] = _collect_targets()
	
	if targets.is_empty():
		emit_signal("burst_complete", owner_node.global_position)
		queue_free()
		return
	
	# Sort targets by HP descending (Kill highest HP first? Or last? User said "ends on one she was able to kill")
	# "Desc order of current health" -> High HP first. Low HP last.
	# "Ideally ends on one she was able to kill" -> Low HP at end? Yes.
	targets.sort_custom(func(a, b):
		var hp_a = a.hp if "hp" in a else 0
		var hp_b = b.hp if "hp" in b else 0
		return hp_a > hp_b
	)
	
	# Calculate Scale
	var speed_mult: float = 1.0
	if targets.size() > 10:
		speed_mult = 2.0
	elif targets.size() > 5:
		speed_mult = 1.5
	
	var dash_time: float = 0.1 / speed_mult
	var wait_time: float = 0.2 / speed_mult
	
	# Enter Time Stop
	_setup_time_stop()
	
	# Process each target sequentially
	for enemy in targets:
		if not is_instance_valid(enemy):
			continue
			
		var start_pos = owner_node.global_position
		var enemy_pos = enemy.global_position
		var dir = (enemy_pos - start_pos).normalized()
		_current_dash_dir = dir
		
		# Offset target: Stop 50px BEFORE the enemy
		var target_pos = enemy_pos - (dir * 50.0)
		
		# Setup Squish/Stretch visuals
		if _owner_sprite:
			_owner_sprite.rotation = dir.angle()
			var base_scale = _owner_orig_scale.abs()
			_owner_sprite.scale = base_scale * Vector2(2.0, 0.6)
			
			if "flip_h" in _owner_sprite:
				_owner_sprite.flip_h = false
		
		# Hyper Dash
		_is_dashing = true
		var dash_tween = create_tween()
		dash_tween.tween_property(owner_node, "global_position", target_pos, dash_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await dash_tween.finished
		_is_dashing = false
		
		# Reset visuals
		if _owner_sprite:
			_owner_sprite.rotation = _owner_orig_rotation
			_owner_sprite.scale = _owner_orig_scale
			if "flip_h" in _owner_sprite:
				_owner_sprite.flip_h = _owner_orig_flip_h
		
		# Teleport tracking
		teleport_target = target_pos
		
		# Visual Slash & Sound
		if owner_node.has_method("_get_weapon_type_name") and owner_node.audio_director:
			owner_node.audio_director.play_weapon_fire_sound("sword")
		
		var slash = ProjectileCache.create_slash()
		
		# HIDE IMMEDIATELY and mask color
		slash.visible = false
		slash.modulate.a = 0.0
		
		# MANUAL CRTL
		slash.process_mode = Node.PROCESS_MODE_ALWAYS
		slash.set("tracking", false)
		
		# VISUAL CONFIGURATION
		# 1. Disable Additive Blend (Must do before _ready)
		# 2. Force UNSHADED material for maximum opacity vs Filter
		var visual_node = slash.get_node_or_null("SwordSlashVisual")
		if visual_node:
			visual_node.set("additive_blend", false)
			var mat = CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
			mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			visual_node.material = mat
		
		# 2. Set Visual Overrides (Passed to update_visual in _ready)
		# Radius 130.0 = 50% of 260.0 default
		# Opacity 0.4 = Even more transparent (Unshaded)
		if "override_visual_params" in slash:
			slash.override_visual_params = {
				"radius": 130.0,
				"core_color": Color(1.0, 0.0, 0.0, 0.4),
				"edge_color": Color(1.0, 0.5, 0.5, 0.4),
				"glow_color": Color(0.8, 0.0, 0.0, 0.4),
				"fade": 1.0
			}
		
		# Suppress any CombatJuice purple fringing (Chromatic Aberration)
		if CombatJuice.instance:
			CombatJuice.chromatic_pulse(0.0)
		
		# PARENT TO WORLD
		get_parent().add_child(slash)
		
		# Apply transforms
		# Note: Radius is scaled by parameter, so node scale can stay 1.0 or adjust if needed
		# User asked for "visuals 50% smaller". Parameter radius handles this best.
		slash.global_position = owner_node.global_position
		slash.look_at(enemy_pos)
		
		# Modulate Parent as fallback
		slash.modulate = Color(1, 0.0, 0.0)
		
		# Explicit Global Z
		slash.z_as_relative = false
		slash.z_index = 205
		
		# Disable physics
		if slash.has_method("set_deferred"):
			slash.set_deferred("monitorable", false)
			slash.set_deferred("monitoring", false)
		slash.collision_mask = 0
		slash.collision_layer = 0
		
		# REVEAL
		slash.visible = true
		slash.modulate.a = 1.0
		
		# Wait
		await get_tree().create_timer(wait_time).timeout
		
		if not is_instance_valid(enemy):
			continue
		
		# Mark target
		_mark_target(enemy)
		
	# Exit Time Stop
	_cleanup_time_stop()
	
	# Execute all kills simultaneously
	_execute_pending_kills()
		
	# Finish
	emit_signal("burst_complete", owner_node.global_position)
	queue_free()

func _setup_time_stop() -> void:
	# Store original state
	_original_z = owner_node.z_index
	_original_process_mode = process_mode
	_owner_original_process_mode = owner_node.process_mode
	
	# Capture Sprite state
	_owner_sprite = owner_node.get_node_or_null("Sprite2D")
	if not _owner_sprite:
		_owner_sprite = owner_node.get_node_or_null("AnimatedSprite2D")
		
	if _owner_sprite:
		_owner_orig_rotation = _owner_sprite.rotation
		_owner_orig_scale = _owner_sprite.scale
		if "flip_h" in _owner_sprite:
			_owner_orig_flip_h = _owner_sprite.flip_h
	
	# LOCK CONTROLS
	# Stop Owner Logic
	owner_node.set_process(false)
	owner_node.set_physics_process(false)
	owner_node.set_process_input(false)
	owner_node.set_process_unhandled_input(false)
	
	# Disable Subsystems (Movement, Weapons)
	if owner_node.get("_movement"):
		_orig_movement_mode = owner_node._movement.process_mode
		owner_node._movement.process_mode = Node.PROCESS_MODE_DISABLED
	
	if owner_node.get("_weapons"):
		_orig_weapons_mode = owner_node._weapons.process_mode
		owner_node._weapons.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Set ALWAYS process mode so we run while paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	owner_node.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Pause game
	get_tree().paused = true
	_restored_paused = true
	
	# Create Monochrome Filter
	_create_mono_filter()
	
	# Elevate Scarlet above filter (Filter is Z=50)
	# IMPORTANT: Disable relative Z to pop out of YSort/Parents
	owner_node.z_as_relative = false
	owner_node.z_index = 200 # Global Z 200 (Highest)
	
	# No explicit Tint/Modulate - Rely on Z-Index to "Pop" (Normal Color vs Grayscale BG)

func _cleanup_time_stop() -> void:
	# Remove Filter
	if is_instance_valid(_filter_rect):
		_filter_rect.queue_free()
	
	# Restore Scarlet
	if is_instance_valid(owner_node):
		owner_node.z_index = _original_z
		owner_node.z_as_relative = true # Restore default
		owner_node.modulate = Color.WHITE # Ensure reset
		owner_node.process_mode = _owner_original_process_mode
		
		# Restore logic
		owner_node.set_process(true)
		owner_node.set_physics_process(true)
		owner_node.set_process_input(true)
		owner_node.set_process_unhandled_input(true)
		
		# Restore Subsystems
		if owner_node.get("_movement"):
			owner_node._movement.process_mode = _orig_movement_mode
		if owner_node.get("_weapons"):
			owner_node._weapons.process_mode = _orig_weapons_mode
		
		# Restore visuals
		if _owner_sprite:
			_owner_sprite.rotation = _owner_orig_rotation
			_owner_sprite.scale = _owner_orig_scale
			if "flip_h" in _owner_sprite:
				_owner_sprite.flip_h = _owner_orig_flip_h
	
	# Restore self
	process_mode = _original_process_mode
	
	# Resume game
	if _restored_paused:
		get_tree().paused = false
	
	_owner_sprite = null

func _spawn_ghost() -> void:
	if not _owner_sprite: return
	
	var ghost
	if _owner_sprite is Sprite2D:
		ghost = Sprite2D.new()
		ghost.texture = _owner_sprite.texture
		ghost.hframes = _owner_sprite.hframes
		ghost.vframes = _owner_sprite.vframes
		ghost.frame = _owner_sprite.frame
	elif _owner_sprite is AnimatedSprite2D and _owner_sprite.sprite_frames:
		ghost = Sprite2D.new()
		var anim = _owner_sprite.animation
		var idx = _owner_sprite.frame
		ghost.texture = _owner_sprite.sprite_frames.get_frame_texture(anim, idx)
	else:
		return
	
	# Position: Farther behind player (60px)
	ghost.global_position = owner_node.global_position - (_current_dash_dir * 60.0)
	ghost.rotation = _owner_sprite.rotation
	# Ghost scale: larger (1.5x original)
	# Pushing to 1.5 to ensure visibility change
	ghost.global_position = owner_node.global_position - (_current_dash_dir * 60.0)
	ghost.rotation = _owner_sprite.rotation
	# Ghost scale: Reverting to 1.25 (User said "shrink back down to what it was earlier")
	# (Earlier was 1.25 in step 7475).
	ghost.scale = _owner_sprite.scale * 1.25
	
	# MATERIAL FIX: Use Additive Blending so it looks like Energy (Bright Red)
	# This prevents "Dark Purple" or "Muddy" look on dark sprites
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = mat
	
	ghost.modulate = Color(1.0, 0.0, 0.0, 0.8) # Strong Red Additive (0.8)
	
	# Z-Index: Between Filter (50) and Scarlet (200)
	ghost.z_as_relative = false
	ghost.z_index = 100
	
	# CRITICAL: Always process so it fades/frees while game is paused
	ghost.process_mode = Node.PROCESS_MODE_ALWAYS
	
	get_parent().add_child(ghost)
	
	# Tween fade
	var tween = create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tween.tween_callback(ghost.queue_free)

func _create_mono_filter() -> void:
	var viewport_size = get_viewport_rect().size / get_parent().get_viewport().get_camera_2d().zoom
	var center = get_parent().get_viewport().get_camera_2d().global_position
	
	_filter_rect = ColorRect.new()
	_filter_rect.color = Color.WHITE # Default to White (Original behavior)
	_filter_rect.size = viewport_size * 2.0 # Oversize to cover rotation/movement
	_filter_rect.position = center - _filter_rect.size / 2.0
	
	# Filter Z = 50 (Absolute)
	_filter_rect.z_as_relative = false
	_filter_rect.z_index = 50
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap; void fragment() { vec4 bg = texture(screen_texture, SCREEN_UV); float gray = dot(bg.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(gray, gray, gray, bg.a); }"
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	_filter_rect.material = mat
	
	# Add to Environment or Parent (must be below Scarlet but aboveWorld)
	# Effectively, adding to parent with high Z is fine
	get_parent().add_child(_filter_rect)

func _collect_targets() -> Array[Node2D]:
	var valid_targets: Array[Node2D] = []
	var view_rect := _get_camera_view_rect()
	var filter_by_view := view_rect.size.x > 0.0 and view_rect.size.y > 0.0
	
	# Filter caching because getting nodes while paused works fine
	for node in TargetCache.get_enemies():
		if not is_instance_valid(node) or not node is Node2D:
			continue
		
		# Skip non-visual nodes or dying enemies
		if node.is_in_group("dying"): continue
		
		# Skip charmed allies (Sin's mind control)
		if node.is_in_group("charmed_allies"): continue
			
		var enemy := node as Node2D
		if filter_by_view and not view_rect.has_point(enemy.global_position):
			continue
			
		valid_targets.append(enemy)
	
	return valid_targets

func _mark_target(enemy: Node2D) -> void:
	# Turn enemy red and bring above filter
	# IMPORTANT: Disable relative Z to ensure it pops out of local hierarchy
	var orig_z_rel = enemy.z_as_relative
	enemy.z_as_relative = false
	enemy.z_index = 101 # Above filter
	
	# User requested NO TINT, just Z-pop (Normal colors vs Monochrome BG)
	# enemy.modulate = Color(1.0, 0.0, 0.0) 
	
	# Queue for deletion
	_pending_kills.append({"node": enemy, "orig_z_rel": orig_z_rel})

func _execute_pending_kills() -> void:
	var execution_kill_count_total: int = 0
	
	for pk in _pending_kills:
		var enemy = pk["node"]
		var orig_z_rel = pk.get("orig_z_rel", true)
		
		if not is_instance_valid(enemy):
			continue
			
		# Restore visuals logic is handled by enemy death usually
		enemy.z_index = 0
		enemy.z_as_relative = orig_z_rel
		# enemy.modulate = Color.WHITE # No need if we didn't change it
		
		# Determine execute logic (re-check in case stats changed?)
		var is_elite_or_boss: bool = enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") in ["elite", "boss"]
		is_elite_or_boss = is_elite_or_boss or enemy.is_in_group("elite") or enemy.is_in_group("boss")
		
		var will_execute := false
		var damage_base: int = 0
		if owner_node:
			if owner_node.has_method("calc_damage"):
				damage_base = owner_node.calc_damage()
			elif "attack_damage" in owner_node:
				damage_base = owner_node.attack_damage
			elif "base_damage" in owner_node:
				damage_base = owner_node.base_damage
				
		var damage_amount: int = damage_base * 10
		
		# Apply Scraping the Bottle multiplier if available
		if owner_node and owner_node.has_method("get_low_hp_damage_multiplier"):
			damage_amount = int(float(damage_amount) * owner_node.get_low_hp_damage_multiplier())
		
		if execute_talent and not is_elite_or_boss:
			damage_amount = 999999
			will_execute = true
			
		# Vulnerability
		if vuln_talent:
			_apply_vulnerability(enemy)
			
		# Apply Damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage_amount, false, Vector2.ZERO, true, "ScarletBurst")
		elif enemy.has_method("apply_damage"):
			enemy.apply_damage(damage_amount, "ScarletBurst")
			
		_killed_positions.append(enemy.global_position)
		
		if will_execute:
			execution_kill_count_total += 1
		
		if owner_node and owner_node.has_method("register_burst_hit"):
			owner_node.register_burst_hit(enemy, true)
			
	# Apply Healing - use heal() method for immediate visual feedback
	if execute_talent and execution_kill_count_total > 0 and owner_node:
		var heal_amount := int(owner_node.max_hp * 0.15 * execution_kill_count_total)
		if heal_amount > 0 and owner_node.has_method("heal"):
			owner_node.heal(heal_amount) # Proper heal method triggers floating number and updates display

func _apply_vulnerability(enemy: Node2D) -> void:
	"""Apply 50% increased damage taken debuff to enemy with purple cracked visual."""
	if not is_instance_valid(enemy):
		return
	
	# Set a meta flag that Enemy.gd can check
	enemy.set_meta("damage_vulnerability", 1.5) # 50% more damage = 1.5x multiplier
	
	# Apply visual shader effect
	# Robust sprite finding (Handles nested Visuals/Sprite2D structures)
	# Prioritize "Visuals" node as it likely contains the composed boss sprite
	var sprite: CanvasItem = null
	var additional_targets: Array[CanvasItem] = [] # For hair, arms, etc.
	
	if enemy.has_node("Visuals"):
		var visuals = enemy.get_node("Visuals")
		if visuals.has_node("AnimatedSprite2D"):
			sprite = visuals.get_node("AnimatedSprite2D")
		elif visuals.has_node("Sprite2D"):
			sprite = visuals.get_node("Sprite2D")
		
		# Also capture hair and arms for the Rapture Queen
		for child in visuals.get_children():
			if child != sprite and child is CanvasItem:
				additional_targets.append(child)
	
	# Fallback to root sprites if nothing found in Visuals (or Visuals doesn't exist)
	if not sprite:
		if enemy.has_node("AnimatedSprite2D"):
			sprite = enemy.get_node("AnimatedSprite2D")
		elif enemy.has_node("Sprite2D"):
			sprite = enemy.get_node("Sprite2D")
	
	# Handle Timer Refreshing (Stacking = Refresh Duration)
	var timer_name = "ScarletVulnTimer"
	var debuff_timer: Timer = enemy.get_node_or_null(timer_name)
	
	if debuff_timer:
		# Timer exists, just refresh it
		debuff_timer.start(8.0)
		return # Visuals already applied
	
	# New Debuff Application
	var original_material: Material = null
	var original_materials: Dictionary = {} # Store original materials for all targets
	
	if sprite:
		original_material = sprite.material
		var vuln_shader = load("res://resources/shaders/vulnerability_debuff.gdshader")
		if vuln_shader:
			var shader_mat = ShaderMaterial.new()
			shader_mat.shader = vuln_shader
			shader_mat.set_shader_parameter("intensity", 1.0)
			shader_mat.set_shader_parameter("pulse_speed", 3.0) # Faster as requested
			shader_mat.set_shader_parameter("crack_density", 4.0)
			shader_mat.set_shader_parameter("tint_factor", 1.0) # Full purple tint for Sprite
			# Standard Square scale for sprites
			shader_mat.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
			sprite.material = shader_mat
			
			# Apply screen-space shader to additional targets (hair, arms)
			# _draw() nodes don't have proper UV coords, so use screen-space version
			var screenspace_shader = load("res://resources/shaders/vulnerability_debuff_screenspace.gdshader")
			if screenspace_shader:
				for target in additional_targets:
					original_materials[target.get_instance_id()] = target.material
					var target_mat = ShaderMaterial.new()
					target_mat.shader = screenspace_shader
					target_mat.set_shader_parameter("intensity", 1.0)
					target_mat.set_shader_parameter("pulse_speed", 3.0)
					target_mat.set_shader_parameter("crack_density", 1.5) # Lower for bigger cracks
					target_mat.set_shader_parameter("tint_factor", 1.0)
					target.material = target_mat
	
	# Create new timer
	debuff_timer = Timer.new()
	debuff_timer.name = timer_name
	debuff_timer.wait_time = 8.0
	debuff_timer.one_shot = true
	debuff_timer.autostart = true
	
	var enemy_ref := enemy
	var sprite_ref := sprite
	var orig_mat_ref := original_material
	
	# Also apply to HP bar if found
	var hp_bar: Control = enemy.get_node_or_null("ProgressBar")
	# If Reparented by ModularEnemy, we might need a reference or search, 
	# but ModularEnemy keeps "hp_bar" variable. We can't access script vars easily without casting or dynamic access.
	# However, ModularEnemy reparents it to EffectsLayer. 
	# Accessing internal "hp_bar" property is safest if dealing with ModularEnemy type.
	
	var hp_elements: Array[CanvasItem] = []
	if "hp_bar" in enemy and is_instance_valid(enemy.hp_bar):
		hp_elements.append(enemy.hp_bar)
	# Do NOT transform the label (text readability issues)
	# if "hp_label" in enemy and is_instance_valid(enemy.hp_label):
	# 	hp_elements.append(enemy.hp_label)
		
	# Store original materials for HP elements
	var hp_orig_mats: Dictionary = {} # { object_id: material }
	# Use overlay-only shader for HP bars (doesn't sample TEXTURE)
	var overlay_shader_res = load("res://resources/shaders/crack_overlay.gdshader")
	
	# For HP bars, we create an OVERLAY instead of replacing the material
	# because ProgressBar has no TEXTURE - the shader reads empty/white pixels
	var hp_overlays: Array[Control] = []
	
	for el in hp_elements:
		hp_orig_mats[el.get_instance_id()] = el.material
		if overlay_shader_res and el is Control:
			# Create a transparent overlay that sits on top of the HP bar
			var overlay = ColorRect.new()
			overlay.name = "VulnOverlay"
			overlay.color = Color(0, 0, 0, 0) # Invisible base
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Use anchors to fill parent exactly, not PRESET which can overflow
			overlay.anchor_left = 0
			overlay.anchor_top = 0
			overlay.anchor_right = 1
			overlay.anchor_bottom = 1
			overlay.offset_left = 0
			overlay.offset_top = 0
			overlay.offset_right = 0
			overlay.offset_bottom = 0
			
			# Clip to parent bounds
			overlay.clip_contents = false # ColorRect doesn't clip itself, parent does
			el.clip_contents = true # Make the ProgressBar clip its children
			
			# Create shader material
			var mat = ShaderMaterial.new()
			mat.shader = overlay_shader_res
			mat.set_shader_parameter("intensity", 0.9)
			mat.set_shader_parameter("pulse_speed", 2.5)
			# REDUCED density for bigger, sparser cracks (0.5 = zoomed in)
			mat.set_shader_parameter("crack_density", 0.5)
			mat.set_shader_parameter("crack_color", Vector3(1.0, 1.0, 1.0)) # White cracks
			
			# Calculate UV Scale based on aspect ratio (Width / Height)
			var aspect_x = 1.0
			var size = el.size
			if size.y > 0:
				aspect_x = size.x / size.y
			mat.set_shader_parameter("uv_scale", Vector2(aspect_x, 1.0))
			
			overlay.material = mat
			el.add_child(overlay)
			hp_overlays.append(overlay)

	debuff_timer.timeout.connect(func():
		if is_instance_valid(enemy_ref):
			enemy_ref.remove_meta("damage_vulnerability")
			
			# Clean up visuals
			if is_instance_valid(sprite_ref) and sprite_ref is CanvasItem:
				# Restore original material
				sprite_ref.material = orig_mat_ref
			
			# Clean up additional targets (hair, arms) - restore material
			for target_id in original_materials.keys():
				# Find the target by walking all CanvasItems
				if enemy_ref.has_node("Visuals"):
					for child in enemy_ref.get_node("Visuals").get_children():
						if is_instance_valid(child) and child.get_instance_id() == target_id:
							child.material = original_materials[target_id]
				
			# Clean up HP bar overlays
			for overlay in hp_overlays:
				if is_instance_valid(overlay):
					overlay.queue_free()
		
		# Remove timer
		if is_instance_valid(debuff_timer):
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
	
	# Draw main flash at origin - REMOVED per user request
	# var main_color := Color(flash_color.r, flash_color.g, flash_color.b, flash_color.a * alpha)
	# draw_circle(Vector2.ZERO, flash_radius * (1.0 - progress * 0.3), main_color)
	
	# Draw glow layer - REMOVED per user request
	# var glow_color := Color(flash_color.r, flash_color.g * 0.8, flash_color.b, flash_color.a * alpha * 0.5)
	# draw_circle(Vector2.ZERO, flash_radius * 1.3 * (1.0 - progress * 0.4), glow_color)
	
	# Draw flashes at killed enemy positions - REMOVED per user request
	# for pos in _killed_positions:
	# 	var local_pos := pos - global_position
	# 	var enemy_color := Color(enemy_flash_color.r, enemy_flash_color.g, enemy_flash_color.b, enemy_flash_color.a * alpha)
	# 	draw_circle(local_pos, enemy_flash_radius * (1.0 - progress * 0.5), enemy_color)

func _get_alpha(progress: float) -> float:
	if progress < 0.15:
		return lerpf(0.0, 1.0, progress / 0.15)
	if progress < 0.4:
		return 1.0
	return lerpf(1.0, 0.0, (progress - 0.4) / 0.6)
