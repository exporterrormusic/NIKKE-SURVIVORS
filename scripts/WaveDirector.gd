extends Node
class_name WaveDirector

## HoloCure-style wave director for 5-minute runs
## Manages time-based spawning, events, and intensity pacing

signal enemy_spawn_requested(enemy_type: String, count: int, pattern: String)
signal event_started(event_type: String, event_data: Dictionary)
signal event_ended(event_type: String)
signal boss_incoming(boss_type: String, time_until: float)
signal run_complete(survived: bool, final_time: float)
signal time_updated(elapsed: float, remaining: float)
signal wave_changed(wave_number: int)  # New signal for wave number changes

# Run settings
const RUN_DURATION := 300.0  # 5 minutes

# Spawn brackets - (start_time, enemies_per_second, max_on_screen, spawn_interval)
const SPAWN_BRACKETS := [
	{"time": 0.0, "rate": 3.0, "max": 25, "interval": 0.33},      # 0:00 - Warmup
	{"time": 15.0, "rate": 5.0, "max": 35, "interval": 0.20},     # 0:15 - Ramp up
	{"time": 30.0, "rate": 7.0, "max": 45, "interval": 0.14},     # 0:30 - Getting busy
	{"time": 60.0, "rate": 10.0, "max": 60, "interval": 0.10},    # 1:00 - Intense
	{"time": 90.0, "rate": 12.0, "max": 70, "interval": 0.08},    # 1:30 - Crazy
	{"time": 120.0, "rate": 15.0, "max": 80, "interval": 0.07},   # 2:00 - Madness
	{"time": 180.0, "rate": 18.0, "max": 90, "interval": 0.055},  # 3:00 - Chaos
	{"time": 240.0, "rate": 20.0, "max": 100, "interval": 0.05},  # 4:00 - Final push
]

# Enemy type unlocks by time
const ENEMY_UNLOCKS := [
	{"time": 0.0, "type": "basic"},        # Basic enemies (shoot + melee)
	{"time": 75.0, "type": "tank"},        # Tank enemies
]

# Scheduled events
const EVENTS := [
	# Horde waves - enemies from one direction
	{"time": 25.0, "type": "horde", "enemy": "basic", "count": 15, "duration": 5.0},
	{"time": 55.0, "type": "horde", "enemy": "basic", "count": 20, "duration": 5.0},
	{"time": 85.0, "type": "horde", "enemy": "basic", "count": 25, "duration": 4.0},
	{"time": 115.0, "type": "horde", "enemy": "basic", "count": 30, "duration": 4.0},
	{"time": 145.0, "type": "horde", "enemy": "basic", "count": 35, "duration": 3.0},
	{"time": 175.0, "type": "horde", "enemy": "tank", "count": 8, "duration": 5.0},
	{"time": 205.0, "type": "horde", "enemy": "basic", "count": 40, "duration": 3.0},
	{"time": 235.0, "type": "horde", "enemy": "basic", "count": 45, "duration": 3.0},
	
	# Elite spawns - single powerful enemy with boss abilities
	{"time": 40.0, "type": "elite", "enemy": "basic"},
	{"time": 70.0, "type": "elite", "enemy": "basic"},
	{"time": 100.0, "type": "elite", "enemy": "basic"},
	{"time": 130.0, "type": "elite", "enemy": "basic"},
	{"time": 160.0, "type": "elite", "enemy": "basic"},
	{"time": 190.0, "type": "elite", "enemy": "basic"},
	{"time": 220.0, "type": "elite", "enemy": "basic"},
	
	# Final boss at 4:30 (30 seconds to kill)
	{"time": 270.0, "type": "boss", "enemy": "boss"},
]

# State
var _elapsed_time := 0.0
var _active := false
var _paused := false
var _spawn_timer := 0.0
var _current_bracket_index := 0
var _unlocked_enemies: Array[String] = []
var _triggered_events: Array[int] = []  # Indices of triggered events
var _active_event: Dictionary = {}
var _event_timer := 0.0
var _current_enemy_count := 0
var _boss_active := false
var _run_won := false
var _current_wave := 1  # Track current wave number
var _last_wave := 0  # For detecting wave changes

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func start() -> void:
	_elapsed_time = 0.0
	_active = true
	_paused = false
	_spawn_timer = 0.0
	_current_bracket_index = 0
	_unlocked_enemies = ["basic"]
	_triggered_events.clear()
	_active_event = {}
	_event_timer = 0.0
	_current_enemy_count = 0
	_boss_active = false
	_run_won = false
	_current_wave = 1
	_last_wave = 0
	emit_signal("time_updated", 0.0, RUN_DURATION)
	emit_signal("wave_changed", 1)

func stop() -> void:
	_active = false

func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false

func set_enemy_count(count: int) -> void:
	_current_enemy_count = count

func notify_boss_defeated() -> void:
	if _boss_active:
		_boss_active = false
		_run_won = true
		emit_signal("run_complete", true, _elapsed_time)
		_active = false

func _process(delta: float) -> void:
	if not _active or _paused:
		return
	
	_elapsed_time += delta
	emit_signal("time_updated", _elapsed_time, RUN_DURATION - _elapsed_time)
	
	# Check for run timeout (survived but didn't kill boss)
	if _elapsed_time >= RUN_DURATION and not _boss_active:
		emit_signal("run_complete", true, _elapsed_time)
		_active = false
		return
	
	# Update spawn bracket
	_update_spawn_bracket()
	
	# Check for enemy type unlocks
	_check_enemy_unlocks()
	
	# Check for scheduled events
	_check_events()
	
	# Process active event
	if not _active_event.is_empty():
		_process_event(delta)
	
	# Normal spawning (reduced during events, stopped during boss)
	if not _boss_active:
		_process_normal_spawning(delta)

func _update_spawn_bracket() -> void:
	for i in range(SPAWN_BRACKETS.size() - 1, -1, -1):
		if _elapsed_time >= SPAWN_BRACKETS[i]["time"]:
			_current_bracket_index = i
			break
	
	# Update wave number based on bracket (wave = bracket + 1)
	_current_wave = _current_bracket_index + 1
	if _current_wave != _last_wave:
		_last_wave = _current_wave
		emit_signal("wave_changed", _current_wave)

func get_current_wave() -> int:
	return _current_wave

func get_health_multiplier() -> float:
	# Wave 1: 1x, Wave 2: 2x, Wave 3: 4x, then +2 each wave (6x, 8x, 10x...)
	if _current_wave <= 3:
		return pow(2.0, _current_wave - 1)  # 1, 2, 4
	else:
		return 4.0 + (_current_wave - 3) * 2.0  # 6, 8, 10...

func _check_enemy_unlocks() -> void:
	for unlock in ENEMY_UNLOCKS:
		if _elapsed_time >= unlock["time"] and not unlock["type"] in _unlocked_enemies:
			_unlocked_enemies.append(unlock["type"])

func _check_events() -> void:
	for i in range(EVENTS.size()):
		if i in _triggered_events:
			continue
		
		var event: Dictionary = EVENTS[i]
		var event_time: float = event["time"]
		
		# Boss warning 10 seconds early
		if event["type"] == "boss" and _elapsed_time >= event_time - 10.0 and _elapsed_time < event_time:
			if not (i * 1000) in _triggered_events:  # Use offset index for warning
				_triggered_events.append(i * 1000)
				emit_signal("boss_incoming", event["enemy"], event_time - _elapsed_time)
		
		# Trigger event at its time
		if _elapsed_time >= event_time:
			_triggered_events.append(i)
			_start_event(event)

func _start_event(event: Dictionary) -> void:
	var event_type: String = event["type"]
	
	match event_type:
		"horde":
			_active_event = event.duplicate()
			_event_timer = 0.0
			emit_signal("event_started", "horde", {"enemy": event["enemy"], "count": event["count"]})
		
		"elite":
			emit_signal("enemy_spawn_requested", event["enemy"], 1, "elite")
			emit_signal("event_started", "elite", {"enemy": event["enemy"]})
			# Elite event is instant
			await get_tree().create_timer(0.1).timeout
			emit_signal("event_ended", "elite")
		
		"boss":
			_boss_active = true
			_active_event = event.duplicate()
			emit_signal("enemy_spawn_requested", "boss", 1, "center")
			emit_signal("event_started", "boss", {})

func _process_event(delta: float) -> void:
	var event_type: String = _active_event.get("type", "")
	
	match event_type:
		"horde":
			_event_timer += delta
			var duration: float = _active_event.get("duration", 5.0)
			var total_count: int = _active_event.get("count", 20)
			var spawn_interval: float = duration / float(total_count)
			
			# Spawn enemies rapidly from one direction
			var spawned: int = _active_event.get("_spawned", 0)
			var spawn_accumulator: float = _active_event.get("_accumulator", 0.0)
			spawn_accumulator += delta
			
			while spawn_accumulator >= spawn_interval and spawned < total_count:
				spawn_accumulator -= spawn_interval
				spawned += 1
				emit_signal("enemy_spawn_requested", _active_event["enemy"], 1, "horde")
			
			_active_event["_spawned"] = spawned
			_active_event["_accumulator"] = spawn_accumulator
			
			if spawned >= total_count:
				emit_signal("event_ended", "horde")
				_active_event = {}

func _process_normal_spawning(delta: float) -> void:
	var bracket: Dictionary = SPAWN_BRACKETS[_current_bracket_index]
	var max_enemies: int = bracket["max"]
	var spawn_interval: float = bracket["interval"]
	
	# Reduce spawn rate during events
	if not _active_event.is_empty():
		spawn_interval *= 2.0
	
	# Don't spawn if at max
	if _current_enemy_count >= max_enemies:
		return
	
	_spawn_timer += delta
	while _spawn_timer >= spawn_interval and _current_enemy_count < max_enemies:
		_spawn_timer -= spawn_interval
		var enemy_type := _pick_random_enemy()
		emit_signal("enemy_spawn_requested", enemy_type, 1, "ring")

func _pick_random_enemy() -> String:
	if _unlocked_enemies.is_empty():
		return "basic"
	
	# Weight towards newer enemy types slightly
	var weights: Array[float] = []
	var total_weight := 0.0
	for i in range(_unlocked_enemies.size()):
		var weight := 1.0 + float(i) * 0.3  # Later unlocks slightly more common
		weights.append(weight)
		total_weight += weight
	
	var roll := _rng.randf() * total_weight
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return _unlocked_enemies[i]
	
	return _unlocked_enemies[0]

func get_elapsed_time() -> float:
	return _elapsed_time

func get_remaining_time() -> float:
	return max(0.0, RUN_DURATION - _elapsed_time)

func is_active() -> bool:
	return _active

func format_time(seconds: float) -> String:
	@warning_ignore("integer_division")
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]
