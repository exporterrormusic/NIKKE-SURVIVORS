extends Node
class_name BurstSystem
## Manages the player's burst (ultimate) gauge.
## Extracted from PlayerCore for modularity.

signal burst_ready
signal burst_used
signal burst_changed(current: float, maximum: float)

## Maximum burst value
@export var burst_max: float = 100.0

## Burst gained per hit
@export var burst_per_hit: float = 2.5

## Current burst value
var burst_current: float = 0.0

## Reference to player for talent checks
var _player: Node = null

## Commander upgrade doubles burst gain
var _commander_burst_upgrade: bool = false


func initialize(player: Node) -> void:
	_player = player


func set_commander_upgrade(enabled: bool) -> void:
	_commander_burst_upgrade = enabled


func is_ready() -> bool:
	return burst_current >= burst_max


func is_unlocked() -> bool:
	if not _player:
		return false
	if _player.has_method("is_burst_unlocked"):
		return _player.is_burst_unlocked()
	return false


func add_burst(from_burst: bool = false) -> void:
	"""Add burst from a hit. Ignored if from_burst is true (prevent recursion)."""
	if from_burst:
		return
	if not is_unlocked():
		return
	
	var gain := burst_per_hit
	
	# Commander "Obviously Anderson" upgrade: 2x burst generation
	if _commander_burst_upgrade:
		gain *= 2.0
	
	var was_ready := is_ready()
	burst_current = minf(burst_current + gain, burst_max)
	burst_changed.emit(burst_current, burst_max)
	
	if is_ready() and not was_ready:
		burst_ready.emit()


func gain_burst(amount: float) -> void:
	"""Add arbitrary burst amount (e.g. from damage dealt)."""
	if not is_unlocked():
		return
		
	var was_ready := is_ready()
	burst_current = minf(burst_current + amount, burst_max)
	burst_changed.emit(burst_current, burst_max)
	
	if is_ready() and not was_ready:
		burst_ready.emit()


func use_burst(consume_fraction: float = 1.0) -> bool:
	"""Attempt to use burst. consume_fraction is the portion of the gauge spent
	(1.0 = all, 0.5 = half, 0.0 = none); used by Snow White's
	"A Goddess Who Cannot Yield". Returns true if successful."""
	if not is_ready():
		return false

	# Check for debug infinite burst
	if _player and _player.has_meta("debug_infinite_burst") and _player.get_meta("debug_infinite_burst"):
		burst_changed.emit(burst_current, burst_max)
		burst_used.emit()
		return true

	burst_current = burst_max * (1.0 - clampf(consume_fraction, 0.0, 1.0))
	burst_changed.emit(burst_current, burst_max)
	burst_used.emit()
	return true


func get_progress() -> float:
	"""Returns 0.0-1.0 progress toward burst readiness."""
	if burst_max <= 0:
		return 0.0
	return burst_current / burst_max
