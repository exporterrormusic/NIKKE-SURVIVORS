extends Node
class_name WeatherSystem
## Manages weather effects: lightning, rain sound, fog, etc.
##
## This is a helper module that can be used by EnvironmentController
## to delegate weather-related functionality. It's designed for
## gradual adoption - EnvironmentController can continue to work
## without changes, or can delegate to this class.
##
## Usage:
##   var weather := WeatherSystem.new()
##   add_child(weather)
##   weather.configure(biome, lightning_overlay)
##   weather.start()

signal lightning_flash_started
signal lightning_flash_ended

## Reference to the lightning overlay ColorRect
var _lightning_overlay: ColorRect = null

## Reference to the audio director for thunder sounds
var _audio_director: Node = null

## Current biome configuration
var _biome: Resource = null

## Random number generator
var _rng := RandomNumberGenerator.new()

## Timer until next lightning strike
var _lightning_timer: float = 0.0

## Whether weather effects are active
var _active: bool = false


func _ready() -> void:
	_rng.randomize()
	# Try to find AudioDirector autoload
	if has_node("/root/AudioDirector"):
		_audio_director = get_node("/root/AudioDirector")


func _process(delta: float) -> void:
	if not _active:
		return
	
	_update_lightning(delta)


## Configure the weather system with the current biome
func configure(biome: Resource, lightning_overlay: ColorRect = null) -> void:
	_biome = biome
	_lightning_overlay = lightning_overlay
	_lightning_timer = 0.0


## Start weather effects
func start() -> void:
	_active = true


## Stop weather effects
func stop() -> void:
	_active = false


## Get the lightning frequency from the biome
func get_lightning_frequency() -> float:
	if _biome == null:
		return 0.0
	if not "lightning_frequency" in _biome:
		return 0.0
	return _biome.lightning_frequency


## Get the lightning intensity from the biome
func get_lightning_intensity() -> float:
	if _biome == null:
		return 0.5
	if not "lightning_intensity" in _biome:
		return 0.5
	return _biome.lightning_intensity


## Check if the current biome has lightning
func has_lightning() -> bool:
	return get_lightning_frequency() > 0.0


func _update_lightning(delta: float) -> void:
	if not has_lightning() or not _lightning_overlay:
		return
	
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		# Increase thunder frequency by 30% and reset timer
		var effective_freq: float = get_lightning_frequency() * 1.3
		var interval: float = 1.0 / effective_freq
		_lightning_timer = _rng.randf_range(interval * 0.5, interval * 1.5)
		
		# Trigger lightning flash
		trigger_lightning_flash()


## Manually trigger a lightning flash
func trigger_lightning_flash() -> void:
	if not _lightning_overlay:
		return
	
	emit_signal("lightning_flash_started")
	
	# Play thunder sound
	if _audio_director and _audio_director.has_method("play_sfx_by_path"):
		_audio_director.play_sfx_by_path(
			"res://assets/sounds/sfx/environment/thunder.wav", 
			1.0, 
			6.0
		)
	
	# Create a tween for the flash
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Flash to white with intensity
	var flash_color := Color(1.0, 1.0, 1.0, get_lightning_intensity())
	_lightning_overlay.color = flash_color
	
	# Fade out quickly
	tween.tween_property(_lightning_overlay, "color:a", 0.0, 0.15)
	tween.tween_callback(func():
		_lightning_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
		emit_signal("lightning_flash_ended")
	)


## Set the lightning overlay (call after configure if needed)
func set_lightning_overlay(overlay: ColorRect) -> void:
	_lightning_overlay = overlay


## Set the audio director reference
func set_audio_director(director: Node) -> void:
	_audio_director = director
