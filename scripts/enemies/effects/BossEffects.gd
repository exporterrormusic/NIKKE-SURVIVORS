extends Node2D
class_name BossEffects

## Visual effects for Boss enemies: shadow only

var _enemy: Node2D = null
var _shadow: Node2D = null

func _ready() -> void:
	_enemy = get_parent()
	_setup_shadow()
	_setup_hp_bar_color()
	_play_growl_sound()
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
	var script := GDScript.new()
	script.source_code = """
extends Node2D

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Get sprite size to position shadow at feet
	var parent := get_parent().get_parent()
	var sprite = parent.get_node_or_null("AnimatedSprite2D") if parent else null
	var feet_offset: float = 18.0  # Default
	if sprite and sprite.sprite_frames:
		var anim = sprite.animation
		if sprite.sprite_frames.has_animation(anim) and sprite.sprite_frames.get_frame_count(anim) > 0:
			var tex = sprite.sprite_frames.get_frame_texture(anim, 0)
			if tex:
				feet_offset = tex.get_height() * sprite.scale.y * 0.4
	
	var shadow_color := Color(0.0, 0.0, 0.0, 0.35)
	draw_set_transform(Vector2(0, feet_offset), 0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, 25.0, shadow_color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
"""
	script.reload()
	_shadow.set_script(script)
	add_child(_shadow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()
