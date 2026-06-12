extends Node

## Marian ally behavior - Minigun with continuous beam

var active_beam: Node2D = null

func configure(ally, _registry) -> void:
	var hp_mult: float = 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(50 * hp_mult)
	ally.move_speed = 200.0
	ally.attack_damage = ally._get_scaled_damage(2)
	ally.attack_range = 450.0
	ally.attack_cooldown = 0.08
	ally._special_cooldown = 4.0
	ally._apply_wells_speed_boost()
	ally._load_sprite("marian")

func attack(ally, direction: Vector2) -> void:
	if active_beam != null and is_instance_valid(active_beam):
		return
	active_beam = null
	var MarianBeamScript = load("res://scripts/characters/effects/MarianBeam.gd")
	if not MarianBeamScript:
		return
	var beam = Node2D.new()
	beam.set_script(MarianBeamScript)
	beam.owner_node = ally
	beam.player_ref = ally
	beam.target_enemy = ally._target_enemy
	beam.duration = 4.5
	beam.beam_width = 60.0
	beam.beam_range = 2400.0
	beam.damage_per_second = 12.0
	beam.missile_upgrade = false
	beam.trail_upgrade = false
	beam.initial_direction = direction
	beam.beam_volume_db = -5.0
	ally._attack_timer = 999.0
	active_beam = beam
	ally.get_parent().add_child(beam)
	beam.global_position = ally.global_position
	beam.tree_exited.connect(_on_beam_exited.bind(beam, ally))

func _on_beam_exited(beam_ref: Node2D, ally) -> void:
	if not ally.is_inside_tree(): return
	await ally.get_tree().process_frame
	if not is_instance_valid(beam_ref):
		if active_beam == beam_ref:
			active_beam = null
			ally._attack_timer = 0.0

func should_use_special(ally) -> bool:
	return false

func perform_burst(ally) -> void:
	if active_beam != null and is_instance_valid(active_beam):
		active_beam.queue_free()
	active_beam = null
	var MarianBeamScript = load("res://scripts/characters/effects/MarianBeam.gd")
	if not MarianBeamScript:
		return
	var direction: Vector2 = ally._last_direction.normalized()
	if direction.length() < 0.5:
		direction = Vector2.RIGHT
	var beam = Node2D.new()
	beam.set_script(MarianBeamScript)
	beam.owner_node = ally
	beam.player_ref = ally
	beam.target_enemy = ally._target_enemy
	beam.duration = 4.0
	beam.beam_width = 240.0
	beam.beam_range = 3000.0
	beam.damage_per_second = 40.0
	beam.missile_upgrade = true
	beam.trail_upgrade = true
	beam.initial_direction = direction
	beam.player_level = ally.player_level
	beam.beam_volume_db = -5.0
	active_beam = beam
	ally.get_parent().add_child(beam)
	beam.global_position = ally.global_position
	beam.tree_exited.connect(_on_beam_exited.bind(beam, ally))

func get_optimal_range() -> float:
	return 200.0

func process(ally, _delta: float) -> void:
	pass
