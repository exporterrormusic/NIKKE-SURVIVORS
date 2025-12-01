extends CharacterBody2D

@export var speed = 400
@export var dash_speed = 800
@export var dash_duration = 0.3
@export var acceleration = 6000
@export var friction = 5000
@export var momentum_duration = 0.1
@export var stamina = 100.0
@export var max_stamina = 100.0
@export var stamina_regen = 20.0
@export var dash_stamina_cost = 20.0
@export var boost_duration = 0.1
@export var attack_stamina_cost = 10.0
@export var boost_multiplier = 1.2
@export var attack_cooldown = 0.3

@export var running_speed_multiplier = 1.5
@export var running_stamina_drain = 20.0
@export var dash_press_grace = 0.12
@export var debug_movement = false

@onready var stamina_bar = $"../CanvasLayer/StaminaUI/ProgressBar"
@onready var hp_bar = $HPBar
@onready var xp_bar = $"../CanvasLayer/XPUI/ProgressBar"

var attack_timer = 0.0
var dashing = false
var dash_direction = Vector2.ZERO
var dash_timer = 0.0
var invincible = false
var momentum_timer = 0.0
var boost_timer = 0.0
var previous_dash_direction = Vector2.ZERO
var wants_running = false
var _dash_press_timer = 0.0
var running = false
@export var scarlet_special_unlocked = false
@export var rapunzel_special_unlocked = false
var current_character = 0
var character_textures = []
var hp = 10
var max_hp = 10
var xp = 0
var level = 1
var xp_to_next = 100

func _ready():
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	update_xp_bar()
	character_textures = [
		load("res://scarlet.png"),
		load("res://snowwhite.png"),
		load("res://rapunzel.png")
	]
	update_sprite()

func update_sprite():
	$Sprite2D.texture = character_textures[current_character]

func take_damage(dmg):
	if invincible:
		return
	hp -= dmg
	hp_bar.value = hp
	if hp <= 0:
		# game over or something
		pass

func heal(amount: int):
	hp = min(hp + amount, max_hp)
	hp_bar.value = hp

func add_xp(amount):
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.2)
	update_xp_bar()

func update_xp_bar():
	xp_bar.max_value = xp_to_next
	xp_bar.value = xp

func _process(delta):
	# Running drains stamina (no simultaneous regen). Otherwise regen.
	if running and not dashing:
		stamina = max(stamina - running_stamina_drain * delta, 0)
		stamina_bar.value = stamina
		if stamina <= 0:
			running = false
			momentum_timer = momentum_duration
	else:
		stamina = min(stamina + stamina_regen * delta, max_stamina)
		stamina_bar.value = stamina

func _physics_process(_delta):
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()

	if attack_timer > 0:
		attack_timer -= _delta

	if Input.is_action_just_pressed("attack") and attack_timer <= 0 and stamina >= attack_stamina_cost:
		stamina -= attack_stamina_cost
		if current_character == 0:  # Scarlet
			var slash_scene = preload("res://scenes/effects/Slash.tscn")
			var slash = slash_scene.instantiate()
			add_child(slash)
			var mouse_pos = get_global_mouse_position()
			var direction = (mouse_pos - global_position).normalized()
			slash.position = direction * 50
			slash.rotation = direction.angle()
		elif current_character == 1:  # Snow White
			var bullet_scene = preload("res://scenes/effects/Bullet.tscn")
			var bullet = bullet_scene.instantiate()
			get_parent().add_child(bullet)
			var mouse_pos = get_global_mouse_position()
			var direction = (mouse_pos - global_position).normalized()
			bullet.global_position = global_position + direction * 50
			bullet.rotation = direction.angle()
			bullet.velocity = direction * 3000
		elif current_character == 2:  # Rapunzel
			var missile_scene = preload("res://scenes/effects/Missile.tscn")
			var missile = missile_scene.instantiate()
			get_parent().add_child(missile)
			var mouse_pos = get_global_mouse_position()
			var direction = (mouse_pos - global_position).normalized()
			missile.global_position = global_position + direction * 60
			missile.target_pos = mouse_pos
			missile.velocity = direction * 100
		attack_timer = attack_cooldown

	if Input.is_action_just_pressed("thrust") and attack_timer <= 0 and stamina >= attack_stamina_cost:
		stamina -= attack_stamina_cost
		if current_character == 0:  # Scarlet
			var thrust_scene = preload("res://scenes/effects/Thrust.tscn")
			var thrust = thrust_scene.instantiate()
			add_child(thrust)
			var mouse_pos = get_global_mouse_position()
			var direction = (mouse_pos - global_position).normalized()
			thrust.position = direction * 50
			thrust.rotation = direction.angle()
		elif current_character == 1:  # Snow White
			var turret_count = 0
			for child in get_parent().get_children():
				if child is Node2D and child.has_method("shoot"):  # assuming turret has shoot method
					turret_count += 1
			if turret_count < 3:
				var turret_scene = preload("res://scenes/effects/Turret.tscn")
				var turret = turret_scene.instantiate()
				get_parent().add_child(turret)
				turret.global_position = global_position + Vector2(100, 0)
		elif current_character == 2:  # Rapunzel
			if rapunzel_special_unlocked:
				var cross_scene = load("res://scenes/effects/HealingCross.tscn")
				if cross_scene:
					var cross = cross_scene.instantiate()
					get_parent().add_child(cross)
					var mouse_pos = get_global_mouse_position()
					var direction = (mouse_pos - global_position).normalized()
					cross.global_position = global_position + direction * 60
		attack_timer = attack_cooldown

	# Update dash press grace timer
	if _dash_press_timer > 0.0:
		_dash_press_timer -= _delta

	if Input.is_action_just_pressed("dash") and input_vector != Vector2.ZERO and not dashing and stamina >= dash_stamina_cost:
		stamina -= dash_stamina_cost
		dashing = true
		dash_direction = input_vector
		previous_dash_direction = dash_direction
		_dash_press_timer = dash_press_grace
		wants_running = Input.is_action_pressed("dash")
		# Scarlet special: if unlocked make dash twice as long and spawn wave
		if current_character == 0 and scarlet_special_unlocked:
			dash_timer = dash_duration * 2.0
			var wave_scene = load("res://scenes/effects/ScarletWave.tscn")
			if wave_scene:
				var w = wave_scene.instantiate()
				# orient the wave to face the dash direction so the collision box
				# and visual line up with the player's facing direction
				w.rotation = dash_direction.angle()
				w.owner_node = self
				w.pierce_all = true
				w.damage = 8
				get_parent().add_child(w)
				w.global_position = global_position + dash_direction * 36
				w.velocity = dash_direction.normalized() * 2400
		else:
			dash_timer = dash_duration
		invincible = true

	if dashing:
		# track intent to keep running when dash finishes
		wants_running = Input.is_action_pressed("dash") or _dash_press_timer > 0.0
		if input_vector != Vector2.ZERO:
			if dash_direction != input_vector.normalized():
				boost_timer = boost_duration
			dash_direction = input_vector.normalized()
		var current_dash_speed = dash_speed
		if boost_timer > 0:
			current_dash_speed *= boost_multiplier
			boost_timer -= _delta
		velocity = dash_direction * current_dash_speed
		# Scarlet special: damage during dash should be handled by a short-lived
		# Area2D hitbox (ScarletDashHitbox) or the forward ScarletWave.
		# Removed per-tick scans for performance.
		dash_timer -= _delta
		if dash_timer <= 0:
			dashing = false
			invincible = false
			# If player is holding dash (or tapped recently) and is providing
			# movement input, enter running and apply an immediate running
			# velocity so the speed increase is visible.
			if (wants_running or _dash_press_timer > 0.0) and input_vector != Vector2.ZERO:
				running = true
				velocity = input_vector.normalized() * speed * running_speed_multiplier
				if debug_movement:
					print("[SC.Player] TRANSITION -> running (stamina=", stamina, ", velocity=", velocity, ")")
			else:
				if running:
					if not Input.is_action_pressed("dash") or stamina <= 0:
						running = false
						momentum_timer = momentum_duration
				momentum_timer = momentum_duration
				velocity = dash_direction * (dash_speed * 0.3)
	else:
		if momentum_timer > 0:
			momentum_timer -= _delta
		else:
			var desired_speed = speed * (running_speed_multiplier if running else 1.0)
			var target_velocity = input_vector * desired_speed
			if input_vector == Vector2.ZERO:
				velocity = velocity.move_toward(Vector2.ZERO, friction * _delta)
			else:
				velocity = velocity.move_toward(target_velocity, acceleration * _delta)

	move_and_slide()

	if dashing and is_on_wall():
		dash_direction = dash_direction.bounce(get_wall_normal())

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == 4:  # wheel up
			current_character = (current_character + 1) % 3
			update_sprite()
		elif event.button_index == 5:  # wheel down
			current_character = (current_character - 1 + 3) % 3
			update_sprite()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			current_character = 0
			update_sprite()
		elif event.keycode == KEY_2:
			current_character = 1
			update_sprite()
		elif event.keycode == KEY_3:
			current_character = 2
			update_sprite()
