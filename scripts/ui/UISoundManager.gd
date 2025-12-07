extends Node
class_name UISoundManager
## Global UI sound effect manager.
## Provides centralized audio playback for menu navigation sounds.
## Use: UISoundManager.play_back(), UISoundManager.play_select(), UISoundManager.play_confirm()

# Sound paths
const SFX_BACK := "res://assets/sounds/sfx/ui/back.wav"
const SFX_SELECT := "res://assets/sounds/sfx/ui/select.wav"
const SFX_CONFIRM := "res://assets/sounds/sfx/ui/confirm.wav"

# Audio players (reused for performance)
static var _back_player: AudioStreamPlayer = null
static var _select_player: AudioStreamPlayer = null
static var _confirm_player: AudioStreamPlayer = null
static var _initialized: bool = false

# Preloaded streams
static var _back_stream: AudioStream = null
static var _select_stream: AudioStream = null
static var _confirm_stream: AudioStream = null


static func _ensure_initialized() -> void:
	if _initialized:
		return
	
	# Preload audio streams
	_back_stream = load(SFX_BACK)
	_select_stream = load(SFX_SELECT)
	_confirm_stream = load(SFX_CONFIRM)
	
	_initialized = true


static func _get_or_create_player(stream: AudioStream, existing: AudioStreamPlayer) -> AudioStreamPlayer:
	if existing and is_instance_valid(existing):
		return existing
	
	# Need to create a new player - find a valid node to parent it
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	
	var root := tree.root
	if not root:
		return null
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.name = "UISoundPlayer"
	root.add_child(player)
	
	return player


## Play the back/exit sound effect
static func play_back() -> void:
	_ensure_initialized()
	if not _back_stream:
		return
	
	_back_player = _get_or_create_player(_back_stream, _back_player)
	if _back_player:
		_back_player.stream = _back_stream
		_back_player.volume_db = -6.0  # Slightly lowered volume
		_back_player.play()


## Play the select/click sound effect (for most button clicks)
static func play_select() -> void:
	_ensure_initialized()
	if not _select_stream:
		return
	
	_select_player = _get_or_create_player(_select_stream, _select_player)
	if _select_player:
		_select_player.stream = _select_stream
		_select_player.volume_db = -6.0  # Slightly lowered volume
		_select_player.play()


## Play the confirm/next sound effect (for confirm, start, next buttons)
static func play_confirm() -> void:
	_ensure_initialized()
	if not _confirm_stream:
		return
	
	_confirm_player = _get_or_create_player(_confirm_stream, _confirm_player)
	if _confirm_player:
		_confirm_player.stream = _confirm_stream
		_confirm_player.volume_db = -15.0  # Much lower volume
		_confirm_player.play()
