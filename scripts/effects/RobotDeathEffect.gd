extends Node2D
class_name RobotDeathEffect

# SHADER-OPTIMIZED Robot destruction effect
# - Single pass GPU explosion
# - Zero CPU particle overhead
# - Dramatic cinematic visuals

const EXPLO_SHADER = preload("res://resources/shaders/death_explosion.gdshader")

var _age := 0.0
var _duration := 0.7 # Slightly longer to show rich shader details
var _rect: ColorRect = null
var _tween: Tween = null
var _is_overkill := false

func set_overkill(is_overkill: bool) -> void:
	_is_overkill = is_overkill

func reset() -> void:
	_age = 0.0
	visible = true
	if _rect:
		_rect.material.set_shader_parameter("progress", 0.0)
	
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_rect.material, "shader_parameter/progress", 1.0, _duration)
	_tween.finished.connect(_on_finished)
	
	# Scale based on overkill
	_rect.scale = Vector2.ONE * (1.2 if _is_overkill else 0.8)

func _on_finished() -> void:
	ProjectileCache.return_to_pool(self)

func _ready() -> void:
	z_index = 100
	
	# Create the shader rect
	_rect = ColorRect.new()
	_rect.size = Vector2(120, 120)
	_rect.pivot_offset = Vector2(60, 60)
	_rect.position = Vector2(-60, -60)
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var mat = ShaderMaterial.new()
	mat.shader = EXPLO_SHADER
	_rect.material = mat
	
	add_child(_rect)
	reset()

# Performance Note: _process and _draw are no longer needed
# Shaders and Tweens handle all visuals on the GPU/Engine level
