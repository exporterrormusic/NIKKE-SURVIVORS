extends Node
class_name LightningManager
## Manages lightning flash timing and visual effects.
##
## Extracted from EnvironmentController to reduce god class size.
## Handles: lightning timer countdown, flash tween animation, thunder SFX.

var _lightning_timer: float = 0.0
var _rng: RandomNumberGenerator = null
var _lightning_overlay: ColorRect = null
var _audio_director: Node = null
var _active_biome: BiomeDefinition = null


func setup(rng: RandomNumberGenerator, lightning_overlay: ColorRect, audio_director: Node) -> void:
	_rng = rng
	_lightning_overlay = lightning_overlay
	_audio_director = audio_director


func set_biome(biome: BiomeDefinition) -> void:
	_active_biome = biome
	_lightning_timer = 0.0


func process(delta: float) -> void:
	if not _active_biome or _active_biome.lightning_frequency <= 0.0 or not _lightning_overlay:
		return
	
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		# Increase thunder frequency by 30% and reset timer based on effective frequency
		var effective_freq: float = _active_biome.lightning_frequency * 1.3
		var interval: float = 1.0 / effective_freq
		_lightning_timer = _rng.randf_range(interval * 0.5, interval * 1.5)
		_trigger_lightning_flash()


func _trigger_lightning_flash() -> void:
	if not _lightning_overlay:
		return
	
	# Play thunder sound
	if _audio_director:
		_audio_director.play_sfx_by_path("res://assets/sounds/sfx/environment/thunder.wav", 1.0, 6.0)
	
	# Create a tween for the flash
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Flash to white with intensity
	var flash_color := Color(1.0, 1.0, 1.0, _active_biome.lightning_intensity)
	_lightning_overlay.color = flash_color
	
	# Fade out quickly
	tween.tween_property(_lightning_overlay, "color:a", 0.0, 0.15)
	tween.tween_callback(func(): _lightning_overlay.color = Color(1.0, 1.0, 1.0, 0.0))
