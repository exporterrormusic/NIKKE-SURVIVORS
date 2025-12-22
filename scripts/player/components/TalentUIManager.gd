extends Node
class_name TalentUIManager
## Manages talent tree UI and skill point notifications.
## Extracted from PlayerCore for modularity.

signal talent_tree_opened
signal talent_tree_closed
signal talent_unlocked(char_id: int, talent_id: String)

## Reference to player
var _player: Node = null

## Skill points notification UI
var _skill_points_notify: Control = null

## Whether talent tree is currently open
var is_open: bool = false


func initialize(player: Node) -> void:
	_player = player


func show_talent_tree(add_point: bool = false) -> void:
	"""Open the talent tree UI."""
	var canvas := _get_canvas()
	if canvas == null:
		return
	
	# Hide notification while tree is open
	if _skill_points_notify and is_instance_valid(_skill_points_notify):
		_skill_points_notify.visible = false
	
	# Check if tree already exists
	var existing := canvas.get_node_or_null("TalentTree")
	if existing:
		if add_point and existing.has_method("add_skill_points"):
			existing.add_skill_points(1)
		return
	
	# Create talent tree
	var TalentTreeScript = load("res://scripts/ui/TalentTree.gd")
	var tree := Control.new()
	tree.set_script(TalentTreeScript)
	tree.name = "TalentTree"
	tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.offset_left = 0.0
	tree.offset_top = 0.0
	tree.offset_right = 0.0
	tree.offset_bottom = 0.0
	
	canvas.add_child(tree)
	
	# Connect signals
	tree.talent_unlocked.connect(_on_talent_unlocked)
	tree.tree_closed.connect(_on_tree_closed)
	
	if add_point and tree.has_method("add_skill_points"):
		tree.add_skill_points(1)
	
	# Pass player reference
	if tree.has_method("show_tree"):
		tree.show_tree(_player)
	
	is_open = true
	talent_tree_opened.emit()
	
	# Pause game
	if _player and _player.get_parent().has_method("set_game_paused"):
		_player.get_parent().call_deferred("set_game_paused", true)


func update_skill_points_notification(points: int) -> void:
	"""Show/hide/update the skill points notification."""
	var canvas := _get_canvas()
	if canvas == null:
		return
	
	# Hide if no points
	if points <= 0:
		if _skill_points_notify and is_instance_valid(_skill_points_notify):
			_skill_points_notify.visible = false
		return
	
	# Create notification if needed
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		_skill_points_notify = _create_notification()
		canvas.add_child(_skill_points_notify)
	
	# Update text and show
	var main_label: Label = _skill_points_notify.get_node_or_null("MainLabel")
	if main_label:
		main_label.text = "SKILL POINTS AVAILABLE × %d" % points
	_skill_points_notify.visible = true
	
	# Animate pulse
	_animate_notification()


func _get_canvas() -> Node:
	if not _player:
		return null
	var canvas := _player.get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = _player.get_tree().root
	return canvas


func _on_talent_unlocked(char_id: int, talent_id: String) -> void:
	talent_unlocked.emit(char_id, talent_id)


func _on_tree_closed() -> void:
	is_open = false
	talent_tree_closed.emit()
	
	# Unpause game
	if _player and _player.get_parent().has_method("set_game_paused"):
		_player.get_parent().call_deferred("set_game_paused", false)
	
	# Update notification
	var tree := _get_canvas().get_node_or_null("TalentTree") if _get_canvas() else null
	if tree and tree.has_method("get_skill_points"):
		update_skill_points_notification(tree.get_skill_points())


func _create_notification() -> Control:
	var container := Control.new()
	container.name = "SkillPointsNotify"
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position = Vector2(35, 200)
	container.size = Vector2(240, 48)
	container.pivot_offset = Vector2(120, 24)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background panel
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
	sub_label.text = "PRESS TAB OR [Select] TO OPEN SKILL TREE"
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
	
	return container


func _animate_notification() -> void:
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		return
	
	# Kill existing tween
	if _skill_points_notify.has_meta("pulse_tween"):
		var old_tween = _skill_points_notify.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()
	
	# Pulse animation
	var tween := _player.create_tween() if _player else null
	if tween:
		tween.set_loops()
		tween.tween_property(_skill_points_notify, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_skill_points_notify, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_skill_points_notify.set_meta("pulse_tween", tween)
