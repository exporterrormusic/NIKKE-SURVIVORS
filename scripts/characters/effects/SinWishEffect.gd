extends Node2D
class_name SinWishEffect

## Sin's "I WISH They Were Gone" death save effect
## 8-second sequence:
## - Monochrome filter (Scarlet-style), player stays in color
## - 5-5.5s: Flash wish image
## - 5-8s: Destroy non-boss enemies gradually
## - After: 3s invulnerability (handled by PlayerCore)

signal sequence_complete

var player_ref: Node2D = null

# Timing constants
const TOTAL_DURATION := 8.0
const RED_TINT_START := 0.0
const RED_TINT_END := 5.0
const IMAGE_FLASH_START := 5.0
const IMAGE_FLASH_DURATION := 0.5
const DESTRUCTION_START := 5.0
const DESTRUCTION_END := 8.0

# State
var _age: float = 0.0
var _is_active: bool = true
var _filter_rect: ColorRect = null
var _image_sprite: Sprite2D = null
var _base_scale: Vector2 = Vector2.ONE
var _audio_player: AudioStreamPlayer = null
var _enemies_to_destroy: Array = []
var _destruction_index: int = 0
var _image_shown: bool = false
var _tinted_enemies: Dictionary = {} # enemy -> original modulate

# Resources
var _wish_images: Array = []
const WISH_IMAGE_1 = preload("res://assets/characters/sin/wish-1.png")
const WISH_IMAGE_2 = preload("res://assets/characters/sin/wish-2.png")
const WISH_AUDIO = preload("res://assets/characters/sin/wish.mp3")

func _ready() -> void:
	z_index = 500
	process_mode = Node.PROCESS_MODE_ALWAYS # Run while paused
	
	# Load wish images
	_wish_images = [
		WISH_IMAGE_1,
		WISH_IMAGE_2
	]
	
	# Assign to effects layer like Scarlet does
	call_deferred("_assign_to_effects_layer")
	# Start sequence deferred like Scarlet
	call_deferred("_start_sequence")

func _assign_to_effects_layer() -> void:
	"""Reparent to EffectsLayer like Scarlet's burst does."""
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

func _start_sequence() -> void:
	"""Start the wish sequence after reparenting."""
	# Pause game first (like Scarlet)
	get_tree().paused = true
	
	# Create filter while paused
	_setup_purple_filter()
	_play_wish_audio()
	_collect_enemies_to_destroy()
	
	# Pop player above filter (z=50) like Scarlet does with owner (z=200)
	if player_ref:
		player_ref.z_as_relative = false
		player_ref.z_index = 200

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_age += delta
	
	# Phase 1: Enemy red tinting (0-5s)
	if _age >= RED_TINT_START and _age < RED_TINT_END:
		var tint_progress = clampf((_age - RED_TINT_START) / (RED_TINT_END - RED_TINT_START), 0.0, 1.0)
		_apply_enemy_red_tint(tint_progress)
	
	# Phase 2: Image flash (5-5.5s)
	if _age >= IMAGE_FLASH_START and not _image_shown:
		_image_shown = true
		_show_wish_image()
	
	# Update image flash (dissolve in/out)
	if _image_sprite and is_instance_valid(_image_sprite):
		var flash_age = _age - IMAGE_FLASH_START
		var target_alpha = _image_sprite.get_meta("target_alpha") if _image_sprite.has_meta("target_alpha") else 0.9
		
		if flash_age < IMAGE_FLASH_DURATION:
			# Dissolve in for first 0.25s, dissolve out for second 0.25s
			var half_duration = IMAGE_FLASH_DURATION * 0.5
			var progress: float
			if flash_age < half_duration:
				progress = flash_age / half_duration
			else:
				progress = 1.0 - ((flash_age - half_duration) / half_duration)
			
			# Apply progress to target alpha
			_image_sprite.modulate.a = target_alpha * progress
			
			# Apply zoom
			var zoom_mult = 1.0 + (flash_age / IMAGE_FLASH_DURATION) * 0.1
			_image_sprite.scale = _base_scale * zoom_mult
		else:
			_image_sprite.queue_free()
			_image_sprite = null
	
	# Phase 3: Destroy enemies gradually (5-8s)
	if _age >= DESTRUCTION_START and _age < DESTRUCTION_END:
		_destroy_enemies_gradually()
	
	# Complete sequence
	if _age >= TOTAL_DURATION:
		_complete_sequence()

func _setup_purple_filter() -> void:
	"""Create monochrome filter - exact copy of Scarlet's _create_mono_filter."""
	# Get camera (same approach as Scarlet)
	var viewport_cam = get_parent().get_viewport().get_camera_2d()
	if not viewport_cam:
		push_warning("[SinWishEffect] No camera!")
		return
	
	var viewport_size = get_viewport_rect().size / viewport_cam.zoom
	var center = viewport_cam.global_position
	
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
	
	# Add to Environment or Parent (must be below player but above World)
	# Use get_parent() same as Scarlet
	get_parent().add_child(_filter_rect)
	print("[SinWishEffect] Filter created. Parent: %s" % get_parent().name)

func _play_wish_audio() -> void:
	"""Play wish.mp3 sound effect."""
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "SFX"
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var audio = WISH_AUDIO
	if audio:
		_audio_player.stream = audio
		add_child(_audio_player)
		_audio_player.play()

func _collect_enemies_to_destroy() -> void:
	"""Collect all non-boss enemies for destruction."""
	var tree = get_tree()
	if not tree:
		return
	
	var all_enemies = tree.get_nodes_in_group("enemies")
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Only process actual Node2D enemies
		if not enemy is Node2D:
			continue
		
		# Only collect actual enemies with hp property or take_damage method
		# Also catch shielders which might store hp differently
		var has_hp = "hp" in enemy or "current_hp" in enemy or enemy.has_method("take_damage")
		var is_shielder = enemy.is_in_group("shielder")
		if not (has_hp or is_shielder):
			continue
		
		# Skip bosses
		if _is_boss_enemy(enemy):
			continue
			
		# Skip charmed allies (Sin's mind control)
		if enemy.is_in_group("charmed_allies"):
			continue
		
		_enemies_to_destroy.append(enemy)
		# Store original modulate AND z-index so we can restore later
		_tinted_enemies[enemy] = {
			"modulate": enemy.modulate if "modulate" in enemy else Color.WHITE,
			"z_index": enemy.z_index,
			"z_as_relative": enemy.z_as_relative
		}
		
		# Elevate enemy above the filter (z=50) so red tint shows through monochrome
		enemy.z_as_relative = false
		enemy.z_index = 100
	
	print("[SinWishEffect] Collected %d enemies to destroy" % _enemies_to_destroy.size())
	
	# Shuffle for more random destruction
	_enemies_to_destroy.shuffle()

func _apply_enemy_red_tint(progress: float) -> void:
	"""Gradually tint enemies red based on progress (0-1)."""
	for enemy in _tinted_enemies.keys():
		if not is_instance_valid(enemy):
			continue
		
		var data = _tinted_enemies[enemy]
		var original = data["modulate"]
		var red_tint = Color(1.0, 0.3, 0.3, 1.0)
		enemy.modulate = original.lerp(red_tint, progress)

func _is_boss_enemy(enemy: Node) -> bool:
	"""Check if enemy is a boss (should be protected)."""
	# Check groups
	if enemy.is_in_group("boss") or enemy.is_in_group("super_boss") or enemy.is_in_group("guardian_bosses"):
		return true
	
	# Check tier metadata
	if enemy.has_meta("enemy_tier"):
		var tier = enemy.get_meta("enemy_tier")
		if tier in ["boss", "super_boss"]:
			return true
	
	# Check name for N01
	if "N01" in enemy.name:
		return true
	
	return false

func _show_wish_image() -> void:
	"""Show a random wish image scaled to fill screen."""
	if _wish_images.is_empty():
		return
	
	var texture = _wish_images[randi() % _wish_images.size()]
	if not texture:
		return
	
	# Create sprite on a canvas layer above everything
	var canvas = CanvasLayer.new()
	canvas.layer = 200
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	
	var viewport_size = get_viewport_rect().size
	var tex_size = texture.get_size()
	var scale_factor = max(viewport_size.x / tex_size.x, viewport_size.y / tex_size.y)
	var final_scale = Vector2(scale_factor, scale_factor) * 1.1 # Slight overscale
	_base_scale = final_scale
	
	# Single image at 90% opacity, normal blend mode
	_image_sprite = Sprite2D.new()
	_image_sprite.texture = texture
	_image_sprite.centered = true
	_image_sprite.modulate.a = 0.0 # Start invisible, will animate
	_image_sprite.scale = final_scale
	_image_sprite.position = viewport_size / 2.0
	_image_sprite.set_meta("target_alpha", 0.9) # 90% opacity target
	canvas.add_child(_image_sprite)

func _destroy_enemies_gradually() -> void:
	"""Destroy collected enemies over the destruction phase."""
	if _enemies_to_destroy.is_empty():
		return
	
	var destruction_progress = (_age - DESTRUCTION_START) / (DESTRUCTION_END - DESTRUCTION_START)
	var target_destroyed = int(_enemies_to_destroy.size() * destruction_progress)
	
	# Destroy enemies up to target count
	while _destruction_index < target_destroyed and _destruction_index < _enemies_to_destroy.size():
		var enemy = _enemies_to_destroy[_destruction_index]
		_destruction_index += 1
		
		if is_instance_valid(enemy):
			# Create death effect
			_spawn_death_effect(enemy.global_position)
			
			# Kill the enemy
			if enemy.has_method("die"):
				enemy.die()
			elif enemy.has_method("take_damage"):
				# Deal exactly enough damage to kill (current hp or max_hp if no current)
				var hp_val = enemy.get("hp") if "hp" in enemy else (enemy.get("current_hp") if "current_hp" in enemy else (enemy.get("max_hp") if "max_hp" in enemy else 100))
				enemy.take_damage(hp_val, false, Vector2.ZERO, true, "sin_wish")
			else:
				enemy.queue_free()

func _spawn_death_effect(pos: Vector2) -> void:
	"""Spawn a purple death flash at position."""
	var effect = Node2D.new()
	effect.global_position = pos
	effect.z_index = 100
	effect.process_mode = Node.PROCESS_MODE_ALWAYS
	effect.set_script(_get_death_effect_script())
	get_parent().add_child(effect)

func _get_death_effect_script() -> GDScript:
	var script = GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0
var _duration: float = 0.3

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress = _time / _duration
	var radius = 30.0 + progress * 50.0
	var alpha = 1.0 - progress
	draw_circle(Vector2.ZERO, radius, Color(0.6, 0.2, 0.9, alpha * 0.8))
	draw_circle(Vector2.ZERO, radius * 0.6, Color(0.8, 0.4, 1.0, alpha))
"""
	script.reload()
	return script

func _complete_sequence() -> void:
	"""Clean up and emit completion signal."""
	_is_active = false
	
	# Clean up filter
	if is_instance_valid(_filter_rect):
		_filter_rect.queue_free()
	
	# Stop audio
	if is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.queue_free()
	
	# Restore enemy modulates and z-index (for any survivors like bosses)
	for enemy in _tinted_enemies.keys():
		if is_instance_valid(enemy):
			var data = _tinted_enemies[enemy]
			enemy.modulate = data["modulate"]
			enemy.z_index = data["z_index"]
			enemy.z_as_relative = data["z_as_relative"]
	
	# Restore player Z
	if player_ref and is_instance_valid(player_ref):
		player_ref.z_as_relative = true
		player_ref.z_index = 0
	
	# Unpause game
	get_tree().paused = false
	
	# Emit completion
	sequence_complete.emit()
	
	# Self destruct with delay for any remaining effects
	await get_tree().create_timer(0.5).timeout
	queue_free()
