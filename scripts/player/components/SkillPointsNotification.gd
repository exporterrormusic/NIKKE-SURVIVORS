extends Control
class_name SkillPointsNotification
## Skill points available notification UI.
## Extracted from PlayerCore for separation of concerns.
##
## Shows a golden-bordered panel with "SKILL POINTS AVAILABLE" text
## when the player has unspent skill points. Pulses with an animation.

const UI := preload("res://scripts/ui/UITheme.gd")


func show_notification(points: int) -> void:
	"""Show or hide the notification based on available points.
	   Pass -1 to force hide (e.g. when talent tree opens)."""
	if points <= 0:
		visible = false
		# Kill pulse animation
		if has_meta("pulse_tween"):
			var tween = get_meta("pulse_tween")
			if tween and is_instance_valid(tween):
				tween.kill()
		return
	
	# Update text
	var main_label: Label = get_node_or_null("Background/MainLabel")
	if main_label:
		main_label.text = "SKILL POINTS AVAILABLE × %d" % points
	
	visible = true
	_animate_pulse()


func _animate_pulse() -> void:
	"""Pulse animation for the notification."""
	if has_meta("pulse_tween"):
		var old_tween = get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()
	
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	set_meta("pulse_tween", tween)


## Factory method: creates a fully configured SkillPointsNotification instance.
static func create(parent: Node, position_offset: Vector2 = Vector2(35, 200)) -> SkillPointsNotification:
	var container := SkillPointsNotification.new()
	container.name = "SkillPointsNotify"
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position = position_offset
	container.size = Vector2(240, 48)
	container.pivot_offset = Vector2(120, 24)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = false
	
	# Background panel with golden border
	var bg := Panel.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	bg_style.border_color = Color(1.0, 0.85, 0.2, 1.0)
	bg_style.set_border_width_all(3)
	bg_style.set_corner_radius_all(6)
	bg_style.shadow_color = Color(1.0, 0.75, 0.0, 0.5)
	bg_style.shadow_size = 5
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)
	
	# Main label
	var main_label := Label.new()
	main_label.name = "MainLabel"
	main_label.text = "SKILL POINTS AVAILABLE × 1"
	main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_label.add_theme_font_size_override("font_size", 16)
	main_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	main_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	main_label.add_theme_constant_override("shadow_offset_x", 1)
	main_label.add_theme_constant_override("shadow_offset_y", 1)
	main_label.position = Vector2(0, 4)
	main_label.size = Vector2(240, 24)
	container.add_child(main_label)
	
	# Sub label
	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = "PRESS TAB TO OPEN SKILL TREE"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 9)
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.85))
	sub_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	sub_label.add_theme_constant_override("shadow_offset_x", 1)
	sub_label.add_theme_constant_override("shadow_offset_y", 1)
	sub_label.position = Vector2(0, 28)
	sub_label.size = Vector2(240, 16)
	container.add_child(sub_label)
	
	parent.add_child(container)
	return container
