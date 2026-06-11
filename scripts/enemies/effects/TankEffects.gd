extends Node2D
class_name TankEffects

## Visual effects for Tank enemies: shadow only

var _enemy: Node2D = null
var _shadow: Node2D = null

func _ready() -> void:
	_enemy = get_parent()
	_setup_shadow()
	# Delay HP bar color setup to ensure ProgressBar is ready
	call_deferred("_setup_hp_bar_color")
	z_index = -1

func _setup_hp_bar_color() -> void:
	# Make tank HP bar dark reddish-orange
	if _enemy and _enemy.has_node("ProgressBar"):
		var hp_bar: ProgressBar = _enemy.get_node("ProgressBar")
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = Color(0.85, 0.35, 0.15, 1.0)  # Dark reddish-orange
		hp_bar.add_theme_stylebox_override("fill", fill_style)

func _setup_shadow() -> void:
	# Shadow underneath tank - positioned at sprite feet
	_shadow = Node2D.new()
	_shadow.name = "TankShadow"
	_shadow.z_index = -3
	_shadow.set_script(preload("res://scripts/enemies/effects/visuals/EnemyShadowVisual.gd"))
	_shadow.set("shadow_radius", 28.0)
	_shadow.set("shadow_alpha", 0.4)
	_shadow.set("default_feet_offset", 20.0)
	add_child(_shadow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()
