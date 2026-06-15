extends Node2D
class_name ScarletCrashout
## D1 Crashout: after Scarlet's burst, enemies (and their bullets) stay frozen via
## GameManager.enemy_time_scale = 0 while Scarlet runs at normal speed (the game is
## NOT paused). Keeps the burst's grayscale "time-stop" look, with Scarlet elevated
## above the filter so she stays in colour. Restores everything after DURATION.

const DURATION := 3.0
const FILTER_Z := 50
const PLAYER_Z := 200

var _gm: Node = null
var _prev_time_scale: float = 1.0
var _filter: ColorRect = null
var _player: Node2D = null
var _player_prev_z: int = 0
var _player_prev_z_rel: bool = true
var _age: float = 0.0
var _running: bool = false


func start(player: Node2D) -> void:
	_player = player
	_gm = get_node_or_null("/root/GameManager")
	if _gm:
		_prev_time_scale = _gm.enemy_time_scale
		_gm.enemy_time_scale = 0.0
	# Elevate Scarlet above the grayscale filter so she stays in colour.
	if is_instance_valid(_player):
		_player_prev_z = _player.z_index
		_player_prev_z_rel = _player.z_as_relative
		_player.z_as_relative = false
		_player.z_index = PLAYER_Z
	_create_filter()
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_reposition_filter()
	_age += delta
	if _age >= DURATION:
		_finish()


func _create_filter() -> void:
	_filter = ColorRect.new()
	_filter.color = Color.WHITE
	_filter.z_as_relative = false
	_filter.z_index = FILTER_Z
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap; void fragment() { vec4 bg = texture(screen_texture, SCREEN_UV); float g = dot(bg.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(g, g, g, bg.a); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_filter.material = mat
	add_child(_filter)
	_reposition_filter()


func _reposition_filter() -> void:
	if not is_instance_valid(_filter):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	var zoom: Vector2 = cam.zoom if cam else Vector2.ONE
	var size: Vector2 = vp.get_visible_rect().size / zoom
	_filter.size = size * 2.0
	var center: Vector2 = cam.global_position if cam else global_position
	_filter.global_position = center - _filter.size / 2.0


func _finish() -> void:
	_running = false
	_restore()
	queue_free()


func _restore() -> void:
	if _gm:
		_gm.enemy_time_scale = _prev_time_scale
	if is_instance_valid(_filter):
		_filter.queue_free()
		_filter = null
	if is_instance_valid(_player):
		_player.z_index = _player_prev_z
		_player.z_as_relative = _player_prev_z_rel


func _notification(what: int) -> void:
	# Safety: if forcibly freed mid-run, make sure the freeze is lifted.
	if what == NOTIFICATION_PREDELETE and _running:
		_restore()
