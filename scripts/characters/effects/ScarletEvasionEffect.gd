extends Node
class_name ScarletEvasionEffect
## Applies the slanted red scanline shader to Scarlet's sprite while she is
## invincible from Dodge (during/after a dash) or Evasion (after a parry).
##
## Refreshable: call refresh(duration) to (re)start or extend the effect. The
## original sprite material is restored when the timer runs out, and on free.

const SHADER := preload("res://resources/shaders/evasion_scanline.gdshader")


## Force the GPU to compile the evasion shader ahead of time by rendering it on a
## tiny near-invisible quad for a few frames. Without this, the FIRST Dodge/Evasion
## of a run hitches while the shader compiles. Call once at run start.
static func warm(host: Node) -> void:
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	var quad := Sprite2D.new()
	quad.name = "EvasionShaderWarm"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	quad.texture = ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	quad.material = mat
	quad.self_modulate.a = 0.004 # invisible to the eye, still rendered
	quad.z_index = -2000
	host.add_child(quad)
	host.get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(quad):
			quad.queue_free())


var _sprite: CanvasItem = null
var _orig_material: Material = null
var _mat: ShaderMaterial = null
var _remaining: float = 0.0
var _time: float = 0.0
var _applied: bool = false


## Bind the sprite this effect drives. Call once right after creation.
func setup(sprite: CanvasItem) -> void:
	_sprite = sprite


## Start the effect (if idle) or extend it to at least `duration` seconds.
func refresh(duration: float) -> void:
	if duration <= 0.0:
		return
	_remaining = maxf(_remaining, duration)
	if not _applied:
		_apply()


func _apply() -> void:
	if not is_instance_valid(_sprite):
		queue_free()
		return
	_orig_material = _sprite.material
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_sprite.material = _mat
	_applied = true


func _process(delta: float) -> void:
	if not _applied:
		return
	_time += delta
	if is_instance_valid(_sprite) and _mat:
		_mat.set_shader_parameter("time", _time)
	_remaining -= delta
	if _remaining <= 0.0:
		_restore()


func _restore() -> void:
	# Only restore if our material is still the one in place (avoid clobbering a
	# material some other effect swapped in while we were active).
	if is_instance_valid(_sprite) and _sprite.material == _mat:
		_sprite.material = _orig_material
	queue_free()


func _exit_tree() -> void:
	if _applied and is_instance_valid(_sprite) and _sprite.material == _mat:
		_sprite.material = _orig_material
