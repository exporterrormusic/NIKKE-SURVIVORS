extends Node
class_name PlayerNightGlow
## Manages the player's night glow PointLight2D for visibility during night cycles.
## Extracted from PlayerCore for separation of concerns.

## Reference back to PlayerCore
var player: PlayerCore = null

# Night glow light reference
var _night_glow_light: PointLight2D = null


func _ready() -> void:
	if not player:
		player = get_parent() as PlayerCore


func setup_environment_modulate() -> void:
	"""Connect to EnvironmentController to toggle night glow."""
	_create_night_glow_light()
	
	var env_controller = player.get_tree().get_first_node_in_group("environment_controller")
	if env_controller and env_controller is EnvironmentController:
		if env_controller.has_signal("modulate_changed"):
			env_controller.modulate_changed.connect(_on_environment_modulate_changed)
			# Set initial state
			_on_environment_modulate_changed(env_controller.current_modulate)


func _create_night_glow_light() -> void:
	if _night_glow_light:
		return
	
	_night_glow_light = PointLight2D.new()
	_night_glow_light.name = "NightGlowLight"
	_night_glow_light.color = Color(0.7, 0.85, 1.0, 1.0) # Soft blue-white glow
	_night_glow_light.energy = 0.0 # Start hidden (will be enabled at night)
	_night_glow_light.texture_scale = 12.0 # Large soft radius
	_night_glow_light.blend_mode = Light2D.BLEND_MODE_ADD
	_night_glow_light.z_index = -1 # Behind the sprite
	
	# Create a simple radial gradient texture for smooth falloff
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32, 32)
	for x in 64:
		for y in 64:
			var dist := Vector2(x, y).distance_to(center) / 32.0
			var alpha := clampf(1.0 - dist, 0.0, 1.0) * 0.5 # Soft edges
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	var tex := ImageTexture.create_from_image(img)
	_night_glow_light.texture = tex
	
	player.add_child(_night_glow_light)


func _on_environment_modulate_changed(color: Color) -> void:
	"""Calculate night intensity from modulate color (darker = more night)."""
	var avg_brightness: float = (color.r + color.g + color.b) / 3.0
	var night_boost: float = clampf((0.95 - avg_brightness) / 0.6, 0.0, 1.0)
	
	if _night_glow_light:
		_night_glow_light.energy = night_boost * 0.4
