extends Node2D
class_name RapunzelBurstEffect

## Rapunzel's burst: Stuns all enemies and heals the player for 75% of max HP
## Creates a warm golden healing aura effect
## With talents: 8s stun duration, 8s invincibility

@export var duration: float = 0.65
@export var stun_duration: float = 4.0
@export var heal_percent: float = 1.0
@export var flash_radius: float = 320.0
@export var flash_color: Color = Color(1.0, 0.94, 0.72, 0.92)
@export var glow_color: Color = Color(1.0, 0.85, 0.5, 0.6)
@export var heal_ring_color: Color = Color(0.4, 1.0, 0.5, 0.7)

var owner_node: Node2D = null

# Talent bonuses
var grant_invuln: bool = false # Divine Protection talent (now default)
var invuln_duration: float = 8.0

# "6,000? Really?" talent - turret spawning
var spawn_turrets: bool = false
var turret_owner_level: int = 1
const TURRET_COUNT := 10 # 5x2 grid across the map
const TURRET_AMMO := 4 # 2 shots at 2 rockets each

# Blinding Radiance: when false, bosses are not stunned by the burst.
var stun_bosses: bool = true
# Turret upgrades passed to each spawned turret.
var turret_incendiary_level: int = 0   # "Incendiary Rockets" - It Burns ground
var turret_extra_ammo: int = 0         # "Extra Stuffed" - bonus rockets per turret
# "Anti-Queen Bombardment": all turret rockets target this point instead of enemies.
var use_fixed_target: bool = false
var fixed_target_position: Vector2 = Vector2.ZERO

var _age: float = 0.0
var _has_executed: bool = false

func _ready() -> void:
	set_process(true)
	z_index = 500
	queue_redraw()
	
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")

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

func _process(delta: float) -> void:
	_age += delta
	
	# Execute the heal/stun effect on first frame
	if not _has_executed:
		_has_executed = true
		_execute_burst()
	
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _execute_burst() -> void:
	if owner_node == null:
		return
	
	# Heal the player
	if owner_node.has_method("heal"):
		var max_hp = owner_node.max_hp if "max_hp" in owner_node else 100
		var heal_amount := int(float(max_hp) * heal_percent)
		owner_node.heal(heal_amount)
	elif "hp" in owner_node and "max_hp" in owner_node:
		var heal_amount := int(float(owner_node.max_hp) * heal_percent)
		owner_node.hp = mini(owner_node.hp + heal_amount, owner_node.max_hp)
		# Update HP bar if exists
		if "hp_bar" in owner_node and owner_node.hp_bar:
			owner_node.hp_bar.value = owner_node.hp
		# Update HUD if exists
		if "player_hud" in owner_node and owner_node.player_hud:
			owner_node.player_hud.update_health(owner_node.hp, owner_node.max_hp, heal_amount, true)
	
	# Grant invincibility if Divine Protection talent is unlocked
	if grant_invuln and owner_node:
		if "invincible" in owner_node:
			owner_node.invincible = true
		# Create a timer to remove invincibility after duration
		var invuln_timer := Timer.new()
		invuln_timer.wait_time = invuln_duration
		invuln_timer.one_shot = true
		invuln_timer.autostart = true
		var player_ref := owner_node
		invuln_timer.timeout.connect(func():
			if is_instance_valid(player_ref) and "invincible" in player_ref:
				player_ref.invincible = false
			invuln_timer.queue_free()
		)
		owner_node.add_child(invuln_timer)
	
	# Stun all enemies
	if not get_tree():
		return
	
	for node in TargetCache.get_enemies():
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
		
		var enemy := node as Node2D

		# Apply stun effect (Blinding Radiance does not stun bosses).
		if enemy.has_method("apply_stun"):
			var is_boss: bool = enemy.is_in_group("bosses") or enemy.is_in_group("super_boss") or enemy.is_in_group("guardian_bosses") or enemy.is_in_group("gbosses")
			if stun_bosses or not is_boss:
				enemy.apply_stun(stun_duration)

		# Register burst hit
		if owner_node and owner_node.has_method("register_burst_hit"):
			owner_node.register_burst_hit(enemy, true) # from_burst = true
	
	# "6,000? Really?" talent: Spawn 20 turrets around map edges
	if spawn_turrets:
		_spawn_edge_turrets()

func _draw() -> void:
	if duration <= 0.0:
		return
	
	var progress := clampf(_age / max(duration, 0.0001), 0.0, 1.0)
	var alpha := _get_alpha(progress)
	
	if alpha <= 0.01:
		return
	
	# Draw expanding glow
	var glow_scale := 1.0 + progress * 0.5
	var glow_alpha := alpha * 0.5
	var glow := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * glow_alpha)
	draw_circle(Vector2.ZERO, flash_radius * glow_scale, glow)
	
	# Draw main flash
	var main_color := Color(flash_color.r, flash_color.g, flash_color.b, flash_color.a * alpha)
	draw_circle(Vector2.ZERO, flash_radius * (1.0 - progress * 0.2), main_color)
	
	# Draw inner bright core
	var core_alpha := alpha * (1.0 - progress)
	var core_color := Color(1.0, 1.0, 0.95, core_alpha * 0.9)
	draw_circle(Vector2.ZERO, flash_radius * 0.4 * (1.0 - progress * 0.3), core_color)
	
	# Draw healing ring particles
	_draw_heal_particles(progress, alpha)

func _draw_heal_particles(progress: float, alpha: float) -> void:
	var particle_count := 12
	var ring_radius := flash_radius * (0.5 + progress * 0.4)
	
	for i in range(particle_count):
		var angle := (float(i) / float(particle_count)) * TAU + progress * TAU * 0.5
		var offset := Vector2(cos(angle), sin(angle)) * ring_radius
		
		# Rising particle effect
		offset.y -= progress * 60.0
		
		var particle_alpha := alpha * (1.0 - progress * 0.5)
		var particle_color := Color(heal_ring_color.r, heal_ring_color.g, heal_ring_color.b, heal_ring_color.a * particle_alpha)
		var particle_size := 8.0 + sin(progress * PI) * 4.0
		
		draw_circle(offset, particle_size, particle_color)

func _get_alpha(progress: float) -> float:
	if progress < 0.15:
		return lerpf(0.0, 1.0, progress / 0.15)
	if progress < 0.5:
		return 1.0
	return lerpf(1.0, 0.0, (progress - 0.5) / 0.5)


## "6,000? Really?" talent: Spawn 20 turrets spread across the MAP interior (not camera)
func _spawn_edge_turrets() -> void:
	if not owner_node or not get_tree():
		return
	
	var parent_node = get_parent()
	if not parent_node:
		parent_node = owner_node.get_parent()
	if not parent_node:
		return
	
	# Get camera for zoom effect
	var camera := get_viewport().get_camera_2d()
	
	# Use actual MAP bounds (4000x4000 centered at origin)
	# This matches the world_size set in Level.gd
	const MAP_SIZE := 4000.0
	const MARGIN := 300.0 # Keep turrets away from absolute edge
	var map_min := -MAP_SIZE / 2.0 + MARGIN
	var map_max := MAP_SIZE / 2.0 - MARGIN
	
	# Zoom camera out to show more of the map
	_zoom_camera_out(camera)
	
	# Distribute turrets in a grid-like pattern across the MAP
	# 10 turrets = 5 columns x 2 rows for good coverage
	var positions: Array[Vector2] = []
	var cols := 5
	var rows := 2
	
	for row in range(rows):
		for col in range(cols):
			# Calculate position with margins - spread across entire map
			var tx := float(col) / float(cols - 1) if cols > 1 else 0.5
			var ty := float(row) / float(rows - 1) if rows > 1 else 0.5
			
			var x := lerpf(map_min, map_max, tx)
			var y := lerpf(map_min, map_max, ty)
			positions.append(Vector2(x, y))
	
	# Spawn turrets at calculated positions using simplified BurstTurret.
	# Spawning is staggered 5 per frame: creating all 20 nodes in one frame
	# caused a visible hitch. (4 frames total — well inside this effect's
	# 0.65s lifetime, so the coroutine can't outlive the node.)
	var tree := get_tree()

	# Extra Stuffed: each turret carries bonus rockets.
	var turret_ammo: int = TURRET_AMMO + turret_extra_ammo
	var spawned: Array = []

	for i in range(positions.size()):
		var pos := positions[i]
		# Use the standard turret scene so the barrage looks like a real turret and
		# fires homing, full-visual missiles (was the lightweight BurstTurret).
		var turret = ProjectileCache.create_turret()
		turret.ammo = turret_ammo
		turret.max_ammo = turret_ammo
		turret.spawner_node = owner_node
		# Stagger fire times: spread across 1 second (0.05s per turret) for faster deployment
		turret.fire_delay = float(i) * 0.05
		# Burst-tree turret upgrades
		turret.rapunzel_it_burns_level = turret_incendiary_level # Incendiary Rockets
		if use_fixed_target:
			turret.use_fixed_target = true
			turret.fixed_target_position = fixed_target_position

		parent_node.add_child(turret)
		turret.global_position = pos
		spawned.append(turret)

		if (i + 1) % 5 == 0 and i + 1 < positions.size():
			await tree.process_frame
			if not is_instance_valid(parent_node):
				return

	# Keep the camera zoomed out until the whole barrage has finished firing
	# (turrets despawn when empty). A persistent watcher polls them and zooms back
	# in, since this effect frees itself after ~0.65s.
	var watcher := ZoomWatcher.new()
	watcher.camera = camera
	watcher.turrets = spawned
	parent_node.add_child(watcher)


## Polls the spawned turrets and zooms the camera back in once they've all fired
## out (or after a safety timeout). Lives on the level so it outlasts the burst FX.
class ZoomWatcher extends Node:
	var turrets: Array = []
	var camera: Camera2D = null
	var _poll: float = 0.0
	var _elapsed: float = 0.0
	const MAX_WAIT := 30.0

	func _process(delta: float) -> void:
		_elapsed += delta
		_poll += delta
		if _poll < 0.4 and _elapsed < MAX_WAIT:
			return
		_poll = 0.0
		var any_alive := false
		for t in turrets:
			if is_instance_valid(t):
				any_alive = true
				break
		if not any_alive or _elapsed >= MAX_WAIT:
			RapunzelBurstEffect._zoom_camera_in_static(camera)
			queue_free()


func _zoom_camera_out(camera: Camera2D) -> void:
	if not camera:
		return
	
	# Use get_tree().create_tween() so tween persists after this node is freed
	var tree := get_tree()
	if not tree:
		return
	
	# Use CombatJuice's base zoom for smooth animation
	if CombatJuice.instance:
		var tween := tree.create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2(0.5, 0.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		# Fallback: direct camera zoom
		var tween := tree.create_tween()
		tween.tween_property(camera, "zoom", Vector2(0.5, 0.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Static version that can be called from timer callback
static func _zoom_camera_in_static(camera: Camera2D) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	var tree := camera.get_tree()
	if not tree:
		return
	
	# Use CombatJuice's base zoom for smooth animation
	if CombatJuice.instance:
		var tween := tree.create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		# Fallback: direct camera zoom
		var tween := tree.create_tween()
		tween.tween_property(camera, "zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
