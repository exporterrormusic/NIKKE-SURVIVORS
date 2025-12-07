extends Node2D

# Draws HP text centered on the enemy HP bar
# Also shows enrage timer for bosses in Goddess Fall mode

var _current_hp: int = 1
var _max_hp: int = 1
var _enemy: Node = null
var _flash_time: float = 0.0  # For timer flashing
var _font: Font = null

const BASE_FONT_SIZE := 12
const BASE_TIMER_FONT_SIZE := 10

func _ready() -> void:
	# Ensure processing is always enabled and never paused
	set_process(true)
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(enemy: Node) -> void:
	_enemy = enemy
	if enemy:
		_current_hp = enemy.hp
		_max_hp = enemy.max_hp
	
	# Load font
	_font = load("res://resources/fonts/pretendard_bold.tres")
	if not _font:
		_font = ThemeDB.fallback_font
	
	queue_redraw()

func update_values(current: int, maximum: int) -> void:
	_current_hp = max(0, current)
	_max_hp = maximum
	queue_redraw()

func _process(delta: float) -> void:
	_flash_time += delta
	
	if not _enemy or not is_instance_valid(_enemy):
		return
	
	# Always check for enrage timer directly each frame and redraw if present
	var enrage_timer: Timer = _enemy.get_node_or_null("EnrageTimer")
	if enrage_timer and is_instance_valid(enrage_timer) and enrage_timer.time_left > 0:
		queue_redraw()

func _draw() -> void:
	if not _font:
		_font = ThemeDB.fallback_font
	if not _enemy or not is_instance_valid(_enemy):
		return
	
	# Get parent scale to render at higher resolution
	var parent_scale: float = _enemy.scale.x if _enemy.scale.x > 0 else 1.0
	
	# Render font at scaled size, then counter-scale the node
	# This gives us higher resolution text
	var font_size := int(BASE_FONT_SIZE * parent_scale)
	var timer_font_size := int(BASE_TIMER_FONT_SIZE * parent_scale)
	
	# Counter-scale so text appears at correct visual size
	scale = Vector2.ONE / _enemy.scale if _enemy.scale.x > 0 else Vector2.ONE
	
	# Draw HP text
	var hp_text := "%d/%d" % [_current_hp, _max_hp]
	var hp_text_size := _font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	var hp_draw_pos := Vector2(-hp_text_size.x * 0.5, font_size * 0.35)
	
	# Scale outline with font size
	var outline_size := maxi(1, int(parent_scale))
	_draw_outlined_text(_font, hp_draw_pos, hp_text, font_size, Color.WHITE, Color.BLACK, outline_size)
	
	# Draw enrage timer if present
	_draw_enrage_timer(hp_draw_pos.y, timer_font_size, outline_size)

func _draw_outlined_text(font: Font, pos: Vector2, text: String, size: int, color: Color, outline_color: Color, outline_size: int = 1) -> void:
	# Draw black outline
	for ox in range(-outline_size, outline_size + 1):
		for oy in range(-outline_size, outline_size + 1):
			if ox != 0 or oy != 0:
				draw_string(font, pos + Vector2(ox, oy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_color)
	# Draw main text
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_enrage_timer(hp_y_offset: float, timer_font_size: int, outline_size: int) -> void:
	if not _enemy or not is_instance_valid(_enemy):
		return
	
	var enrage_timer: Timer = _enemy.get_node_or_null("EnrageTimer")
	if not enrage_timer or enrage_timer.time_left <= 0:
		return
	
	var time_remaining: float = enrage_timer.time_left
	var seconds := int(time_remaining)
	var tenths := int((time_remaining - seconds) * 10)
	
	var timer_text := "⚠%d.%d⚠" % [seconds, tenths]
	var timer_color := Color(1.0, 0.9, 0.3, 1.0)  # Default yellow
	
	if time_remaining <= 3.0:
		timer_color = Color(1.0, 0.1, 0.1, 1.0)
	elif time_remaining <= 10.0:
		var urgency := 1.0 - (time_remaining - 3.0) / 7.0
		var flash_speed := 2.0 + urgency * 8.0
		var flash := sin(_flash_time * flash_speed * PI) * 0.5 + 0.5
		timer_color = Color(1.0, 0.9 - flash * 0.8, 0.3 - flash * 0.3, 1.0)
	
	var timer_text_size := _font.get_string_size(timer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, timer_font_size)
	# Timer position: offset upward more to account for HP bar being lowered (add 5 pixels)
	var timer_draw_pos := Vector2(-timer_text_size.x * 0.5, hp_y_offset - timer_font_size - 7)
	
	_draw_outlined_text(_font, timer_draw_pos, timer_text, timer_font_size, timer_color, Color.BLACK, outline_size)