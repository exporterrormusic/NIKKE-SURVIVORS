extends Node
class_name AudioDirector

## Centralized audio playback and bus management.
## Add to autoloads for global access.

const MUSIC_BUS := "Music"  # Music bus for background music only
const SFX_BUS := "SFX"      # SFX bus for all sound effects (weapons, UI, etc.)
const BATTLE_MUSIC_DIR := "res://assets/sounds/music"

const WEAPON_FILE_MAP := {
	"Assault Rifle": "AR",
	"assault_rifle": "AR",
	"assault": "AR",
	"AR": "AR",
	"Rocket Launcher": "rocket",
	"rocket_launcher": "rocket",
	"rocket": "rocket",
	"Shotgun": "shotgun",
	"shotgun": "shotgun",
	"SMG": "SMG",
	"smg": "SMG",
	"Sniper": "sniper",
	"sniper": "sniper",
	"Sword": "sword",
	"sword": "sword",
	"Minigun": "minigun",
	"minigun": "minigun"
}

var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _looping_players: Dictionary = {}
var _stream_cache: Dictionary = {}
var _weapon_fire_counters: Dictionary = {}

var _master_volume := 1.0
var _music_volume := 1.0
var _sfx_volume := 1.0
var _current_music_path: String = ""
var _ambient_player: AudioStreamPlayer = null
var _current_ambient_path: String = ""
var _explosion_player: AudioStreamPlayer = null  # Dedicated explosion player to prevent overlap

func _ready() -> void:
	initialize()

func _exit_tree() -> void:
	# Clean up all looping players to prevent lambda capture errors
	for handle in _looping_players.keys():
		stop_looping_sfx(handle)
	_looping_players.clear()

func initialize() -> void:
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		_music_player.bus = MUSIC_BUS
		_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_player)

func play_random_battle_track(fade_time: float = 0.5) -> void:
	var candidates := _list_files_in_directory(BATTLE_MUSIC_DIR)
	if candidates.is_empty():
		push_warning("AudioDirector: No battle music files found in %s" % BATTLE_MUSIC_DIR)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var choice := candidates[rng.randi_range(0, candidates.size() - 1)]
	play_music_by_path(choice, true, fade_time)

func play_music_by_path(path: String, loop: bool = true, fade_time: float = 0.5) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	initialize()
	var prepared := _ensure_loop_state(stream, loop)
	if fade_time > 0.05 and _music_player.playing:
		_start_music_with_fade(prepared, fade_time)
	else:
		_music_player.stop()
		_music_player.stream = prepared
		_music_player.volume_db = -12.0 if fade_time > 0.05 else 0.0
		_music_player.play()
		if fade_time > 0.05:
			var tween := create_tween()
			tween.tween_property(_music_player, "volume_db", 0.0, fade_time)
	_current_music_path = path

func stop_music(fade_time: float = 0.3) -> void:
	if _music_player == null or not _music_player.playing:
		return
	if fade_time <= 0.05:
		_music_player.stop()
		_current_music_path = ""
		return
	var tween := create_tween()
	var player_ref := _music_player
	tween.tween_property(player_ref, "volume_db", -48.0, fade_time)
	tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(player_ref):
			player_ref.stop()
			player_ref.volume_db = 0.0
	)
	_current_music_path = ""

func play_sfx_by_path(path: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	var player := _request_sfx_player()
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.volume_db = volume_db
	player.play()

## Play burst voice with dedicated player at scene root
## Ensures voice plays to completion regardless of game state
func play_burst_voice(sound: AudioStream) -> void:
	if sound == null:
		return
	
	# Create a fresh player at scene root for complete independence
	var burst_player = AudioStreamPlayer.new()
	burst_player.name = "BurstVoice_%d" % Time.get_ticks_msec()
	burst_player.bus = SFX_BUS  # Use SFX bus for voice lines
	burst_player.process_mode = Node.PROCESS_MODE_ALWAYS
	burst_player.stream = sound
	burst_player.volume_db = 6.0
	burst_player.pitch_scale = 1.0
	get_tree().root.add_child(burst_player)
	burst_player.play()
	burst_player.finished.connect(burst_player.queue_free)

func play_weapon_fire_sound(weapon_name: String, is_special_attack: bool = false) -> void:
	var key := _resolve_weapon_key(weapon_name)
	if key == "":
		push_warning("AudioDirector: No fire sound mapping for %s" % weapon_name)
		return
	var volume_db := 0.0
	if key == "sniper":
		volume_db = 6.0  # Increased volume for sniper
	var directory := "res://assets/sounds/sfx/weapons/%s" % key
	if is_special_attack:
		var fire_special_path := "%s/fire_special.mp3" % directory
		if _stream_exists(fire_special_path):
			play_sfx_by_path(fire_special_path, 1.0, volume_db)
			return
		var special_path := "%s/special_%s.mp3" % [directory, key]
		if _stream_exists(special_path):
			play_sfx_by_path(special_path, 1.0, volume_db)
			return
	var variants := _collect_indexed_variants(directory, "fire", key)
	if variants.size() > 1:
		var counter: int = int(_weapon_fire_counters.get(key, 0))
		var index: int = counter % variants.size()
		_weapon_fire_counters[key] = (counter + 1) % variants.size()
		play_sfx_by_path(variants[index], 1.0, volume_db)
		return
	if variants.size() == 1:
		play_sfx_by_path(variants[0], 1.0, volume_db)
		return
	var fallback_mp3 := "%s/fire_%s.mp3" % [directory, key]
	if _stream_exists(fallback_mp3):
		play_sfx_by_path(fallback_mp3, 1.0, volume_db)
		return
	var fallback_wav := "%s/fire_%s.wav" % [directory, key]
	if _stream_exists(fallback_wav):
		play_sfx_by_path(fallback_wav, 1.0, volume_db)
		return
	push_warning("AudioDirector: Missing fire sound for weapon %s" % weapon_name)

func play_rocket_flight_sound() -> int:
	return play_looping_sfx("res://assets/sounds/sfx/weapons/rocket/rocket_fly.mp3", 1.0, -6.02)

func stop_rocket_flight_sound(handle: int) -> void:
	stop_looping_sfx(handle)

func play_rocket_explosion_sound() -> void:
	# Use dedicated explosion player to prevent overlapping explosion sounds
	# Only play if not already playing an explosion
	if _explosion_player == null:
		_explosion_player = AudioStreamPlayer.new()
		_explosion_player.bus = SFX_BUS
		add_child(_explosion_player)
		var stream := _load_stream("res://assets/sounds/sfx/weapons/rocket/rocket_explosion.mp3")
		if stream:
			_explosion_player.stream = stream
	
	# Skip if explosion is already playing (prevents overlap)
	if _explosion_player.playing:
		return
	
	_explosion_player.pitch_scale = 1.0
	_explosion_player.volume_db = -12.0  # Reduced volume (was -6.02)
	_explosion_player.play()

func play_weapon_reload_sound(weapon_name: String) -> void:
	var key := _resolve_weapon_key(weapon_name)
	if key == "":
		push_warning("AudioDirector: No reload sound mapping for %s" % weapon_name)
		return
	var directory := "res://assets/sounds/sfx/weapons/%s" % key
	var reload_path := "%s/reload_%s.mp3" % [directory, key]
	if _stream_exists(reload_path):
		play_sfx_by_path(reload_path, 1.0, 0.0)
		return
	# Try wav fallback
	var reload_wav := "%s/reload_%s.wav" % [directory, key]
	if _stream_exists(reload_wav):
		play_sfx_by_path(reload_wav, 1.0, 0.0)
		return
	push_warning("AudioDirector: Missing reload sound for weapon %s" % weapon_name)

func play_looping_sfx(path: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> int:
	var stream := _load_stream(path)
	if stream == null:
		return -1
	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.stream = _ensure_loop_state(stream, true)
	add_child(player)
	player.play()
	player.finished.connect(func(): 
		if not is_instance_valid(self):
			return
		if is_instance_valid(player):
			player.play()
	)
	var handle := player.get_instance_id()
	_looping_players[handle] = player
	player.tree_exited.connect(func():
		if not is_instance_valid(self):
			return
		if _looping_players.has(handle):
			_looping_players.erase(handle)
	)
	return handle

func stop_looping_sfx(handle: int) -> void:
	if not _looping_players.has(handle):
		return
	var player: AudioStreamPlayer = _looping_players[handle]
	_looping_players.erase(handle)
	if player and is_instance_valid(player):
		# Disconnect all signals to prevent lambda capture errors
		if player.finished.get_connections().size() > 0:
			for conn in player.finished.get_connections():
				player.finished.disconnect(conn["callable"])
		if player.tree_exited.get_connections().size() > 0:
			for conn in player.tree_exited.get_connections():
				player.tree_exited.disconnect(conn["callable"])
		player.stop()
		player.queue_free()

func set_master_volume(value: float) -> void:
	_master_volume = clamp(value, 0.0, 1.0)

func set_music_volume(value: float) -> void:
	_music_volume = clamp(value, 0.0, 1.0)

func set_sfx_volume(value: float) -> void:
	_sfx_volume = clamp(value, 0.0, 1.0)

func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing

func play_ambient_loop(path: String, fade_time: float = 0.5) -> void:
	if path == _current_ambient_path and _ambient_player != null and _ambient_player.playing:
		return
	var stream := _load_stream(path)
	if stream == null:
		push_warning("AudioDirector: Failed to load ambient stream %s" % path)
		return
	if _ambient_player == null:
		_ambient_player = AudioStreamPlayer.new()
		_ambient_player.name = "AmbientPlayer"
		_ambient_player.bus = SFX_BUS
		_ambient_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_ambient_player)
	var looped_stream := _ensure_loop_state(stream, true)
	if _ambient_player.playing and fade_time > 0.05:
		var fade_out := create_tween()
		var ambient_ref := _ambient_player
		fade_out.tween_property(ambient_ref, "volume_db", -48.0, fade_time * 0.5)
		fade_out.finished.connect(func():
			if not is_instance_valid(self):
				return
			if is_instance_valid(ambient_ref):
				ambient_ref.stop()
				ambient_ref.stream = looped_stream
				ambient_ref.volume_db = -24.0
				ambient_ref.play()
				var fade_in := create_tween()
				fade_in.tween_property(ambient_ref, "volume_db", -6.0, fade_time * 0.5)
		)
	else:
		_ambient_player.stop()
		_ambient_player.stream = looped_stream
		_ambient_player.volume_db = -6.0
		_ambient_player.play()
	_current_ambient_path = path

func stop_ambient(fade_time: float = 0.3) -> void:
	if _ambient_player == null or not _ambient_player.playing:
		_current_ambient_path = ""
		return
	if fade_time <= 0.05:
		_ambient_player.stop()
		_current_ambient_path = ""
		return
	var tween := create_tween()
	var ambient_ref := _ambient_player
	tween.tween_property(ambient_ref, "volume_db", -48.0, fade_time)
	tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(ambient_ref):
			ambient_ref.stop()
	)
	_current_ambient_path = ""

func _start_music_with_fade(stream: AudioStream, fade_time: float) -> void:
	var fade_out := create_tween()
	var player_ref := _music_player
	fade_out.tween_property(player_ref, "volume_db", -48.0, fade_time * 0.5)
	fade_out.finished.connect(func():
		if not is_instance_valid(self):
			return
		if not is_instance_valid(player_ref):
			return
		player_ref.stop()
		player_ref.stream = stream
		player_ref.volume_db = -30.0
		player_ref.play()
		var fade_in := create_tween()
		fade_in.tween_property(player_ref, "volume_db", 0.0, max(0.01, fade_time * 0.5))
	)

func _request_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if player == null:
			continue
		if not player.playing:
			return player
	var new_player := AudioStreamPlayer.new()
	new_player.bus = SFX_BUS
	add_child(new_player)
	_sfx_pool.append(new_player)
	return new_player

func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = ResourceLoader.load(path)
	if stream == null:
		push_warning("AudioDirector: Failed to load stream %s" % path)
		return null
	_stream_cache[path] = stream
	return stream

func _stream_exists(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path)

func _ensure_loop_state(stream: AudioStream, should_loop: bool) -> AudioStream:
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var desired := AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
		if wav.loop_mode == desired:
			return wav
		var wav_clone := wav.duplicate() as AudioStreamWAV
		wav_clone.loop_mode = desired
		return wav_clone
	if stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		if mp3.loop == should_loop:
			return mp3
		var mp3_clone := mp3.duplicate() as AudioStreamMP3
		mp3_clone.loop = should_loop
		return mp3_clone
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		if ogg.loop == should_loop:
			return ogg
		var ogg_clone := ogg.duplicate() as AudioStreamOggVorbis
		ogg_clone.loop = should_loop
		return ogg_clone
	return stream

func _collect_indexed_variants(directory: String, prefix: String, key: String) -> Array[String]:
	var variants: Array[String] = []
	for i in range(1, 9):
		var candidate := "%s/%s%d_%s.mp3" % [directory, prefix, i, key]
		if _stream_exists(candidate):
			variants.append(candidate)
			continue
		break
	return variants

func _resolve_weapon_key(weapon_name: String) -> String:
	if weapon_name == "":
		return ""
	if WEAPON_FILE_MAP.has(weapon_name):
		return WEAPON_FILE_MAP[weapon_name]
	var normalized := weapon_name.strip_edges().to_lower()
	if WEAPON_FILE_MAP.has(normalized):
		return WEAPON_FILE_MAP[normalized]
	return ""

func _list_files_in_directory(path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".mp3"):
			var full_path := "%s/%s" % [path, entry_name]
			if ResourceLoader.exists(full_path):
				files.append(full_path)
		entry_name = dir.get_next()
	dir.list_dir_end()
	return files
