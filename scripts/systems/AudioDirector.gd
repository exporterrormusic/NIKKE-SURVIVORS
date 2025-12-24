extends Node

## Centralized audio playback and bus management.
## Add to autoloads for global access.

const MUSIC_BUS := "Music" # Music bus for background music only
const SFX_BUS := "SFX" # SFX bus for all sound effects (weapons, UI, etc.)
const BATTLE_MUSIC_DIR := "res://assets/sounds/music/bgm"

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
var _explosion_player: AudioStreamPlayer = null # Dedicated explosion player to prevent overlap
var _ambient_player_a: AudioStreamPlayer = null
var _ambient_player_b: AudioStreamPlayer = null
var _ambient_use_b: bool = false
var _ambient_loop_timer: Timer = null
const AMBIENT_CROSSFADE := 1.0 # seconds to crossfade between loop endpoints
var _ambient_stream_length: float = 0.0
var _ambient_crossfade_step_timer: Timer = null
var _ambient_crossfade_progress: float = 0.0
var _ambient_crossfade_step_dt: float = 0.05
var _ambient_base_db: float = 6.0
var _music_tween: Tween = null # Track active music fade tween to prevent race conditions

# --- MUSIC PLAYER ADDITIONS ---
# Name: [Display Name, Unlock Condition (Achievement ID or empty if unlocked)]
const MUSIC_METADATA := {
	"battle": {"name": "BATTLE", "unlock_id": ""},
	"dark": {"name": "DARK", "unlock_id": ""},
	"nayuta": {"name": "SEEN IT ALL (Nayuta's Theme)", "unlock_id": ""},
	"racer": {"name": "FAST", "unlock_id": ""},
	"rapunzel": {"name": "YET STILL I BELIEVE (Rapunzel's Theme)", "unlock_id": ""},
	"sin": {"name": "TASTE MY SILVER TONGUE (Sin's Theme)", "unlock_id": ""},
	"snow": {"name": "UNYIELDING (Snow White's Theme)", "unlock_id": ""},
	"western": {"name": "WESTERN", "unlock_id": ""},
	"wishes": {"name": "ABANDON YOUR WISHES (Scheherezade's Theme)", "unlock_id": "abandoned_wishes", "event_only": true},
	"main-menu": {"name": "MAIN MENU", "unlock_id": ""},
	"timer": {"name": "TIMER", "unlock_id": "she_descends", "event_only": true},
}

signal music_track_changed(track_name: String)
signal music_playback_state_changed(is_playing: bool)

var _playlist: Array[String] = [] # List of confirmed unlocked file paths
var _shuffled_queue: Array[String] = [] # Shuffled queue - depletes then reshuffles
var _history: Array[String] = [] # Paths of previously played songs
var _current_track_path: String = ""
var _is_paused_by_user: bool = false

func _ready() -> void:
	initialize()
	_update_playlist()

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
	
	# Preload weapon sounds to prevent frame freezes during gameplay
	_preload_weapon_sounds()

## Preload all weapon fire/reload sounds at startup to avoid frame freezes
func _preload_weapon_sounds() -> void:
	print("[AudioDirector] Preloading weapon sounds...")
	var start_time := Time.get_ticks_msec()
	var count := 0
	
	# Weapon directories and their expected sound patterns
	var weapon_patterns := {
		"SMG": ["fire1_SMG", "fire2_SMG", "fire3_SMG", "fire4_SMG", "reload_SMG"],
		"sniper": ["fire_sniper", "reload_sniper"],
		"shotgun": ["fire_shotgun", "reload_shotgun"],
		"rocket": ["fire_rocket", "rocket_explosion", "rocket_fly"],
		"AR": ["fire_AR", "fire1_AR", "fire2_AR", "reload_AR"],
		"minigun": ["fire_minigun", "fire1_minigun", "reload_minigun"],
		"sword": ["sword_swing", "sword_swing1", "sword_swing2"],
	}
	
	var base_path := "res://assets/sounds/sfx/weapons"
	var extensions := [".mp3", ".ogg", ".wav"]
	
	for weapon_dir in weapon_patterns:
		var patterns: Array = weapon_patterns[weapon_dir]
		for pattern in patterns:
			for ext in extensions:
				var full_path := "%s/%s/%s%s" % [base_path, weapon_dir, pattern, ext]
				if ResourceLoader.exists(full_path):
					# Load and cache the stream
					var stream := _load_stream(full_path)
					if stream:
						count += 1
					break # Found this pattern, move to next
	
	var elapsed := Time.get_ticks_msec() - start_time
	print("[AudioDirector] Preloaded %d weapon sounds in %d ms" % [count, elapsed])

func play_random_battle_track(fade_time: float = 0.5) -> void:
	# Use ResourceManifest for export-safe file listing
	ResourceManifest.ensure_initialized()
	var candidates: Array[String] = []
	# Filter out event_only songs (timer.mp3, wishes.mp3)
	# Filter out event_only songs (timer.mp3, wishes.mp3)
	# Filter out event_only songs (timer.mp3, wishes.mp3)
	for path in ResourceManifest.battle_music:
		var file_id = path.get_file().get_basename()
		if MUSIC_METADATA.has(file_id):
			var data = MUSIC_METADATA[file_id]
			if data.get("event_only", false):
				continue # Skip event-only songs from random selection
		candidates.append(path)
	if candidates.is_empty():
		push_warning("AudioDirector: No battle music files in manifest")
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var choice: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	play_music_by_path(choice, true, fade_time)

func play_music_by_path(path: String, loop: bool = true, fade_time: float = 0.5) -> void:
	print("[AudioDirector] play_music_by_path called: ", path)
	if _current_music_path == path and _music_player.playing:
		print("[AudioDirector] Music already playing: ", path)
		return
		
	var stream := _load_stream(path)
	if stream == null:
		push_error("[AudioDirector] FAILED to load music stream: " + path)
		return
	print("[AudioDirector] Stream loaded successfully. Preparing to play.")
	print("[AudioDirector] Preparing to play. _music_player.playing: ", _music_player.playing, " fade_time: ", fade_time)
	
	var prepared := _ensure_loop_state(stream, loop)
	
	# Kill any pending music fade/stop tween
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	
	if fade_time > 0.05 and _music_player.playing:
		print("[AudioDirector] Branch: CROSSFADE")
		_start_music_with_fade(prepared, fade_time)
	else:
		print("[AudioDirector] Branch: STANDARD START")
		_music_player.stop()
		_music_player.stream = prepared
		_music_player.volume_db = -12.0 if fade_time > 0.05 else 0.0
		_music_player.play()
		if fade_time > 0.05:
			_music_tween = create_tween()
			_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Run even if paused
			_music_tween.tween_property(_music_player, "volume_db", 0.0, fade_time)
	_current_music_path = path
	_current_track_path = path # Sync for Music Player UI
	
	# Add to history if this is a new track (enables "Previous" button for first song)
	if _history.is_empty() or _history[_history.size() - 1] != path:
		_history.append(path)
		if _history.size() > 20:
			_history.pop_front()
	
	# Emit signal so Music Player UI updates immediately
	var file_id = path.get_file().get_basename().to_lower()
	var display_name = file_id.capitalize()
	if MUSIC_METADATA.has(file_id):
		display_name = MUSIC_METADATA[file_id]["name"]
	emit_signal("music_track_changed", display_name)
	emit_signal("music_playback_state_changed", true)

func stop_music(fade_time: float = 0.3) -> void:
	if _music_player == null or not _music_player.playing:
		return
	
	# Kill any active tween
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
		
	if fade_time <= 0.05:
		_music_player.stop()
		_current_music_path = ""
		return
	
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var player_ref := _music_player
	_music_tween.tween_property(player_ref, "volume_db", -48.0, fade_time)
	_music_tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(player_ref):
			player_ref.stop()
			player_ref.volume_db = 0.0
	)
	_current_music_path = ""

func play_ui_music() -> void:
	# _load_stream will automatically find .ogg if .mp3 is missing or overridden
	play_music_by_path("res://assets/sounds/music/menu/main-menu.mp3", true, 0.5)

func play_queen_timer_music() -> void:
	play_music_by_path("res://assets/sounds/music/bgm/timer.wav", true, 2.0)
	print("[AudioDirector] Playing Queen Timer Music (Crossfade 2.0s)")

func play_sfx_by_path(path: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	var player := _request_sfx_player()
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.volume_db = volume_db
	player.play()

var _current_burst_player: AudioStreamPlayer = null

## Play burst voice with dedicated player at scene root
## Ensures voice plays to completion regardless of game state
## ENFORCED MONOPHONY: Stops any previous burst voice to prevent overlapping lines.
func play_burst_voice(sound: AudioStream) -> void:
	if sound == null:
		return
	
	# Stop/Clear previous burst player if it's still running
	if is_instance_valid(_current_burst_player):
		_current_burst_player.stop()
		_current_burst_player.queue_free()
		_current_burst_player = null
	
	# Create a fresh player at scene root for complete independence
	var burst_player = AudioStreamPlayer.new()
	burst_player.name = "BurstVoice_%d" % Time.get_ticks_msec()
	burst_player.bus = SFX_BUS # Use SFX bus for voice lines
	burst_player.process_mode = Node.PROCESS_MODE_ALWAYS
	burst_player.stream = sound
	burst_player.volume_db = 6.0
	burst_player.pitch_scale = 1.0
	
	get_tree().root.add_child(burst_player)
	burst_player.play()
	
	# Track current player
	_current_burst_player = burst_player
	
	# Cleanup on finish
	burst_player.finished.connect(func():
		if is_instance_valid(burst_player):
			burst_player.queue_free()
		if _current_burst_player == burst_player:
			_current_burst_player = null
	)

func play_weapon_fire_sound(weapon_name: String, is_special_attack: bool = false) -> void:
	var key := _resolve_weapon_key(weapon_name)
	if key == "":
		push_warning("AudioDirector: No fire sound mapping for %s" % weapon_name)
		return
	var volume_db := 0.0
	if key == "sniper":
		volume_db = 6.0 # Increased volume for sniper
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
	_explosion_player.volume_db = -12.0 # Reduced volume (was -6.02)
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
	print("AudioDirector: play_looping_sfx requested for: ", path)
	var stream := _load_stream(path)
	if stream == null:
		return -1
	print("AudioDirector: loaded stream type=", typeof(stream), " class=", stream.get_class())
	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	var ensured := _ensure_loop_state(stream, true)
	player.stream = ensured
	if ensured is AudioStreamWAV:
		var w := ensured as AudioStreamWAV
		print("AudioDirector: WAV stream loop_mode=", w.loop_mode, " loop_begin=", w.loop_begin, " loop_end=", w.loop_end)
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
	# If already playing this stream, just ensure it's playing and return
	if _current_ambient_path == path:
		if _ambient_player and _ambient_player.playing:
			return
		# If player exists but stopped, we'll let it restart below
	
	print("AudioDirector: play_ambient_loop requested for: ", path)
	var stream := _load_stream(path)
	if stream == null:
		push_warning("AudioDirector: Failed to load ambient stream %s" % path)
		return
		
	# FORCE native engine looping for stable volume
	# This fixes the "fade out then in" artifact from the manual crossfader
	_ensure_loop_state(stream, true)
	
	if _ambient_player == null:
		_ambient_player = AudioStreamPlayer.new()
		_ambient_player.name = "AmbientPlayer"
		_ambient_player.bus = SFX_BUS
		_ambient_player.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_ambient_player)
	
	_current_ambient_path = path
	
	# Clean up legacy crossfade system if active
	if _ambient_loop_timer and not _ambient_loop_timer.is_stopped():
		_ambient_loop_timer.stop()
	if _ambient_player_a and _ambient_player_a.playing:
		_ambient_player_a.stop()
	if _ambient_player_b and _ambient_player_b.playing:
		_ambient_player_b.stop()
		
	# Play with simple crossfade for track transition (not loop)
	if _ambient_player.playing and fade_time > 0.05:
		var fade_out := create_tween()
		var player_ref := _ambient_player
		# Fade out old
		fade_out.tween_property(player_ref, "volume_db", -80.0, fade_time * 0.5)
		fade_out.finished.connect(func():
			if not is_instance_valid(self) or not is_instance_valid(player_ref):
				return
			# Switch and fade in
			player_ref.stop()
			player_ref.stream = stream
			player_ref.volume_db = -80.0
			player_ref.play()
			var fade_in := create_tween()
			fade_in.tween_property(player_ref, "volume_db", 6.0, fade_time * 0.5)
		)
	else:
		# Immediate start
		_ambient_player.stop()
		_ambient_player.stream = stream
		_ambient_player.volume_db = 6.0
		_ambient_player.play()

func stop_ambient(fade_time: float = 0.3) -> void:
	# Stop any ambient playback (single-player or crossfade players)
	_current_ambient_path = ""
	# Stop two-player system
	if _ambient_loop_timer != null and not _ambient_loop_timer.is_stopped():
		_ambient_loop_timer.stop()
	if _ambient_player_a != null and _ambient_player_a.playing:
		_ambient_player_a.stop()
	if _ambient_player_b != null and _ambient_player_b.playing:
		_ambient_player_b.stop()
	# Stop legacy single player
	if _ambient_player == null or not _ambient_player.playing:
		return
	if fade_time <= 0.05:
		_ambient_player.stop()
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

func _start_music_with_fade(stream: AudioStream, fade_time: float) -> void:
	print("[AudioDirector] Starting music crossfade. Time: ", fade_time)
	
	# Kill any active tween
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
		
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Run even if game is paused
	var player_ref := _music_player
	_music_tween.tween_property(player_ref, "volume_db", -48.0, fade_time * 0.5)
	_music_tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if not is_instance_valid(player_ref):
			return
		player_ref.stop()
		player_ref.stream = stream
		player_ref.volume_db = -30.0
		player_ref.play()
		# Start fade in (reuse same tween variable, create new tween)
		_music_tween = create_tween()
		_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Run even if game is paused
		_music_tween.tween_property(player_ref, "volume_db", 0.0, max(0.01, fade_time * 0.5))
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
		
	# Smart Loading: Check for optimized formats (.ogg, .mp3) if original path missing or to override
	var final_path = path
	var base_path = path.get_base_dir() + "/" + path.get_file().get_basename()
	
	# Priority: Configured Path > WAV > OGG > MP3
	# But if input is .wav, we might want to swap TO compressed for music, or keep WAV for SFX.
	# The previous logic replaced wav with mp3. Let's make it smarter:
	
	# If specific file exists, keep it (unless we want to force override, but let's trust the call first)
	if not ResourceLoader.exists(path):
		# Try to find an alternative with standard extensions
		for ext in [".wav", ".ogg", ".mp3"]: # Wav first (quality), then Ogg, then MP3
			var try_path = base_path + ext
			if ResourceLoader.exists(try_path):
				final_path = try_path
				break
	
	# Special case: If path requests .mp3 but .ogg exists, prefer .ogg (better looping/latency)
	if final_path.ends_with(".mp3"):
		var ogg_path = final_path.replace(".mp3", ".ogg")
		if ResourceLoader.exists(ogg_path):
			final_path = ogg_path
			
	if _stream_cache.has(final_path):
		return _stream_cache[final_path]
		
	print("AudioDirector: loading stream from path: ", final_path)
	var stream: AudioStream = ResourceLoader.load(final_path)
	if stream == null:
		push_warning("AudioDirector: Failed to load stream %s" % final_path)
		return null
		
	_stream_cache[final_path] = stream
	_stream_cache[path] = stream # Cache under original path too to save lookups
	return stream

func _stream_exists(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path)

func _ensure_loop_state(stream: AudioStream, should_loop: bool) -> AudioStream:
	if stream == null:
		return null
	
	# Modify directly to avoid duplication issues
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var desired := AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
		if wav.loop_mode != desired:
			wav.loop_mode = desired
		return wav
		
	if stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		if mp3.loop != should_loop:
			mp3.loop = should_loop
		return mp3
		
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		if ogg.loop != should_loop:
			ogg.loop = should_loop
		return ogg
		
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

func _db_to_amp(db: float) -> float:
	return pow(10.0, db / 20.0)

func _amp_to_db(amp: float) -> float:
	if amp <= 0.000001:
		return -80.0
	return 20.0 * (log(amp) / log(10.0))

func _ambient_crossfade_step(current: AudioStreamPlayer, next: AudioStreamPlayer) -> void:
	# Increment progress and update volumes using linear amplitude mix so combined amplitude is constant
	_ambient_crossfade_progress += _ambient_crossfade_step_dt
	var t: float = clamp(_ambient_crossfade_progress / AMBIENT_CROSSFADE, 0.0, 1.0)
	# Use equal-power curve (cosine / sine) so perceived loudness stays constant
	var theta: float = t * PI * 0.5
	var w_cur: float = cos(theta)
	var w_next: float = sin(theta)
	var base_amp: float = _db_to_amp(_ambient_base_db)
	var amp_current: float = base_amp * w_cur
	var amp_next: float = base_amp * w_next
	if is_instance_valid(current):
		current.volume_db = _amp_to_db(amp_current)
	if is_instance_valid(next):
		next.volume_db = _amp_to_db(amp_next)
	# Finish crossfade
	if t >= 1.0:
		if _ambient_crossfade_step_timer != null and not _ambient_crossfade_step_timer.is_stopped():
			_ambient_crossfade_step_timer.stop()
		if is_instance_valid(current):
			current.stop()
		_ambient_use_b = !_ambient_use_b

func _ambient_crossfade_tick() -> void:
	# Called by the ambient loop timer to crossfade between A and B players.
	if _ambient_player_a == null or _ambient_player_b == null:
		return
	# Determine which player is currently active and which is next
	var current := _ambient_player_b if _ambient_use_b else _ambient_player_a
	var next := _ambient_player_a if _ambient_use_b else _ambient_player_b
	# Prepare next player and start at beginning; use a step timer to update linear amplitude crossfade
	# Ensure any existing crossfade step timer is stopped
	if _ambient_crossfade_step_timer != null and not _ambient_crossfade_step_timer.is_stopped():
		_ambient_crossfade_step_timer.stop()
	# Reset progress
	_ambient_crossfade_progress = 0.0
	# Ensure next starts silent and at the beginning
	next.volume_db = -80.0
	if next.playing:
		next.stop()
	next.play(0.0)
	# Prepare step timer
	if _ambient_crossfade_step_timer == null:
		_ambient_crossfade_step_timer = Timer.new()
		_ambient_crossfade_step_timer.one_shot = false
		_ambient_crossfade_step_timer.wait_time = _ambient_crossfade_step_dt
		add_child(_ambient_crossfade_step_timer)
		_ambient_crossfade_step_timer.timeout.connect(func(): _ambient_crossfade_step(current, next))
	else:
		_ambient_crossfade_step_timer.wait_time = _ambient_crossfade_step_dt
	# Start stepping
	_ambient_crossfade_step_timer.start()

# --- MUSIC PLAYER API ---

func _update_playlist() -> void:
	# Use ResourceManifest for export compatibility
	ResourceManifest.ensure_initialized()
	_playlist.clear()
	
	# Get battle music from manifest (works in both editor and exports)
	var all_files: Array[String] = ResourceManifest.battle_music.duplicate()
	
	# Also add main menu if not already included
	var menu_path = "res://assets/sounds/music/menu/main-menu.mp3"
	if ResourceLoader.exists(menu_path) and menu_path not in all_files:
		all_files.append(menu_path)
		
	for file_path in all_files:
		var file_id = file_path.get_file().get_basename().to_lower()
		if MUSIC_METADATA.has(file_id):
			var data = MUSIC_METADATA[file_id]
			var unlock_id = data.get("unlock_id", "")
			
			if unlock_id == "" or (AchievementManager and AchievementManager.is_achievement_unlocked(unlock_id)):
				_playlist.append(file_path)
		else:
			# Include unlisted tracks too (they'll show capitalized filename)
			_playlist.append(file_path)

func play_next_random_song(force_start: bool = false) -> void:
	# Always refresh playlist to pick up newly unlocked songs
	_update_playlist()
	if _playlist.is_empty(): return
	
	# Shuffle queue system: play all songs once before reshuffling
	if _shuffled_queue.is_empty():
		_shuffled_queue = _playlist.duplicate()
		_shuffled_queue.shuffle()
		# If current song is first in new shuffle, move it to end to avoid immediate repeat
		if _shuffled_queue.size() > 1 and _shuffled_queue[0] == _current_track_path:
			var first = _shuffled_queue.pop_front()
			_shuffled_queue.append(first)
	
	# Pop next song from shuffled queue
	var next_path = _shuffled_queue.pop_front()
	play_music_file(next_path)

func play_prev_song() -> void:
	if _history.size() <= 1:
		# Current + 0 Previous implies we just started or history empty
		# Start over current or pick random? 
		# "Hitting back goes back to the previous songs, not a random one."
		# If no previous, maybe just restart current?
		if _music_player and _music_player.playing:
			_music_player.seek(0.0)
		return
		
	# Pop current
	_history.pop_back()
	# Peek previous
	var prev_path = _history[_history.size() - 1]
	# Pop previous so play_music_file re-adds it correctly (or just handle history manually?)
	# Let's handle manually:
	_play_track_internal(prev_path, false) # Don't add to history again

func play_music_file(path: String) -> void:
	_play_track_internal(path, true)

func _play_track_internal(path: String, add_to_history: bool) -> void:
	if add_to_history:
		_history.append(path)
		if _history.size() > 20: # Cap available history
			_history.pop_front()
	
	_current_track_path = path
	play_music_by_path(path, true, 0.5)
	
	_is_paused_by_user = false

func toggle_pause_music() -> void:
	if _music_player == null: return
	
	if _music_player.stream_paused:
		_music_player.stream_paused = false
		_is_paused_by_user = false
		emit_signal("music_playback_state_changed", true)
	else:
		_music_player.stream_paused = true
		_is_paused_by_user = true
		emit_signal("music_playback_state_changed", false)

func get_playback_progress() -> float:
	if _music_player and _music_player.playing and not _music_player.stream_paused:
		var len = _music_player.stream.get_length() if _music_player.stream else 1.0
		if len <= 0: len = 1.0
		return _music_player.get_playback_position() / len
	return 0.0

func get_current_song_name() -> String:
	if _current_track_path == "":
		# Also check _current_music_path as fallback
		if _current_music_path != "":
			var file_id = _current_music_path.get_file().get_basename().to_lower()
			if MUSIC_METADATA.has(file_id):
				return MUSIC_METADATA[file_id]["name"]
			return file_id.capitalize()
		return "No Music"
	var file_id = _current_track_path.get_file().get_basename().to_lower()
	if MUSIC_METADATA.has(file_id):
		return MUSIC_METADATA[file_id]["name"]
	# Fallback: try to make the filename readable
	return file_id.capitalize()
