extends Node2D
class_name CecilWishEffect

## Cecil's "Three Wishes" revive visual effect
## Quick 1-second sequence (miniature version of Sin's wish effect):
## - Brief pause with monochrome filter
## - Flash wish image for 0.5s
## - Resume with 1s additional invincibility

signal sequence_complete

# Phase timing (shorter version of Sin's)
const PAUSE_DURATION := 0.8 # How long game stays paused
const IMAGE_DISPLAY_TIME := 0.5 # How long wish image shows
const TOTAL_DURATION := 1.0 # Total effect duration

# State
var player_ref: Node2D = null
var _is_active: bool = false
var _age: float = 0.0

# Nodes
# Nodes
var _filter_rect: ColorRect = null
var _image_sprite: Sprite2D = null
var _audio_player: AudioStreamPlayer = null
var _base_scale: float = 1.0

# Resources - use Sin's wish images but Cecil's own wish audio
const WISH_IMAGE_1 = preload("res://assets/characters/sin/wish-1.png")
const WISH_IMAGE_2 = preload("res://assets/characters/sin/wish-2.png")
const WISH_AUDIO = preload("res://assets/characters/cecil/WISH.mp3")

func _ready() -> void:
	z_index = 500
	process_mode = Node.PROCESS_MODE_ALWAYS # Run while paused
	
	# Assign to effects layer
	call_deferred("_assign_to_effects_layer")
	
	# Pause game
	get_tree().paused = true
	
	# Setup effect
	_is_active = true
	_setup_mono_filter()
	_show_wish_image()
	_play_wish_audio()
	
	# Pop player above filter
	if player_ref:
		player_ref.z_as_relative = false
		player_ref.z_index = 200

func _assign_to_effects_layer() -> void:
	var root = get_tree().root
	var env = root.get_node_or_null("Level/EnvironmentController")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_age += delta
	
	# Animate image fade in/out - smooth transition across entire duration
	if _image_sprite and is_instance_valid(_image_sprite):
		var target_alpha: float = _image_sprite.get_meta("target_alpha", 0.9)
		var half_time: float = PAUSE_DURATION / 2.0
		
		if _age < half_time:
			# First half: fade in
			var progress = _age / half_time
			_image_sprite.modulate.a = lerpf(0.0, target_alpha, ease(progress, 0.5))
		else:
			# Second half: fade out
			var progress = (_age - half_time) / half_time

			_image_sprite.modulate.a = lerpf(target_alpha, 0.0, ease(progress, 2.0))
			
		# Apply slight zoom (zoom in by 10% over duration)
		var zoom_progress = _age / PAUSE_DURATION
		var zoom_mult = 1.0 + (zoom_progress * 0.1)
		_image_sprite.scale = Vector2(_base_scale * zoom_mult, _base_scale * zoom_mult)
	
	# Complete sequence after pause duration
	if _age >= PAUSE_DURATION:
		_complete_sequence()

func _setup_mono_filter() -> void:
	"""Create monochrome filter like Sin's effect."""
	var viewport_cam = get_viewport().get_camera_2d() if get_viewport() else null
	var cam_pos = viewport_cam.global_position if viewport_cam else Vector2.ZERO
	var cam_zoom = viewport_cam.zoom if viewport_cam else Vector2.ONE
	var viewport_size = get_viewport().get_visible_rect().size
	
	_filter_rect = ColorRect.new()
	_filter_rect.z_index = 49 # Below player (z=200)
	_filter_rect.z_as_relative = false
	_filter_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Calculate filter size to cover entire visible area
	var filter_size = viewport_size / cam_zoom * 2.0
	_filter_rect.size = filter_size
	_filter_rect.position = cam_pos - filter_size / 2.0
	
	# Monochrome shader - blue/purple tint like Cecil
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	// Cool cyan/blue tint for Cecil
	vec3 tinted = vec3(gray * 0.6, gray * 0.8, gray * 1.0);
	COLOR = vec4(tinted, tex.a * 0.8);
}
"""
	mat.shader = shader
	_filter_rect.material = mat
	
	get_parent().add_child(_filter_rect)

func _show_wish_image() -> void:
	"""Show a wish image scaled to fill screen."""
	var textures = [WISH_IMAGE_1, WISH_IMAGE_2]
	var texture = textures[randi() % textures.size()]
	if not texture:
		return
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(canvas)
	
	_image_sprite = Sprite2D.new()
	_image_sprite.texture = texture
	_image_sprite.z_index = 100
	
	# Scale to fill the screen (100%)
	var viewport_size = get_viewport().get_visible_rect().size
	var tex_size = texture.get_size()
	var scale_factor = maxf(viewport_size.x / tex_size.x, viewport_size.y / tex_size.y) * 1.0
	
	_base_scale = scale_factor
	_image_sprite.scale = Vector2(scale_factor, scale_factor)
	_image_sprite.position = viewport_size / 2.0
	_image_sprite.modulate.a = 0.0 # Start invisible
	_image_sprite.set_meta("target_alpha", 0.85)
	canvas.add_child(_image_sprite)

func _play_wish_audio() -> void:
	"""Play wish sound effect at reduced volume for briefer effect."""
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "SFX"
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_player.volume_db = -3.0 # Slightly quieter
	
	if WISH_AUDIO:
		_audio_player.stream = WISH_AUDIO
		add_child(_audio_player)
		_audio_player.play()

func _complete_sequence() -> void:
	"""Clean up and unpause."""
	_is_active = false
	
	# Clean up filter
	if is_instance_valid(_filter_rect):
		_filter_rect.queue_free()
	
	# Clean up image
	if is_instance_valid(_image_sprite):
		var parent_canvas = _image_sprite.get_parent()
		_image_sprite.queue_free()
		if parent_canvas and parent_canvas is CanvasLayer:
			parent_canvas.queue_free()
	
	# Let audio play to completion (don't cut it off)
	if is_instance_valid(_audio_player):
		# Reparent to tree root so it survives this node being freed
		remove_child(_audio_player)
		get_tree().root.add_child(_audio_player)
		_audio_player.finished.connect(_audio_player.queue_free)
	
	# Restore player z-index
	if player_ref and is_instance_valid(player_ref):
		player_ref.z_as_relative = true
		player_ref.z_index = 0
	
	# Unpause game
	get_tree().paused = false
	
	# Emit completion
	sequence_complete.emit()
	
	# Self destruct
	await get_tree().create_timer(0.2).timeout
	queue_free()
