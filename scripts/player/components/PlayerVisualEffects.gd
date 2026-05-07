extends Node
class_name PlayerVisualEffects
## Manages player visual effects: Eden shield visual, shield hit effects,
## Marian beam buff, revive effects, Sin wish visual sequence.
## Extracted from PlayerCore for separation of concerns.

const KiloShieldVisualScript = preload("res://scripts/effects/KiloShieldVisual.gd")
const ShieldHitScript = preload("res://scripts/effects/ShieldHitEffect.gd")
const CecilWishEffectScript = preload("res://scripts/characters/effects/CecilWishEffect.gd")
const SinWishEffectScript = preload("res://scripts/characters/effects/SinWishEffect.gd")

## Reference back to PlayerCore
var player: PlayerCore = null

# Eden shield visual
var _eden_shield_visual: Node2D = null

# Marian beam buff visual
var _marian_beam_buff_visual: Node2D = null


func _ready() -> void:
	# Find parent if not set
	if not player:
		player = get_parent() as PlayerCore


# ============= EDEN SHIELD VISUALS =============

func create_eden_shield_visual() -> void:
	"""Creates the visual shield effect for Eden's Shield upgrade."""
	if _eden_shield_visual and is_instance_valid(_eden_shield_visual):
		return
	
	_eden_shield_visual = KiloShieldVisualScript.new()
	_eden_shield_visual.name = "EdenShieldVisual"
	call_deferred("_add_eden_shield_visual")


func _add_eden_shield_visual() -> void:
	if _eden_shield_visual and is_instance_valid(_eden_shield_visual):
		get_parent().add_child(_eden_shield_visual)
		_eden_shield_visual.initialize(player)


func update_shield_display(current: int, maximum: int) -> void:
	"""Update the visual shield with current shield status."""
	if _eden_shield_visual and is_instance_valid(_eden_shield_visual):
		_eden_shield_visual.update_shield(current, maximum)


func spawn_shield_hit_effect() -> void:
	"""Spawns a cyan shield hit effect when Eden's shield absorbs damage."""
	var effect = ShieldHitScript.new()
	get_parent().add_child(effect)
	effect.global_position = player.global_position
	
	if _eden_shield_visual and is_instance_valid(_eden_shield_visual) and _eden_shield_visual.has_method("on_shield_hit"):
		_eden_shield_visual.on_shield_hit()


# ============= MARIAN BEAM BUFF VISUAL =============

func activate_marian_beam_buff() -> void:
	"""Activate Marian's beam absorption buff visual."""
	create_marian_buff_visual()
	update_marian_beam_visual(true)


func create_marian_buff_visual() -> void:
	"""Create smoky purple glow around player."""
	if _marian_beam_buff_visual and is_instance_valid(_marian_beam_buff_visual):
		return
	
	_marian_beam_buff_visual = load("res://scripts/player/components/MarianBeamBuffVisual.tscn").instantiate() if ResourceLoader.exists("res://scripts/player/components/MarianBeamBuffVisual.tscn") else _create_marian_buff_visual_inline()


func _create_marian_buff_visual_inline() -> Node2D:
	var node := Node2D.new()
	node.name = "MarianBeamBuffGlow"
	node.set_script(_get_marian_buff_glow_script())
	return node


func _get_marian_buff_glow_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0
var _particles: Array = []

func _ready() -> void:
	z_index = -1
	for i in range(12):
		_particles.append({
			"angle": randf() * TAU,
			"dist": randf_range(30, 60),
			"speed": randf_range(0.5, 1.5),
			"size": randf_range(15, 30),
			"alpha": randf_range(0.3, 0.6)
		})

func _process(delta: float) -> void:
	_time += delta
	for p in _particles:
		p.angle += p.speed * delta
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var pos = Vector2(cos(p.angle), sin(p.angle)) * p.dist
		var pulse = 0.8 + 0.2 * sin(_time * 3.0 + p.angle)
		var color = Color(0.6, 0.2, 0.9, p.alpha * pulse)
		draw_circle(pos, p.size, color)
	var center_alpha = 0.3 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, 50, Color(0.5, 0.1, 0.8, center_alpha))
"""
	script.reload()
	return script


func update_marian_beam_visual(active: bool) -> void:
	"""Update Marian beam visual state and notify controller."""
	if active:
		if _marian_beam_buff_visual == null or not is_instance_valid(_marian_beam_buff_visual):
			create_marian_buff_visual()
			player.add_child(_marian_beam_buff_visual)
		# Notify Marian controller for damage boost
		var controller = player.get_current_controller()
		if controller is MarianController:
			controller.set_beam_buff_active(true)
	else:
		if _marian_beam_buff_visual and is_instance_valid(_marian_beam_buff_visual):
			_marian_beam_buff_visual.queue_free()
			_marian_beam_buff_visual = null
		# Notify Marian controller
		var controller = player.get_current_controller()
		if controller is MarianController:
			controller.set_beam_buff_active(false)


# ============= REVIVE EFFECTS =============

func spawn_revive_effect() -> void:
	"""Spawn Cecil's 'Three Wishes' visual effect with pause and wish image."""
	var effect = CecilWishEffectScript.new()
	effect.player_ref = player
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position


# ============= SIN WISH SEQUENCE =============

func trigger_sin_wish_sequence() -> void:
	"""Trigger Sin's 'I WISH They Were Gone' death save sequence."""
	if not SinWishEffectScript:
		push_error("[PlayerVisualEffects] Failed to load SinWishEffect.gd!")
		return
	
	var effect = SinWishEffectScript.new()
	effect.player_ref = player
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position
	
	# Connect completion signal to grant invulnerability
	if effect.has_signal("sequence_complete"):
		effect.sequence_complete.connect(_on_sin_wish_complete)


func _on_sin_wish_complete() -> void:
	"""Called when Sin's wish sequence finishes."""
	# Grant 3 seconds of invulnerability
	player.invincible = true
	player._cecil_revive_invincible_timer = 3.0
	player.hp = player.max_hp
	player._update_health_display(player.max_hp, false)
	print("[PlayerVisualEffects] Sin wish sequence complete. 3s invulnerability granted.")
