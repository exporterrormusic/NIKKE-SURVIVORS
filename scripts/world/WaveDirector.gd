extends Node
class_name WaveDirector

## Wave-based director for stage runs
## Manages time-based spawning, events, and intensity pacing (DDA)

signal enemy_spawn_requested(enemy_type: String, count: int, pattern: String)
signal event_started(event_type: String, event_data: Dictionary)
signal event_ended(event_type: String)
signal boss_incoming(boss_type: String, time_until: float)
signal run_complete(survived: bool, final_time: float)
signal time_updated(elapsed: float, remaining: float)
signal wave_changed(wave_number: int)
signal rapture_event_started()

# Run settings
const WAVE_DURATION := 30.0
const TOTAL_WAVES := 12 # 12 Waves defined in script
const RUN_DURATION := WAVE_DURATION * TOTAL_WAVES

# 12-WAVE SCRIPT
# Defines the specific behavior for each wave
# rate: Spawns per second (Target: ~4.0 for 120/wave)
# max: Max concurrent enemies
var WAVE_SCRIPT := {
	1:  { "rate": 2.5, "max": 40, "event_type": "", "event_count": 0, "unlocks": ["basic"] },
	2:  { "rate": 2.7, "max": 45, "event_type": "spawn_tanks", "event_count": 3, "unlocks": ["basic", "tank"] },
	3:  { "rate": 2.9, "max": 50, "event_type": "spawn_exploders", "event_count": 3, "unlocks": ["basic", "tank", "exploder"] },
	4:  { "rate": 3.1, "max": 55, "event_type": "spawn_shielders", "event_count": 2, "unlocks": ["basic", "tank", "exploder", "shielder"] },
	5:  { "rate": 3.3, "max": 60, "event_type": "spawn_elites", "event_count": 3, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] },
	6:  { "rate": 3.5, "max": 55, "event_type": "boss", "event_count": 1, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] },
	7:  { "rate": 3.0, "max": 50, "event_type": "", "event_count": 0, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] }, # Breather
	8:  { "rate": 3.7, "max": 65, "event_type": "boost_shielders", "event_count": 0, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] },
	9:  { "rate": 4.0, "max": 70, "event_type": "boss", "event_count": 1, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] },
	10: { "rate": 4.5, "max": 75, "event_type": "super_boss_plus", "event_count": 1, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] },
	11: { "rate": 3.5, "max": 60, "event_type": "gate_super_bosses", "event_count": 3, "unlocks": ["basic", "tank", "exploder", "shielder", "elite"] }, # FINAL WAVE gate
	12: { "rate": 0.0, "max": 0,  "event_type": "n01", "event_count": 1, "unlocks": [] }, # N01 Solo
}

# Unit Weights (Ratios)
# Basic: 30
# Tank: 10 (1:3)
# Exploder: 3 (1:3 Tanks)
# Shielder: 1 (1:10 Tanks)
# Elite: 1 (1:10 Tanks)
var SPAWN_WEIGHTS := {
	"basic": 30,
	"tank": 10,
	"exploder": 3,
	"shielder": 1,
	"elite": 1
}

# State
var _elapsed_time := 0.0
var _active := false
var _paused := false
var _spawn_timer := 0.0
var _current_wave := 1
var _last_wave := 0
var _current_enemy_count := 0
var _boss_active := false
var _bosses_remaining := 0
var _intensity_multiplier := 1.0 # DDA Multiplier
var _active_event: Dictionary = {}
var _gate_active := false # Wave 11 Gate
var _n01_active := false # Wave 12

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func start() -> void:
	_elapsed_time = 0.0
	_active = true
	_paused = false
	_spawn_timer = 0.0
	_current_wave = 1
	_last_wave = 0
	_intensity_multiplier = 1.0
	_gate_active = false
	_n01_active = false
	_boss_active = false
	_bosses_remaining = 0
	emit_signal("time_updated", 0.0, RUN_DURATION)
	_update_wave_state()

func stop() -> void:
	_active = false

func set_enemy_count(count: int) -> void:
	_current_enemy_count = count

func notify_boss_defeated(is_super: bool = false) -> void:
	if _bosses_remaining > 0:
		_bosses_remaining -= 1
	
	# Check Wave 11 Gate
	if _gate_active and _bosses_remaining <= 0:
		_gate_active = false
		_start_wave_12() # Proceed to N01

	# Check Game Win (N01)
	if _n01_active:
		_win_game()

func notify_rapture_queen_defeated() -> void:
	_win_game()

func _win_game() -> void:
	_active = false
	emit_signal("run_complete", true, _elapsed_time)

func _process(delta: float) -> void:
	if not _active or _paused:
		return
	
	# Pause timer during Gate (Wave 11) or N01 (Wave 12)
	if not _gate_active and not _n01_active:
		_elapsed_time += delta
	
	# Broadcast Time
	var display_max = RUN_DURATION
	if _gate_active or _n01_active:
		display_max = -1.0 # Infinite/Events
	emit_signal("time_updated", _elapsed_time, display_max)
	
	# Wave Logic
	if not _gate_active and not _n01_active:
		_update_wave_progress()
	
	# Spawning
	_process_spawning(delta)

func _update_wave_progress() -> void:
	# Calculate current wave based on time (30s intervals)
	var time_wave = int(_elapsed_time / WAVE_DURATION) + 1
	time_wave = min(time_wave, 11) # Cap at 11 by time (12 is manual trigger)
	
	if time_wave != _current_wave:
		_current_wave = time_wave
		_update_wave_state()

func _update_wave_state() -> void:
	if _current_wave > TOTAL_WAVES: return
	
	emit_signal("wave_changed", _current_wave)
	EventBus.wave_started.emit(_current_wave)
	
	# DDA Check (Only if not Gate/N01)
	if not _gate_active and not _n01_active:
		_calculate_dda()
	
	# Trigger Event
	_trigger_wave_event()

func _calculate_dda() -> void:
	# DDA Logic: Check enemy count
	# < 5: Crushing (1.5x)
	# 5-40: On Pace (1.0x)
	# > 40: Struggling (0.5x)
	
	if _current_enemy_count <= 5:
		_intensity_multiplier = 1.5
		print("[Director] CRUSHING! Intensity -> 1.5x")
	elif _current_enemy_count > 40:
		_intensity_multiplier = 0.5
		print("[Director] STRUGGLING! Intensity -> 0.5x")
	else:
		_intensity_multiplier = 1.0
		print("[Director] ON PACE. Intensity -> 1.0x")

func _trigger_wave_event() -> void:
	var data = WAVE_SCRIPT.get(_current_wave, {})
	var type = data.get("event_type", "")
	var count = data.get("event_count", 0)
	
	# Wave 11 Gate
	if type == "gate_super_bosses":
		_gate_active = true
		_bosses_remaining = count
		emit_signal("enemy_spawn_requested", "super_boss", count, "center")
		emit_signal("event_started", "boss_gate", {"count": count, "name": "FINAL WAVE"})
		return

	# Instant Spawns (Tanks, Exploders, Elites)
	if type in ["spawn_tanks", "spawn_exploders", "spawn_shielders", "spawn_elites"]:
		var unit = "tank"
		if type == "spawn_exploders": unit = "exploder"
		if type == "spawn_shielders": unit = "shielder"
		if type == "spawn_elites": unit = "elite"
		
		emit_signal("enemy_spawn_requested", unit, count, "horde")
		emit_signal("event_started", "wave_spawn", {"unit": unit, "count": count})
	
	# Bosses
	if type == "boss":
		emit_signal("enemy_spawn_requested", "boss", count, "center")
		emit_signal("event_started", "boss", {"count": count})
	
	if type == "super_boss_plus":
		emit_signal("enemy_spawn_requested", "super_boss", 1, "center")
		emit_signal("enemy_spawn_requested", "boss", 2, "center")
		emit_signal("event_started", "boss", {"count": 3, "name": "TITAN SQUAD"})

func _start_wave_12() -> void:
	_current_wave = 12
	_n01_active = true
	emit_signal("wave_changed", 12)
	EventBus.wave_started.emit(12)
	
	# Spawn N01
	emit_signal("rapture_event_started") # Trigger legacy event/music if needed
	# Actually spawn the queen
	# Assuming EnemySpawner handles "n01" request or we use the specific signal
	# But WaveDirector usually requests spawns. 
	# EnemySpawner has `spawn_rapture_queen()`. Let's assume we can request it or strict bind.
	
	# For now, use a special signal or type "rapture_queen"
	# EnemySpawner logic might need a tweak if "rapture_queen" isn't a standard str
	# Checking EnemySpawner... it has `spawn_rapture_queen()`.
	# We'll rely on `rapture_event_started` signal potentially OR allow "rapture_queen" type.
	# Let's emit a specific intent.
	var spawner = get_tree().get_first_node_in_group("enemy_spawners")
	if spawner and spawner.has_method("spawn_rapture_queen"):
		spawner.spawn_rapture_queen()

func _process_spawning(delta: float) -> void:
	# Wave 12: No stream
	if _current_wave == 12: return
	
	var data = WAVE_SCRIPT.get(_current_wave, {})
	var base_rate = data.get("rate", 2.0)
	var base_max = data.get("max", 50)
	
	# Apply DDA
	var actual_rate = base_rate * _intensity_multiplier
	var actual_max = int(base_max * _intensity_multiplier)
	
	if _current_enemy_count >= actual_max:
		return
		
	_spawn_timer += delta
	var interval = 1.0 / max(0.1, actual_rate)
	
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		var unit = _pick_weighted_enemy()
		emit_signal("enemy_spawn_requested", unit, 1, "ring")

func _pick_weighted_enemy() -> String:
	var unlocks: Array = WAVE_SCRIPT.get(_current_wave, {}).get("unlocks", ["basic"])
	var total_weight = 0
	var current_weights = SPAWN_WEIGHTS.duplicate()
	
	# Wave 8 Boost
	if _current_wave == 8:
		current_weights["shielder"] = 3 # Boost from 1 to 3 (1:3 Tanks approx)
	
	# Calculate total based on what is UNLOCKED
	for u in unlocks:
		total_weight += current_weights.get(u, 0)
	
	var roll = _rng.randi() % total_weight
	var cum = 0
	for u in unlocks:
		cum += current_weights.get(u, 0)
		if roll < cum:
			return u
	return "basic"

func get_health_multiplier() -> float:
	# Linear scaling: 1x per wave (Wave 1 = 1x, Wave 2 = 2x, etc.)
	return float(_current_wave)

# Helpers
func get_current_wave() -> int: return _current_wave
func is_active() -> bool: return _active
func get_elapsed_time() -> float: return _elapsed_time
func format_time(seconds: float) -> String:
	var m = int(seconds / 60)
	var s = int(seconds) % 60
	return "%d:%02d" % [m, s]
func debug_jump_to_wave(w: int) -> void:
	if w < 12:
		_elapsed_time = (w - 1) * 30.0
		_update_wave_progress()
	else:
		_start_wave_12()
