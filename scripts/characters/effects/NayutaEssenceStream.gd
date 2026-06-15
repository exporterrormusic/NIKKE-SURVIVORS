# Bright golden "essence" stream that bursts from a dying Nayuta clone and flows
# back to the player. Lives on the environment EffectsLayer (additive + unshaded)
# so it glows THROUGH night darkness, just like the player's aura sparkles.
#
# Crucially, the heal and the RETURN UNTO ME buff glow are applied WHEN the stream
# arrives at the player - not when the clone dies - so the reward visibly follows
# the particles home.
extends Node2D

var _player: Node2D = null
var _heal_amount: int = 0
var _is_return: bool = false
var _should_travel: bool = false
var _finished: bool = false
var _time: float = 0.0

var _sparkles: Array = []
const ARRIVE_DIST := 26.0
const SAFETY_TIME := 3.0  # a sparkle that somehow can't reach gives up after this

func _ready() -> void:
	z_index = 60
	# Additive + unshaded: reads as bright golden light and the EffectsLayer's
	# inverse-of-night modulate makes it glow brighter the darker it gets.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	light_mask = 0
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var world_pos := global_position
			var saved_parent = get_parent()
			if saved_parent:
				saved_parent.remove_child(self)
			effects.add_child(self)
			z_as_relative = false
			z_index = 500
			global_position = world_pos

## Called right after the node is added at the clone's death position.
func setup(player: Node2D, heal_amount: int, is_return: bool) -> void:
	_player = player
	_heal_amount = heal_amount
	_is_return = is_return
	# RETURN UNTO ME essence always flows home (to power her up); a plain death
	# only streams home when it heals, otherwise the sparkles just drift away.
	_should_travel = (heal_amount > 0 or is_return) and is_instance_valid(player)
	_spawn_burst()

func _spawn_burst() -> void:
	for i in range(44):
		var p := Vector2(randf_range(-14, 14), randf_range(-18, 14))
		_sparkles.append({
			"pos": p,
			"prev": p,
			"vel": Vector2(randf_range(-50, 50), randf_range(-80, -20)),
			"size": randf_range(2.5, 6.0),
			"delay": randf_range(0.0, 0.22),  # staggered so they form a flowing stream
			"travel": 0.0,
			"life": 1.0
		})

func _process(delta: float) -> void:
	_time += delta
	var travel_ok: bool = _should_travel and is_instance_valid(_player)

	for s in _sparkles:
		s.prev = s.pos

		# Staggered departure
		if s.delay > 0.0:
			s.delay -= delta
			s.vel.y -= 30.0 * delta
			s.pos += s.vel * delta * 0.35
			continue

		if travel_ok:
			# Flow fast toward the player, accelerating as it nears, and only
			# expire on ARRIVAL so far-away clones still deliver their stream.
			var to_player: Vector2 = _player.global_position - (global_position + s.pos)
			var dist: float = to_player.length()
			var speed: float = 900.0 + clampf(700.0 - dist, 0.0, 700.0) * 1.8
			s.vel = s.vel.lerp(to_player.normalized() * speed, delta * 12.0)
			s.pos += s.vel * delta
			s.travel += delta
			if dist < ARRIVE_DIST or s.travel > SAFETY_TIME:
				s.life = 0.0
		else:
			# No heal/return: drift upward and fade out
			s.life -= delta * 0.5
			s.vel.y -= 50.0 * delta
			s.pos += s.vel * delta

	_sparkles = _sparkles.filter(func(s): return s.life > 0.0)

	# Deliver the heal + glow exactly when the stream has finished arriving
	if not _finished and _sparkles.is_empty():
		_deliver()
		queue_free()
		return

	# Hard safety so the node can never linger forever
	if not _finished and _time > SAFETY_TIME + 0.6:
		_deliver()
		queue_free()
		return

	queue_redraw()

func _deliver() -> void:
	_finished = true
	if not is_instance_valid(_player):
		return
	if _heal_amount > 0 and _player.has_method("heal"):
		_player.heal(_heal_amount)
	# Light up Nayuta's RETURN UNTO ME aura now that the essence has arrived
	if _is_return and _player.has_method("get_current_controller"):
		var ctrl = _player.get_current_controller()
		if ctrl and ctrl.has_method("notify_return_essence_arrived"):
			ctrl.notify_return_essence_arrived()

func _draw() -> void:
	for s in _sparkles:
		var alpha: float = clampf(float(s.life), 0.0, 1.0)
		var head: Vector2 = s.pos
		var tail: Vector2 = s.prev
		var streak: Vector2 = head - tail

		# Motion trail - long streaks while flowing fast give the connected,
		# ribbon-like "flowing stream" look
		if streak.length() > 2.5:
			draw_line(tail, head, Color(1.0, 0.85, 0.3, alpha * 0.5), s.size * 0.8)
			draw_line(tail, head, Color(1.0, 0.95, 0.6, alpha * 0.9), s.size * 0.4)

		# Glowing head: soft halo, gold body, bright core
		draw_circle(head, s.size * alpha * 1.5, Color(1.0, 0.9, 0.5, alpha * 0.35))
		draw_circle(head, s.size * alpha, Color(1.0, 0.87, 0.35, alpha))
		draw_circle(head, s.size * alpha * 0.45, Color(1.0, 1.0, 0.85, alpha))
