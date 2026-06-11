extends Node2D
class_name EliteEffects

## Visual effects for Elite enemies: shadow only

var _enemy: Node2D = null
var _shadow: Node2D = null

func _ready() -> void:
	_enemy = get_parent()
	_setup_shadow()
	# Delay HP bar color setup to ensure ProgressBar is ready
	call_deferred("_setup_hp_bar_color")
	_play_growl_sound()
	z_index = -1

func _play_growl_sound() -> void:
	# Play growl sound on spawn
	var growl_path := "res://assets/enemies/rapture-basic/growl.mp3"
	if ResourceLoader.exists(growl_path):
		var audio := AudioStreamPlayer.new()
		audio.stream = load(growl_path)
		audio.volume_db = -8.0  # Slightly quieter for elite
		audio.bus = "SFX"
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)

func _setup_hp_bar_color() -> void:
	# Make elite HP bar red
	if _enemy and _enemy.has_node("ProgressBar"):
		var hp_bar: ProgressBar = _enemy.get_node("ProgressBar")
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = Color(0.9, 0.2, 0.2, 1.0)  # Red
		hp_bar.add_theme_stylebox_override("fill", fill_style)

func _setup_shadow() -> void:
	# Shadow underneath elite - positioned at sprite feet
	_shadow = Node2D.new()
	_shadow.name = "EliteShadow"
	_shadow.z_index = -3
	_shadow.set_script(preload("res://scripts/enemies/effects/visuals/EnemyShadowVisual.gd"))
	add_child(_shadow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()
