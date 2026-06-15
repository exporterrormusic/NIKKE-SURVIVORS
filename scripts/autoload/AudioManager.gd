extends Node
## Audio management singleton - handles music, SFX, and UI sounds.
## Optimized replacement for the legacy AudioDirector.gd.
## Registered as autoload: AudioManager

# --- Signals ---
signal music_track_changed(track_name: String)
signal music_playback_state_changed(is_playing: bool)

# --- Audio Bus Names ---
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "SFX" # Using SFX bus for UI as well for now

# --- UI Sound Constants ---
const UI_SELECT := "res://assets/sounds/sfx/ui/select.wav"
const UI_BACK := "res://assets/sounds/sfx/ui/back.wav"
const UI_CONFIRM := "res://assets/sounds/sfx/ui/confirm.wav"

# --- Audio Players ---
var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer

const SFX_POOL_SIZE := 24

# --- State ---
var _current_music_path: String = ""
var _music_fade_tween: Tween = null
var _sfx_cache: Dictionary = {} # path -> AudioStream

# --- Auto loudness measurement ---
const TARGET_RMS_DB := -14.0
const RMS_SAMPLE_STRIDE := 50
var _measured_offsets: Dictionary = {}
var _offsets_config_path: String = "user://music_offsets.cfg"

# --- Music Metadata ---
const MUSIC_METADATA := {
	"battle": {"name": "BATTLE", "unlock_id": "", "volume_offset_db": 0.3},
	"breakbeat": {"name": "BREAKBEAT", "unlock_id": "", "volume_offset_db": -1.6},
	"dark": {"name": "DARK", "unlock_id": "", "volume_offset_db": -0.3},
	"nayuta": {"name": "SEEN IT ALL (Nayuta's Theme)", "unlock_id": "", "volume_offset_db": 0.5},
	"racer": {"name": "FAST", "unlock_id": "", "volume_offset_db": 0.9},
	"rapunzel": {"name": "YET STILL I BELIEVE (Rapunzel's Theme)", "unlock_id": "", "volume_offset_db": 1.1},
	"sin": {"name": "TASTE MY SILVER TONGUE (Sin's Theme)", "unlock_id": "", "volume_offset_db": -0.3},
	"snow": {"name": "UNYIELDING (Snow White's Theme)", "unlock_id": "", "volume_offset_db": -1.1},
	"train": {"name": "TRAIN", "unlock_id": "", "volume_offset_db": -0.3},
	"western": {"name": "WESTERN", "unlock_id": "", "volume_offset_db": 0.9},
	"wishes": {"name": "ABANDON YOUR WISHES (Scheherezade's Theme)", "unlock_id": "abandoned_wishes", "event_only": true, "volume_offset_db": 1.2},
	"main-menu": {"name": "MAIN MENU", "unlock_id": "", "volume_offset_db": 0.0},
	"timer": {"name": "TIMER", "unlock_id": "she_descends", "event_only": true, "volume_offset_db": -3.0},
}

# --- Weapon SFX Data ---
const WEAPON_SFX_ARRAYS := {
	"rocket_fire": ["res://assets/sounds/sfx/weapons/rocket/fire_rocket.mp3"],
	"minigun_fire": [
		"res://assets/sounds/sfx/weapons/minigun/fire1_minigun.mp3",
		"res://assets/sounds/sfx/weapons/minigun/fire2_minigun.mp3",
		"res://assets/sounds/sfx/weapons/minigun/fire3_minigun.mp3",
	],
	"shotgun_fire": ["res://assets/sounds/sfx/weapons/shotgun/fire_shotgun.mp3"],
	"sniper_fire": ["res://assets/sounds/sfx/weapons/sniper/fire_sniper.mp3"],
	"smg_fire": [
		"res://assets/sounds/sfx/weapons/SMG/fire1_SMG.mp3",
		"res://assets/sounds/sfx/weapons/SMG/fire2_SMG.mp3",
		"res://assets/sounds/sfx/weapons/SMG/fire3_SMG.mp3",
		"res://assets/sounds/sfx/weapons/SMG/fire4_SMG.mp3",
	],
	"assault_rifle_fire": ["res://assets/sounds/sfx/weapons/AR/fire_AR.mp3"],
	"sword_slash": [
		"res://assets/sounds/sfx/weapons/sword/sword_swing.mp3",
		"res://assets/sounds/sfx/weapons/sword/sword_swing1.mp3",
		"res://assets/sounds/sfx/weapons/sword/sword_swing2.mp3",
	],
	"rocket_explosion": ["res://assets/sounds/sfx/weapons/rocket/rocket_explosion.mp3"],
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	_load_measured_offsets()
	_scan_unmeasured_tracks.call_deferred()  # Defer so ResourceManifest is ready
	print("[AudioManager] Initialized")


func _setup_audio_players() -> void:
	# Music player
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	
	# UI player (separate from pooling for guaranteed UI feedback)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_SFX # Could use a dedicated UI bus if configured
	add_child(_ui_player)
	
	# SFX pool
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_pool.append(player)


# =============================================================================
# MUSIC MANAGEMENT
# =============================================================================

func play_music(path: String, fade_time: float = 0.5) -> void:
	if path == _current_music_path and _music_player.playing:
		return
		
	var stream = _load_stream(path)
	if not stream:
		return
		
	if _music_fade_tween:
		_music_fade_tween.kill()
	
	_current_music_path = path
	
	# Metadata update
	var file_id = path.get_file().get_basename().to_lower()
	var display_name = file_id.capitalize()
	if MUSIC_METADATA.has(file_id):
		display_name = MUSIC_METADATA[file_id]["name"]
	
	music_track_changed.emit(display_name)
	
	if fade_time > 0 and _music_player.playing:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -40.0, fade_time * 0.5)
		_music_fade_tween.tween_callback(func(): _start_playing_music(stream, fade_time * 0.5))
	else:
		_start_playing_music(stream, fade_time)


func _start_playing_music(stream: AudioStream, fade_in_time: float) -> void:
	# Look up per-track volume offset (hardcoded metadata → auto-measured cache → 0.0)
	var offset_db: float = _get_track_offset(_current_music_path)
	
	_music_player.stop()
	_music_player.stream = stream
	_music_player.volume_db = offset_db - 40.0 if fade_in_time > 0 else offset_db
	_music_player.play()
	
	if fade_in_time > 0:
		if _music_fade_tween: _music_fade_tween.kill()
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", offset_db, fade_in_time)
	
	music_playback_state_changed.emit(true)


func stop_music(fade_time: float = 0.5) -> void:
	if not _music_player.playing:
		return
		
	if _music_fade_tween:
		_music_fade_tween.kill()
		
	if fade_time > 0:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -40.0, fade_time)
		_music_fade_tween.tween_callback(func():
			_music_player.stop()
			_current_music_path = ""
			music_playback_state_changed.emit(false)
		)
	else:
		_music_player.stop()
		_current_music_path = ""
		music_playback_state_changed.emit(false)


# =============================================================================
# SFX MANAGEMENT
# =============================================================================

func play_sfx(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream = _load_stream(path)
	if not stream:
		return
		
	var player = _get_available_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func play_weapon_sfx(sfx_key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if WEAPON_SFX_ARRAYS.has(sfx_key):
		var variants: Array = WEAPON_SFX_ARRAYS[sfx_key]
		var path: String = variants[randi() % variants.size()]
		play_sfx(path, volume_db, pitch)
	else:
		push_warning("[AudioManager] Unknown weapon SFX key: %s" % sfx_key)


func play_ui(path: String, volume_db: float = 0.0) -> void:
	var stream = _load_stream(path)
	if stream:
		_ui_player.stream = stream
		_ui_player.volume_db = volume_db
		_ui_player.play()


func play_ui_select() -> void:
	play_ui(UI_SELECT, -6.0)


func play_ui_back() -> void:
	play_ui(UI_BACK, -6.0)


func play_ui_confirm() -> void:
	play_ui(UI_CONFIRM, -15.0)


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	# Fallback: Steal the first player if pool is full
	return _sfx_pool[0]


# =============================================================================
# AUTO LOUDNESS MEASUREMENT
# =============================================================================

func _load_measured_offsets() -> void:
	var config := ConfigFile.new()
	if config.load(_offsets_config_path) == OK:
		for key in config.get_section_keys("offsets"):
			_measured_offsets[key] = config.get_value("offsets", key)

func _save_measured_offsets() -> void:
	var config := ConfigFile.new()
	for key in _measured_offsets:
		config.set_value("offsets", key, _measured_offsets[key])
	config.save(_offsets_config_path)

func _scan_unmeasured_tracks() -> void:
	## Measure any battle music tracks that don't have a volume offset yet
	if not ResourceManifest:
		return
	ResourceManifest.ensure_initialized()
	var new_count := 0
	for path in ResourceManifest.battle_music:
		var file_id := path.get_file().get_basename().to_lower()
		if MUSIC_METADATA.has(file_id) and MUSIC_METADATA[file_id].has("volume_offset_db"):
			continue
		if _measured_offsets.has(file_id):
			continue
		
		var stream := _load_stream(path)
		if stream == null:
			continue
		
		var rms_db := _measure_stream_rms(stream)
		if rms_db > -80.0:
			var offset_db: float = snapped(TARGET_RMS_DB - rms_db, 0.1)
			_measured_offsets[file_id] = offset_db
			new_count += 1
			print("[AudioManager] Auto-measured %s: RMS %.1f dB → offset %.1f dB" % [file_id, rms_db, offset_db])
	
	if new_count > 0:
		_save_measured_offsets()
		print("[AudioManager] Saved %d new loudness measurement(s)" % new_count)

func _get_track_offset(path: String) -> float:
	var file_id := path.get_file().get_basename().to_lower()
	if MUSIC_METADATA.has(file_id) and MUSIC_METADATA[file_id].has("volume_offset_db"):
		return MUSIC_METADATA[file_id]["volume_offset_db"]
	if _measured_offsets.has(file_id):
		return _measured_offsets[file_id]
	return 0.0

func _measure_stream_rms(stream: AudioStream) -> float:
	var data := _get_stream_pcm(stream)
	if data.size() < 4:
		return -120.0
	
	var sum_sq := 0.0
	var count := 0
	var step := RMS_SAMPLE_STRIDE * 2
	var i := 0
	while i < data.size() - 1:
		var lo := data[i] as int
		var hi := data[i + 1] as int
		var sample := lo | (hi << 8)
		if sample >= 0x8000:
			sample -= 0x10000
		sum_sq += float(sample * sample)
		count += 1
		i += step
	
	if count == 0:
		return -120.0
	
	var rms := sqrt(sum_sq / float(count)) / 32768.0
	if rms < 0.0000001:
		return -120.0
	return 20.0 * log(rms) / log(10.0)

func _get_stream_pcm(stream: AudioStream) -> PackedByteArray:
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).data
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).data
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).data
	return PackedByteArray()

# =============================================================================
# UTILITY
# =============================================================================

func _load_stream(path: String) -> AudioStream:
	if _sfx_cache.has(path):
		return _sfx_cache[path]
		
	if ResourceLoader.exists(path):
		var stream = load(path)
		if stream:
			# Ensure loop state for music
			if path.contains("music/"):
				_set_loop(stream, true)
			_sfx_cache[path] = stream
			return stream
			
	push_warning("[AudioManager] Failed to load sound: %s" % path)
	return null


func _set_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamMP3:
		stream.loop = loop
	elif stream is AudioStreamOggVorbis:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED


func set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clamp(linear_volume, 0.0, 1.0)))


func get_bus_volume(bus_name: String) -> float:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		return db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	return 1.0


# =============================================================================
# AUDIO DIRECTOR FORWARDING
# These methods delegate to AudioDirector (found on the player node during
# gameplay) so that consumers can use AudioManager as the single entry point.
# =============================================================================

## Lazy-cached reference to AudioDirector
static var _audio_director_ref: Node = null

static func _find_audio_director() -> Node:
	if not is_instance_valid(_audio_director_ref):
		_audio_director_ref = null
		var tree = Engine.get_main_loop()
		if tree and tree is SceneTree:
			var root = tree.root
			if root:
				var player = root.get_node_or_null("/root/Level/Player")
				if player:
					_audio_director_ref = player.get_node_or_null("AudioDirector")
	return _audio_director_ref

## Play a random battle track via AudioDirector
static func play_random_battle_track() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_random_battle_track"):
		ad.play_random_battle_track()

## Play music by explicit path via AudioDirector
static func play_music_by_path(path: String, force: bool = false, fade_time: float = 0.5) -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_music_by_path"):
		ad.play_music_by_path(path, force, fade_time)

## Play the N01 queen timer music
static func play_queen_timer_music() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_queen_timer_music"):
		ad.play_queen_timer_music()

## Stop music via AudioDirector
static func stop_music_director(fade_time: float = 0.5) -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("stop_music"):
		ad.stop_music(fade_time)

## Stop ambient audio via AudioDirector
static func stop_ambient(fade_time: float = 0.5) -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("stop_ambient"):
		ad.stop_ambient(fade_time)

## Play rain ambience via AudioDirector
static func play_rain_ambience() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_rain_ambience"):
		ad.play_rain_ambience()

## Get current song name from AudioDirector
static func get_current_song_name() -> String:
	var ad = _find_audio_director()
	if ad and ad.has_method("get_current_song_name"):
		return ad.get_current_song_name()
	return ""

## Get playback progress from AudioDirector
static func get_playback_progress() -> float:
	var ad = _find_audio_director()
	if ad and ad.has_method("get_playback_progress"):
		return ad.get_playback_progress()
	return 0.0

## Toggle pause music via AudioDirector
static func toggle_pause_music() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("toggle_pause_music"):
		ad.toggle_pause_music()

## Play next random song via AudioDirector
static func play_next_random_song() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_next_random_song"):
		ad.play_next_random_song()

## Play previous song via AudioDirector
static func play_prev_song() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_prev_song"):
		ad.play_prev_song()

## Check if music is playing via AudioDirector
static func is_music_playing() -> bool:
	var ad = _find_audio_director()
	if ad and ad.has_method("is_music_playing"):
		return ad.is_music_playing()
	return false

## Play UI music via AudioDirector
static func play_ui_music() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("play_ui_music"):
		ad.play_ui_music()

## Update playlist via AudioDirector
static func update_playlist() -> void:
	var ad = _find_audio_director()
	if ad and ad.has_method("_update_playlist"):
		ad._update_playlist()

## Reset AudioDirector cached reference (call on scene transition)
static func reset_audio_director_ref() -> void:
	_audio_director_ref = null
