extends Node2D
class_name ScarletBloodDecal
## A small splatter of blood left on the ground by a bleeding (Eviscerate) enemy.
## Fades out over its lifetime, then frees itself.
##
## A static, FIFO cap bounds how many decals exist at once for performance: when
## the cap is reached, the oldest decal is removed before a new one spawns. They
## still read as a continuous "trail of blood" because they're spawned densely.

const MAX_ON_SCREEN := 44
const LIFETIME := 4.5
const FADE_START := 0.55 # fraction of life before alpha starts dropping

static var _active: Array = []

var _age: float = 0.0
var _blobs: Array = [] # [{offset:Vector2, radius:float, color:Color}]
var _alpha: float = 1.0


## Spawn a decal under `parent` at world `pos`, enforcing the global cap.
static func spawn(parent: Node, pos: Vector2) -> ScarletBloodDecal:
	if parent == null or not is_instance_valid(parent):
		return null
	# Prune dead references, then retire oldest until under the cap.
	_active = _active.filter(func(d): return is_instance_valid(d))
	while _active.size() >= MAX_ON_SCREEN:
		var oldest = _active.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var decal := ScarletBloodDecal.new()
	parent.add_child(decal)
	decal.global_position = pos
	_active.append(decal)
	return decal


func _ready() -> void:
	# Sit beneath enemies/player so it reads as ground splatter.
	z_as_relative = false
	z_index = -5
	# Unshaded so the blood still shows on dark/night ground.
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

	# Build a small irregular cluster of blobs once.
	var count := randi_range(3, 5)
	for i in range(count):
		var ang := randf() * TAU
		var dist := randf() * 14.0
		_blobs.append({
			"offset": Vector2(cos(ang), sin(ang)) * dist,
			"radius": randf_range(5.0, 11.0),
			"color": Color(randf_range(0.55, 0.8), randf_range(0.02, 0.08), randf_range(0.04, 0.1), 1.0)
		})
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var t := _age / LIFETIME
	if t > FADE_START:
		_alpha = 1.0 - (t - FADE_START) / (1.0 - FADE_START)
	else:
		_alpha = 1.0
	queue_redraw()


func _draw() -> void:
	for blob in _blobs:
		var c: Color = blob["color"]
		c.a *= _alpha * 0.85
		draw_circle(blob["offset"], blob["radius"], c)


func _exit_tree() -> void:
	_active.erase(self)
