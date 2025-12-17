extends CharacterBody2D
class_name FutureMarian

## Future Marian - Temporal Breach Boss Enemy
## Spawned by Wells when temporal breach triggers
## Uses Marian-style attacks but targets the player

signal died

# Constants
const TRACKING_SPEED := 45.0  # Very slow tracking
const BULLET_INTERVAL := 0.4  # Fire rate for bullets
const BEAM_COOLDOWN := 10.0   # How often to use beam
const BEAM_DURATION := 3.5    # Beam duration
const ROCKET_COOLDOWN := 6.0  # How often to fire rockets
const AIM_SPREAD := 0.4       # ~23 degrees inaccuracy
const BULLET_SPEED := 550.0   # Slower bullets (easy to dodge)
const SPAWN_DELAY := 2.0      # Seconds before attacking after spawn

# Purple tint for all attacks
const PURPLE_TINT := Color(0.6, 0.2, 1.0, 1.0)

# Stats (set by spawner or defaults)
@export var max_hp: int = 300
@export var base_damage: float = 12.0

var hp: int:
	get: return _health_component.current_hp if _health_component else 0
	set(value): 
		if _health_component: 
			_health_component.current_hp = value
			_update_hp_bar()

# Components
@onready var _health_component: Node = $HealthComponent
@onready var _movement_component: Node = $MovementComponent
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _hp_bar: ProgressBar = $ProgressBar
@onready var _hp_label: Label = $HPLabel

# State
var _player: Node2D
var _bullet_timer: float = 1.0   # Short delay before first bullet
var _beam_timer: float = 5.0     # First beam after 5s + spawn delay
var _rocket_timer: float = 3.0   # First rockets after 3s + spawn delay
var _is_beaming: bool = false
var _beam_instance: Node2D = null
var _spawn_timer: float = SPAWN_DELAY  # Don't attack immediately

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	add_to_group("temporal_marian")
	
	set_meta("enemy_tier", "boss")
	set_meta("display_name", "Future Marian")
	
	# Find player
	_player = get_tree().get_first_node_in_group("player")
	
	# Setup health
	if _health_component:
		_health_component.max_hp = max_hp
		_health_component.current_hp = max_hp
		_health_component.died.connect(_on_death)
		_health_component.health_changed.connect(_on_health_changed)
	
	# Setup HP bar
	_update_hp_bar()
	
	# Apply purple tint (to match attack theme)
	if _sprite:
		_sprite.modulate = Color(0.8, 0.4, 1.0, 1.0)  # Purple-red mix
	
	# Trigger boss HP bar
	call_deferred("_emit_boss_spawned")
	
	# Shimmer fade-in effect
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

func _emit_boss_spawned() -> void:
	if EventBus:
		EventBus.boss_spawned.emit(self)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	
	# Slow tracking toward player
	var to_player = _player.global_position - global_position
	var dir = to_player.normalized()
	
	velocity = dir * TRACKING_SPEED
	move_and_slide()
	
	# Sync HP bar position (top_level nodes don't follow parent)
	_sync_hp_bar_position()
	
	# Update animation
	_update_animation(dir)
	
	# Combat logic
	_process_combat(delta, dir)

func _update_animation(dir: Vector2) -> void:
	if not _sprite or not _sprite.sprite_frames:
		return
		
	var anim_name := "down"
	if abs(dir.x) > abs(dir.y):
		anim_name = "right" if dir.x > 0 else "left"
	else:
		anim_name = "down" if dir.y > 0 else "up"
	
	if _sprite.sprite_frames.has_animation(anim_name):
		if _sprite.animation != anim_name:
			_sprite.play(anim_name)

func _process_combat(delta: float, dir: Vector2) -> void:
	# Wait for spawn delay
	if _spawn_timer > 0:
		_spawn_timer -= delta
		return
	
	# Don't fire bullets/rockets while beaming
	if _is_beaming:
		if not is_instance_valid(_beam_instance):
			_is_beaming = false
		return
	
	# 1. Beam attack (highest priority - Marian's shop upgrade attack)
	_beam_timer -= delta
	if _beam_timer <= 0:
		_start_beam_attack(dir)
		return
	
	# 2. Rocket attack
	_rocket_timer -= delta
	if _rocket_timer <= 0:
		_fire_rockets(dir)
		_rocket_timer = ROCKET_COOLDOWN

func _start_beam_attack(dir: Vector2) -> void:
	_is_beaming = true
	_beam_timer = BEAM_COOLDOWN + BEAM_DURATION
	
	# Visual flash (purple)
	if _sprite:
		var tween = create_tween()
		tween.tween_property(_sprite, "modulate", Color(1.5, 0.8, 2.0, 1.0), 0.2)
		tween.tween_property(_sprite, "modulate", Color(0.8, 0.4, 1.0, 1.0), 0.2)
	
	# Spawn beam
	var BeamScript = load("res://scripts/enemies/effects/EnemyMarianBeam.gd")
	if BeamScript:
		_beam_instance = BeamScript.new()
		_beam_instance.owner_enemy = self
		_beam_instance.target_node = _player
		_beam_instance.duration = BEAM_DURATION
		_beam_instance.initial_direction = dir
		# Purple beam colors are set in EnemyMarianBeam
		
		get_parent().add_child(_beam_instance)
		_beam_instance.global_position = global_position + dir * 40

func _fire_bullet(dir: Vector2) -> void:
	var bs = BulletServer.get_instance()
	if not bs:
		return
	
	# Add aim error
	var fire_dir = dir.rotated(randf_range(-AIM_SPREAD, AIM_SPREAD))
	
	# Spawn purple-tinted bullet
	bs.spawn_colored_bullet(global_position + dir * 20, fire_dir * BULLET_SPEED, base_damage, self, PURPLE_TINT)

func _fire_rockets(dir: Vector2) -> void:
	if not is_instance_valid(_player):
		return
	
	# Fire 3 boss missiles with warning indicators and proper explosions
	var rocket_count := 3
	
	var BossMissileScript = load("res://scripts/enemies/BossMissile.gd")
	if not BossMissileScript:
		return
	
	for i in range(rocket_count):
		# Create BossMissile (has red warning circles and burning explosion)
		var missile = Area2D.new()
		missile.set_script(BossMissileScript)
		
		get_parent().add_child(missile)
		missile.global_position = global_position
		
		# Call proper initialization (player, delay, spread_index, total_missiles, damage)
		if missile.has_method("initialize"):
			missile.initialize(_player, 0.0, i, rocket_count, 10)
		
		# Set purple colors directly (modulate would multiply with red = dark)
		if "_trail_color" in missile:
			missile._trail_color = Color(0.7, 0.3, 1.0, 0.8)  # Purple trail
		if "_smoke_color" in missile:
			missile._smoke_color = Color(0.6, 0.4, 0.8, 0.85)  # Purple-ish smoke

func _update_hp_bar() -> void:
	if _hp_bar and _health_component:
		_hp_bar.max_value = _health_component.max_hp
		_hp_bar.value = _health_component.current_hp
	if _hp_label and _health_component:
		_hp_label.text = "%d/%d" % [_health_component.current_hp, _health_component.max_hp]

func _sync_hp_bar_position() -> void:
	# HP bar/label use top_level=true so they need manual position sync
	var bar_offset := Vector2(0, -60)  # Above the sprite
	if _hp_bar:
		_hp_bar.global_position = global_position + bar_offset - Vector2(40, 10)
	if _hp_label:
		_hp_label.global_position = global_position + bar_offset - Vector2(40, 12)

func _on_health_changed(_new_hp: int, _old_hp: int) -> void:
	_update_hp_bar()

func _on_death(overkill: int = 0) -> void:
	died.emit()
	
	# Disable physics/combat during death animation
	set_physics_process(false)
	set_process(false)
	
	# Stop any active beam
	if _beam_instance and is_instance_valid(_beam_instance):
		_beam_instance.queue_free()
		_beam_instance = null
	
	# Hide HP bar
	if _hp_bar: _hp_bar.hide()
	if _hp_label: _hp_label.hide()
	
	# Spawn reverse portal effect at our position
	var portal = Node2D.new()
	portal.set_script(_get_death_portal_script())
	portal.set("marian_ref", self)
	get_parent().add_child(portal)
	portal.global_position = global_position

func _get_death_portal_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var marian_ref: Node2D = null
var _time: float = 0.0
var _duration: float = 2.0
var _dissolve_start: float = 0.3  # When Marian starts dissolving
var _portal_close_start: float = 1.2  # When portal starts closing
var _original_scale: Vector2 = Vector2.ONE  # Store original scale

func _ready() -> void:
	z_index = 200
	# Capture original scale on ready
	if marian_ref and is_instance_valid(marian_ref):
		_original_scale = marian_ref.scale

func _process(delta: float) -> void:
	_time += delta
	
	# Dissolve Marian (fade out + shrink)
	if marian_ref and is_instance_valid(marian_ref):
		if _time > _dissolve_start:
			var dissolve_progress := clampf((_time - _dissolve_start) / 0.8, 0.0, 1.0)
			marian_ref.modulate.a = 1.0 - dissolve_progress
			# Shrink relative to original scale (1.0 down to 0.5)
			marian_ref.scale = _original_scale * (1.0 - dissolve_progress * 0.5)
			
			# Move Marian toward portal center
			marian_ref.global_position = lerp(marian_ref.global_position, global_position, delta * 3.0)
		
		# Queue free Marian when fully dissolved
		if _time > _dissolve_start + 0.9:
			marian_ref.queue_free()
			marian_ref = null
	
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	
	# Portal opens quickly, stays open, then closes
	var open_phase := clampf(progress * 4.0, 0.0, 1.0)  # Fast open
	var close_start := clampf((_time - _portal_close_start) / (_duration - _portal_close_start), 0.0, 1.0)
	
	var portal_scale := open_phase * (1.0 - close_start)
	var alpha := 1.0 - close_start * 0.8
	
	var portal_w := 100.0 * portal_scale
	var portal_h := 175.0 * portal_scale
	
	# Shimmering distortion effect - wavy oval portal
	var wave_offset := sin(_time * 8.0) * 5.0
	
	# Outer glow
	for i in range(5):
		var glow_alpha := alpha * 0.15 * (1.0 - float(i) * 0.15)
		var extra := float(i) * 8.0
		_draw_wavy_oval(portal_w + extra, portal_h + extra, Color(0.6, 0.2, 0.9, glow_alpha), wave_offset)
	
	# Portal core (darker center)
	_draw_wavy_oval(portal_w * 0.8, portal_h * 0.8, Color(0.1, 0.0, 0.2, alpha * 0.9), wave_offset)
	
	# Edge ring
	_draw_wavy_oval_ring(portal_w, portal_h, Color(0.9, 0.4, 1.0, alpha), wave_offset, 4.0)
	
	# Inner shimmer particles
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + _time * 3.0
		var r := portal_w * 0.6 * (0.7 + sin(_time * 5.0 + float(i)) * 0.3)
		var px: float = cos(angle) * r
		var py: float = sin(angle) * r * (portal_h / max(portal_w, 0.001))
		draw_circle(Vector2(px, py), 3.0, Color(1.0, 0.8, 1.0, alpha * 0.7))

func _draw_wavy_oval(w: float, h: float, color: Color, wave: float) -> void:
	if w <= 0 or h <= 0: return
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
		points.append(Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod))
	draw_colored_polygon(points, color)

func _draw_wavy_oval_ring(w: float, h: float, color: Color, wave: float, thickness: float) -> void:
	if w <= 0 or h <= 0: return
	var prev := Vector2.ZERO
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
		var pt := Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod)
		if i > 0:
			draw_line(prev, pt, color, thickness)
		prev = pt
"""
	script.reload()
	return script

func take_damage(amount: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, from_burst: bool = false, source: String = "") -> void:
	if _health_component and _health_component.has_method("damage"):
		_health_component.damage(amount, source)

func setup_sprite(texture: Texture2D, columns: int, rows: int) -> void:
	if not _sprite:
		return
	
	var frames := SpriteFrames.new()
	var directions: Array[String] = ["down", "left", "right", "up"]
	
	@warning_ignore("integer_division")
	var frame_width: int = texture.get_width() / columns
	@warning_ignore("integer_division")
	var frame_height: int = texture.get_height() / rows
	
	for row in range(rows):
		var anim_name: String = directions[row]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, 8.0)
		frames.set_animation_loop(anim_name, true)
		
		for col in range(columns):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			frames.add_frame(anim_name, atlas)
	
	_sprite.sprite_frames = frames
	_sprite.play("down")
