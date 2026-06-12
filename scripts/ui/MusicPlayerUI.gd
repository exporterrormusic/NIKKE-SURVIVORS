extends PanelContainer

# Static flag for other scripts to check if mouse is over the music player
static var is_hovered: bool = false
static var _instance: Control = null  # Track the active instance for rect checking

const UI := preload("res://scripts/ui/UITheme.gd")
const BracketStyleBoxScript := preload("res://scripts/ui/components/BracketStyleBox.gd")

# Use safe lookups for all nodes to prevent instantiation errors
@onready var song_label: Label = find_child("SongLabel", true, false)
@onready var progress_bar: ProgressBar = find_child("ProgressBar", true, false)
@onready var play_pause_btn: Button = find_child("PlayPauseButton", true, false)
@onready var prev_btn: Button = find_child("PrevButton", true, false)
@onready var next_btn: Button = find_child("NextButton", true, false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self  # Register this instance for static checks
	_apply_styles()

	# Track mouse hover to block game input
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if AudioDirector:
		AudioDirector.music_track_changed.connect(_on_track_changed)
		AudioDirector.music_playback_state_changed.connect(_on_state_changed)
		
		# Initial State (deferred to catch music that starts before UI is ready)
		call_deferred("_update_song_info")
		get_tree().create_timer(0.5).timeout.connect(_update_song_info)
		
	if play_pause_btn:
		play_pause_btn.pressed.connect(_on_play_pause)
	if next_btn:
		next_btn.pressed.connect(_on_next)
	if prev_btn:
		prev_btn.pressed.connect(_on_prev)

func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Bracket-frame chip styling (dark field register, approved HUD mockup
## docs/mockups/hud_v2.html).
func _apply_styles() -> void:
	var panel_style = BracketStyleBoxScript.new()
	add_theme_stylebox_override("panel", panel_style)

	if song_label:
		song_label.add_theme_font_override("font", UI.FONT_BOLD)
		song_label.add_theme_font_size_override("font_size", 15)
		song_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)

	if progress_bar:
		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(1, 1, 1, 0.12)
		bar_bg.set_corner_radius_all(0)
		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = UI.ACCENT_CYAN_DEEP
		bar_fill.set_corner_radius_all(0)
		progress_bar.add_theme_stylebox_override("background", bar_bg)
		progress_bar.add_theme_stylebox_override("fill", bar_fill)
		progress_bar.custom_minimum_size.y = 6

	for btn in [prev_btn, play_pause_btn, next_btn]:
		if btn == null:
			continue
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(1, 1, 1, 0.06)
		normal.set_corner_radius_all(0)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.122, 0.561, 0.878, 0.35)
		hover.set_corner_radius_all(0)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(0.122, 0.561, 0.878, 0.55)
		pressed.set_corner_radius_all(0)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_font_override("font", UI.FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)

func _on_mouse_entered() -> void:
	is_hovered = true

func _on_mouse_exited() -> void:
	is_hovered = false

# Static function to check if mouse is over this UI element (more reliable than signal-based hover)
static func is_mouse_over() -> bool:
	if is_hovered:
		return true
	# Also check directly using mouse position and rect as a fallback
	if _instance and is_instance_valid(_instance):
		var mouse_pos: Vector2 = _instance.get_global_mouse_position()
		var rect: Rect2 = _instance.get_global_rect()
		if rect.has_point(mouse_pos):
			return true
	return false

# Consume all mouse input on this panel to prevent attacks from triggering
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()  # Mark as handled, prevents propagation to game

func _process(_delta: float) -> void:
	if AudioDirector and progress_bar:
		progress_bar.value = AudioDirector.get_playback_progress() * 100.0

func _on_play_pause() -> void:
	if AudioDirector:
		AudioDirector.toggle_pause_music()

func _on_next() -> void:
	if AudioDirector:
		AudioDirector.play_next_random_song()

func _on_prev() -> void:
	if AudioDirector:
		AudioDirector.play_prev_song()

func _on_track_changed(track_name: String) -> void:
	if song_label:
		song_label.text = track_name

func _on_state_changed(is_playing: bool) -> void:
	if play_pause_btn:
		play_pause_btn.text = "||" if is_playing else "|>"

func _update_song_info() -> void:
	if AudioDirector:
		if song_label:
			song_label.text = AudioDirector.get_current_song_name()
		if play_pause_btn:
			play_pause_btn.text = "||" if AudioDirector.is_music_playing() else "|>"
