# Shared enemy drop-shadow (extracted from embedded sources in BossEffects,
# EliteEffects and TankEffects; identical except radius/alpha/offset).
extends Node2D

var shadow_radius: float = 20.0
var shadow_alpha: float = 0.35
var default_feet_offset: float = 18.0

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Get sprite size to position shadow at feet
	var parent := get_parent().get_parent()
	var sprite = parent.get_node_or_null("AnimatedSprite2D") if parent else null
	var feet_offset: float = default_feet_offset
	if sprite and sprite.sprite_frames:
		var anim = sprite.animation
		if sprite.sprite_frames.has_animation(anim) and sprite.sprite_frames.get_frame_count(anim) > 0:
			var tex = sprite.sprite_frames.get_frame_texture(anim, 0)
			if tex:
				feet_offset = tex.get_height() * sprite.scale.y * 0.4

	var shadow_color := Color(0.0, 0.0, 0.0, shadow_alpha)
	draw_set_transform(Vector2(0, feet_offset), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, shadow_radius, shadow_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
