extends Node2D
class_name BossMissileExplosion

## AOE explosion from boss missile - damages player if in radius

const EXPLOSION_DURATION := 0.5
const RING_COUNT := 2 # Reduced from 3

var _radius := 150.0
var _damage := 2
var _player: Node2D = null
var _damage_dealt := false

# Static cached flash texture
static var _cached_flash_texture: Texture2D = null

# Visual elements
var _rings: Array[Node2D] = []

# Audio
const EXPLOSION_SFX = preload("res://assets/sounds/sfx/weapons/rocket/rocket_explosion.mp3")

func initialize(radius: float, damage: int, player: Node2D) -> void:
	_radius = radius
	_damage = damage
	_player = player

func _ready() -> void:
	# AUDIO PLAYBACK
	var audio = AudioStreamPlayer2D.new()
	audio.stream = EXPLOSION_SFX
	audio.bus = "Master" # Ensure audibility (SFX bus might be muted/missing?)
	audio.volume_db = -16.0 # Reduced from -12.0
	audio.max_distance = 6000.0 # Ensure it's heard
	add_child(audio)
	audio.play()
	
	_create_explosion_visuals()
	_check_damage()
	
	# Add to tree for cleanup
	# Wait for audio to finish
	var duration := EXPLOSION_DURATION
	if audio.stream:
		duration = max(duration, audio.stream.get_length())
	
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(queue_free)

func _create_explosion_visuals() -> void:
	# Create expanding rings (reduced count)
	for i in range(RING_COUNT):
		var ring := Node2D.new()
		ring.name = "Ring%d" % i
		ring.set_script(preload("res://scripts/effects/ExplosionRing.gd"))
		if ring.has_method("initialize"):
			var delay := i * 0.1
			var ring_color := Color(1.0, 0.3 - i * 0.1, 0.1, 0.7 - i * 0.2)
			ring.initialize(_radius, EXPLOSION_DURATION, delay, ring_color)
		add_child(ring)
		_rings.append(ring)
	
	# Central flash - use cached texture
	var flash := Sprite2D.new()
	flash.name = "Flash"
	if _cached_flash_texture == null:
		_cached_flash_texture = _create_flash_texture()
	flash.texture = _cached_flash_texture
	flash.scale = Vector2.ONE * (_radius / 32.0) * 0.5
	
	# Unshaded material for flash
	var flash_mat := CanvasItemMaterial.new()
	flash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	flash.material = flash_mat
	
	add_child(flash)
	
	# Animate flash fade
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, EXPLOSION_DURATION * 0.5)
	tween.tween_callback(flash.queue_free)

static func _create_flash_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in range(64):
		for y in range(64):
			var dist := Vector2(x - 32, y - 32).length() / 32.0
			if dist < 1.0:
				var alpha := (1.0 - dist) ** 2
				img.set_pixel(x, y, Color(1.0, 0.8, 0.4, alpha))
			else:
				img.set_pixel(x, y, Color.TRANSPARENT)
	return ImageTexture.create_from_image(img)

func _check_damage() -> void:
	if _damage_dealt:
		return
	
	_damage_dealt = true
	
	# Damage player if in radius
	if _player and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist <= _radius:
			if _player.has_method("take_damage"):
				_player.take_damage(_damage, false, Vector2.ZERO, false, "Boss:Missile")
	
	# Damage charmed allies if in radius (they're fighting for the player)
	var tree := get_tree()
	if tree:
		var charmed_allies := tree.get_nodes_in_group("charmed_allies")
		for ally in charmed_allies:
			if not is_instance_valid(ally) or not ally is Node2D:
				continue
			var dist := global_position.distance_to((ally as Node2D).global_position)
			if dist <= _radius:
				if ally.has_method("take_damage"):
					ally.take_damage(_damage)
