extends Node
class_name EnemyHUD
## Manages enemy HP bar, shield bar, and label visuals.
##
## Extracted from ModularEnemy.gd to reduce its size and isolate HUD concerns.
## - Owns the static StyleBox pool shared across all enemies.
## - Creates and positions the shield bar node.
## - Syncs bar positions each frame based on enemy global_position/scale.
## - Applies unshaded materials so bars stay visible at night.

# ── References (set by setup()) ──────────────────────────────────────────
var hp_bar: ProgressBar
var hp_label: Label
var shield_bar: ProgressBar
var shield_label: Label

var _enemy: Node2D

# ── Static StyleBox pool (shared across all enemies) ─────────────────────
static var _style_green: StyleBoxFlat = null
static var _style_red: StyleBoxFlat = null
static var _style_yellow: StyleBoxFlat = null
static var _style_boss_red: StyleBoxFlat = null
static var _style_elite_red: StyleBoxFlat = null
static var _style_bg: StyleBoxFlat = null

static func _ensure_styles_initialized() -> void:
	if _style_green == null:
		_style_green = StyleBoxFlat.new()
		_style_green.bg_color = Color(0, 1, 0)
	if _style_red == null:
		_style_red = StyleBoxFlat.new()
		_style_red.bg_color = Color(1.0, 0.2, 0.2)
	if _style_yellow == null:
		_style_yellow = StyleBoxFlat.new()
		_style_yellow.bg_color = Color(0.95, 0.85, 0.2)
	if _style_boss_red == null:
		_style_boss_red = StyleBoxFlat.new()
		_style_boss_red.bg_color = Color(0.9, 0.0, 0.0)
	if _style_elite_red == null:
		_style_elite_red = StyleBoxFlat.new()
		_style_elite_red.bg_color = Color(0.8, 0.1, 0.1)
	if _style_bg == null:
		_style_bg = StyleBoxFlat.new()
		_style_bg.bg_color = Color(0.2, 0.2, 0.2)

static func cleanup_style_pool() -> void:
	_style_green = null
	_style_red = null
	_style_yellow = null
	_style_boss_red = null
	_style_elite_red = null
	_style_bg = null

# ── Cached font / scale state ────────────────────────────────────────────
var _cached_font_size: int = -1
var _prev_scale_x: float = 0.0

# ── Initialization ───────────────────────────────────────────────────────
func setup(enemy: Node2D, bar: ProgressBar, label: Label,
		is_exploder: bool, is_tank: bool, is_boss: bool,
		is_super_boss: bool, is_elite: bool) -> void:
	_enemy = enemy
	hp_bar = bar
	hp_label = label

	_ensure_styles_initialized()
	_make_unshaded(hp_bar)
	_make_unshaded(hp_label)

	# Apply fill style based on tier
	hp_bar.add_theme_stylebox_override("background", _style_bg)
	if is_exploder:
		hp_bar.add_theme_stylebox_override("fill", _style_red)
	elif is_tank:
		hp_bar.add_theme_stylebox_override("fill", _style_yellow)
	elif is_boss or is_super_boss:
		hp_bar.add_theme_stylebox_override("fill", _style_boss_red)
	elif is_elite:
		hp_bar.add_theme_stylebox_override("fill", _style_elite_red)
	else:
		hp_bar.add_theme_stylebox_override("fill", _style_green)

	# Create shield bar (added as child of the enemy so it lives beside hp_bar)
	_ensure_shield_bar_exists()

# ── Shield bar creation ──────────────────────────────────────────────────
func _ensure_shield_bar_exists() -> void:
	if shield_bar:
		return

	shield_bar = ProgressBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.show_percentage = false
	shield_bar.size = Vector2(50, 6)
	shield_bar.z_index = 51

	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0.2, 0.8, 1.0) # Cyan
	shield_bar.add_theme_stylebox_override("fill", sb_style)
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.5)
	shield_bar.add_theme_stylebox_override("background", sb_bg)
	_enemy.add_child(shield_bar)
	shield_bar.visible = false
	_make_unshaded(shield_bar)

	shield_label = Label.new()
	shield_label.name = "ShieldLabel"
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shield_label.add_theme_font_size_override("font_size", 10)
	shield_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	shield_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	shield_label.add_theme_constant_override("outline_size", 4)
	shield_label.z_index = 52
	_enemy.add_child(shield_label)
	shield_label.visible = false
	_make_unshaded(shield_label)

# ── Unshaded helper ──────────────────────────────────────────────────────
func _make_unshaded(node: CanvasItem) -> void:
	if not node:
		return
	node.top_level = true
	node.light_mask = 0
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	node.material = mat

# ── Health update (event-driven, from signal) ───────────────────────────
func update_health(current: int, max_hp: int) -> void:
	if hp_bar:
		hp_bar.value = current
	if hp_label:
		hp_label.text = str(current) + "/" + str(max_hp)
		# Force centering
		if hp_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# ── Shield bar update ────────────────────────────────────────────────────
func update_shield(current: float, max_shield: float) -> void:
	if shield_bar and is_instance_valid(shield_bar):
		if max_shield > 0 and current > 0:
			shield_bar.max_value = max_shield
			shield_bar.value = current
			shield_bar.visible = true
			if shield_label and is_instance_valid(shield_label):
				shield_label.text = str(int(current)) + "/" + str(int(max_shield))
				shield_label.visible = true
		else:
			shield_bar.visible = false
			if shield_label:
				shield_label.visible = false

# ── Per-frame position sync ──────────────────────────────────────────────
func sync_position(on_screen: bool, shield_stats: Vector2,
		is_boss: bool, is_super_boss: bool) -> void:
	if not hp_bar or not is_instance_valid(hp_bar):
		return

	if on_screen and _enemy.visible:
		# Show bars if hidden
		if not hp_bar.visible:
			hp_bar.visible = true
			if hp_label:
				hp_label.visible = true

		# Sync HP bar position
		hp_bar.scale = _enemy.scale
		var offset = Vector2(-25, -47) * _enemy.scale
		hp_bar.global_position = (_enemy.global_position + offset).round()

		# Sync HP label
		if hp_label and is_instance_valid(hp_label):
			_font_scaling()
			hp_label.scale = Vector2.ONE
			var bar_visual_size = hp_bar.size * hp_bar.scale
			var bar_center_global = hp_bar.global_position + bar_visual_size * 0.5
			var label_size = hp_label.size
			hp_label.global_position = (bar_center_global - label_size * 0.5).round()

		# Sync shield bar
		if shield_bar and is_instance_valid(shield_bar) and not is_boss and not is_super_boss:
			shield_bar.scale = _enemy.scale
			shield_bar.size.x = hp_bar.size.x
			var sb_offset = offset + Vector2(0, -9.0 * _enemy.scale.y)
			shield_bar.global_position = (_enemy.global_position + sb_offset).round()

			if shield_stats.y > 0 and shield_stats.x > 0:
				shield_bar.max_value = shield_stats.y
				shield_bar.value = shield_stats.x
				shield_bar.visible = true
				if shield_label and is_instance_valid(shield_label):
					shield_label.text = str(int(shield_stats.x)) + "/" + str(int(shield_stats.y))
					shield_label.size = Vector2(hp_bar.size.x * _enemy.scale.x, 12)
					shield_label.global_position = shield_bar.global_position
					shield_label.visible = true
			else:
				shield_bar.visible = false
				if shield_label:
					shield_label.visible = false

		if hp_label and not hp_label.visible:
			hp_label.visible = true
	else:
		# Off-screen or hidden: hide bars
		if hp_bar.visible:
			hp_bar.visible = false
		if hp_label and hp_label.visible:
			hp_label.visible = false
		if shield_bar and is_instance_valid(shield_bar) and shield_bar.visible:
			shield_bar.visible = false
		if shield_label and is_instance_valid(shield_label) and shield_label.visible:
			shield_label.visible = false

# ── Font scaling ─────────────────────────────────────────────────────────
func _font_scaling() -> void:
	if not hp_label or not is_instance_valid(hp_label):
		return
	var p_scale_x = abs(_enemy.scale.x)
	if abs(p_scale_x - _prev_scale_x) > 0.01:
		_prev_scale_x = p_scale_x
		if p_scale_x > 0.001:
			hp_label.pivot_offset = Vector2.ZERO
			if hp_label.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
				hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var visual_factor = pow(p_scale_x, 0.7)
			var target_font_size = int(10 * visual_factor)
			var target_outline = int(4 * visual_factor)
			if _cached_font_size != target_font_size:
				hp_label.add_theme_font_size_override("font_size", target_font_size)
				hp_label.add_theme_constant_override("outline_size", target_outline)
				_cached_font_size = target_font_size

# ── Reset for pooling ────────────────────────────────────────────────────
func reset() -> void:
	if hp_bar:
		hp_bar.visible = false
		hp_bar.modulate = Color.WHITE
		# Restore default green fill
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0, 1, 0)
		hp_bar.add_theme_stylebox_override("fill", style_box)
		hp_bar.value = hp_bar.max_value
	if hp_label:
		hp_label.visible = false
	if shield_bar:
		shield_bar.visible = false
	if shield_label:
		shield_label.visible = false
	_cached_font_size = -1
	_prev_scale_x = 0.0
