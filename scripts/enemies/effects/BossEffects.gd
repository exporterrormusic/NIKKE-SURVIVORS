extends Node2D
class_name BossEffects

## Visual effects for Boss enemies: shadow only

var _enemy: Node2D = null
var _shadow: Node2D = null

func _ready() -> void:
	_enemy = get_parent()
	_setup_shadow()
	# Delay HP bar color setup to ensure ProgressBar is ready
	call_deferred("_setup_hp_bar_color")
	_play_growl_sound()
	_trigger_boss_shake()
	z_index = -1

func _setup_hp_bar_color() -> void:
	# Make boss HP bar purple to match the screen bar
	if _enemy and _enemy.has_node("ProgressBar"):
		var hp_bar: ProgressBar = _enemy.get_node("ProgressBar")
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = Color(0.7, 0.2, 0.9, 1.0)  # Purple (matches BossHealthBar)
		hp_bar.add_theme_stylebox_override("fill", fill_style)

func _play_growl_sound() -> void:
	# Play growl sound on spawn
	var growl_path := "res://assets/enemies/rapture-basic/growl.mp3"
	if ResourceLoader.exists(growl_path):
		var audio := AudioStreamPlayer.new()
		audio.stream = load(growl_path)
		audio.volume_db = -5.0
		audio.bus = "SFX"
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)

func _setup_shadow() -> void:
	# Shadow under boss - positioned at sprite's feet
	_shadow = Node2D.new()
	_shadow.name = "BossShadow"
	_shadow.z_index = -10
	_shadow.set_script(preload("res://scripts/enemies/effects/visuals/EnemyShadowVisual.gd"))
	_shadow.set("shadow_radius", 25.0) # Bosses cast a larger shadow
	add_child(_shadow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()


func _trigger_boss_shake() -> void:
	# Dramatic camera shake when boss spawns
	var CombatJuice = load("res://scripts/systems/CombatJuice.gd")
	if CombatJuice and CombatJuice.instance:
		CombatJuice.camera_shake(20.0)  # Strong shake for boss entrance

