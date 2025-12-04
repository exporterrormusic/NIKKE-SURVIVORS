extends Node
class_name WaveDirector

## Wave-based director for stage runs
## Manages time-based spawning, events, and intensity pacing

signal enemy_spawn_requested(enemy_type: String, count: int, pattern: String)
signal event_started(event_type: String, event_data: Dictionary)
signal event_ended(event_type: String)
signal boss_incoming(boss_type: String, time_until: float)
signal run_complete(survived: bool, final_time: float)
signal time_updated(elapsed: float, remaining: float)
signal wave_changed(wave_number: int)

# Run settings - 7 waves at 30 seconds each = 3.5 minutes
const WAVE_DURATION := 30.0
const TOTAL_WAVES := 7
const RUN_DURATION := WAVE_DURATION * TOTAL_WAVES  # 210 seconds (3:30)

# Stage difficulty modes
var _stage_mode := 1  # 1 = normal, 2 = hard (tanks replace basic, etc.)

# Spawn brackets - 7 waves at 30 second intervals
# Stage 1: basic enemies, Stage 2: tanks replace basic
const SPAWN_BRACKETS := [
	{"time": 0.0, "rate": 3.0, "max": 25, "interval": 0.33},       # Wave 1 (0:00)
	{"time": 30.0, "rate": 5.0, "max": 35, "interval": 0.20},      # Wave 2 (0:30)
	{"time": 60.0, "rate": 7.0, "max": 45, "interval": 0.14},      # Wave 3 (1:00)
	{"time": 90.0, "rate": 10.0, "max": 55, "interval": 0.10},     # Wave 4 (1:30)
	{"time": 120.0, "rate": 12.0, "max": 65, "interval": 0.08},    # Wave 5 (2:00)
	{"time": 150.0, "rate": 15.0, "max": 75, "interval": 0.07},    # Wave 6 (2:30)
	{"time": 180.0, "rate": 18.0, "max": 85, "interval": 0.055},   # Wave 7 (3:00)
]

# Enemy type unlocks by wave (Stage 1)
# Wave 1: basic only
# Wave 2: tanks unlock
# Wave 3: elites unlock
const ENEMY_UNLOCKS := [
	{"time": 0.0, "type": "basic"},         # Wave 1: Basic enemies
	{"time": 30.0, "type": "tank"},         # Wave 2: Tank enemies
]

# Scheduled events (Stage 1)
# Events trigger at wave start (0, 30, 60, 90, 120, 150, 180)
# Wave 1: Horde
# Wave 2: Horde (tanks unlock)
# Wave 3: Horde + Elite
# Wave 4: Horde + Elite
# Wave 5: Horde + Elite + 1 Boss
# Wave 6: Horde + Elite
# Wave 7: Horde + Elite + 3 Bosses
const EVENTS := [
	# Horde waves - trigger at wave start, last full 30 seconds
	{"time": 0.0, "type": "horde", "enemy": "basic", "count": 15, "duration": 30.0},     # Wave 1
	{"time": 30.0, "type": "horde", "enemy": "basic", "count": 20, "duration": 30.0},    # Wave 2
	{"time": 60.0, "type": "horde", "enemy": "basic", "count": 25, "duration": 30.0},    # Wave 3
	{"time": 90.0, "type": "horde", "enemy": "tank", "count": 12, "duration": 30.0},     # Wave 4
	{"time": 120.0, "type": "horde", "enemy": "basic", "count": 30, "duration": 30.0},   # Wave 5
	{"time": 150.0, "type": "horde", "enemy": "tank", "count": 15, "duration": 30.0},    # Wave 6
	{"time": 180.0, "type": "horde", "enemy": "basic", "count": 35, "duration": 30.0},   # Wave 7
	
	# Elite spawns - at wave start, starting wave 3
	{"time": 60.0, "type": "elite", "enemy": "basic"},    # Wave 3
	{"time": 90.0, "type": "elite", "enemy": "basic"},    # Wave 4
	{"time": 120.0, "type": "elite", "enemy": "basic"},   # Wave 5
	{"time": 150.0, "type": "elite", "enemy": "basic"},   # Wave 6
	{"time": 180.0, "type": "elite", "enemy": "basic"},   # Wave 7
	
	# Boss spawns - at wave start
	{"time": 120.0, "type": "boss", "enemy": "boss", "count": 1},   # Wave 5: 1 boss
	{"time": 180.0, "type": "boss", "enemy": "boss", "count": 3},   # Wave 7: 3 bosses
]

# State
var _elapsed_time := 0.0
var _active := false
var _paused := false
var _spawn_timer := 0.0
var _current_bracket_index := 0
var _unlocked_enemies: Array[String] = []
var _triggered_events: Array[int] = []
var _active_event: Dictionary = {}
var _event_timer := 0.0
var _current_enemy_count := 0
var _boss_active := false
var _bosses_remaining := 0  # Track remaining bosses to defeat
var _run_won := false
var _current_wave := 1
var _last_wave := 0
var _endless_mode := false

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func set_stage_mode(mode: int) -> void:
	_stage_mode = mode
	print("[WaveDirector] Stage mode: ", mode)

func set_endless_mode(enabled: bool) -> void:
	_endless_mode = enabled
	print("[WaveDirector] Endless mode: ", enabled)

func start() -> void:
	_elapsed_time = 0.0
	_active = true
	_paused = false
	_spawn_timer = 0.0
	_current_bracket_index = 0
	# Stage 2: tanks are the base enemy instead of basic
	if _stage_mode == 2:
		_unlocked_enemies = ["tank"]
	else:
		_unlocked_enemies = ["basic"]
	_triggered_events.clear()
	_active_event = {}
	_event_timer = 0.0
	_current_enemy_count = 0
	_boss_active = false
	_bosses_remaining = 0
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
		_bosses_remaining -= 1
		print("[WaveDirector] Boss defeated! Remaining: ", _bosses_remaining)
		if _bosses_remaining <= 0:
			_boss_active = false
			_run_won = true
			emit_signal("run_complete", true, _elapsed_time)
			_active = false

func _process(delta: float) -> void:
	if not _active or _paused:
		return
	
	_elapsed_time += delta
	
	# In endless mode, remaining time is always infinite (show elapsed only)
	if _endless_mode:
		emit_signal("time_updated", _elapsed_time, -1.0)  # -1 signals endless
	else:
		emit_signal("time_updated", _elapsed_time, RUN_DURATION - _elapsed_time)
	
	# Check for run timeout (only in non-endless mode)
	if not _endless_mode and _elapsed_time >= RUN_DURATION and not _boss_active:
		emit_signal("run_complete", true, _elapsed_time)
		_active = false
		return
	
	# Update spawn bracket
	_update_spawn_bracket()
	
	# Check for enemy type unlocks
	_check_enemy_unlocks()
	
	# Check for scheduled events (not in endless mode after first cycle)
	if not _endless_mode or _elapsed_time <= RUN_DURATION:
		_check_events()
	
	# Process active event
	if not _active_event.is_empty():
		_process_event(delta)
	
	# Normal spawning (reduced during events, stopped during boss)
	if not _boss_active:
		_process_normal_spawning(delta)

func _update_spawn_bracket() -> void:
	# In endless mode, we loop through brackets but keep increasing wave number
	var bracket_time := _elapsed_time
	if _endless_mode and _elapsed_time > RUN_DURATION:
		# After 5 minutes, use max bracket settings but keep counting waves
		bracket_time = RUN_DURATION  # Use max bracket
	
	for i in range(SPAWN_BRACKETS.size() - 1, -1, -1):
		if bracket_time >= SPAWN_BRACKETS[i]["time"]:
			_current_bracket_index = i
			break
	
	# Calculate wave number (in endless mode, keep incrementing past normal brackets)
	if _endless_mode:
		# After bracket 8, increment wave every 30 seconds
		if _elapsed_time <= RUN_DURATION:
			_current_wave = _current_bracket_index + 1
		else:
			var extra_time := _elapsed_time - RUN_DURATION
			@warning_ignore("integer_division")
			_current_wave = SPAWN_BRACKETS.size() + int(extra_time / 30.0)
	else:
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
	print("[WaveDirector] Starting event: ", event_type, " - ", event)
	
	# Translate enemy types for Stage 2 (hard mode)
	var translated_enemy := _translate_enemy_type(event.get("enemy", "basic"))
	var translated_type := _translate_event_type(event_type)
	
	match translated_type:
		"horde":
			var translated_event := event.duplicate()
			translated_event["enemy"] = translated_enemy
			_active_event = translated_event
			_event_timer = 0.0
			emit_signal("event_started", "horde", {"enemy": translated_enemy, "count": event["count"]})
		
		"elite":
			print("[WaveDirector] SPAWNING ELITE - enemy_type: ", translated_enemy)
			emit_signal("enemy_spawn_requested", translated_enemy, 1, "elite")
			emit_signal("event_started", "elite", {"enemy": translated_enemy})
			await get_tree().create_timer(0.1).timeout
			emit_signal("event_ended", "elite")
		
		"boss":
			var boss_count: int = event.get("count", 1)
			_boss_active = true
			_bosses_remaining = boss_count
			_active_event = event.duplicate()
			
			# Spawn boss(es) - use super_boss for stage 2
			var boss_type := "super_boss" if _stage_mode == 2 else "boss"
			for i in range(boss_count):
				emit_signal("enemy_spawn_requested", boss_type, 1, "center")
			emit_signal("event_started", "boss", {"count": boss_count})

## Translate enemy types based on stage mode
## Stage 1: normal (basic, tank, elite, boss)
## Stage 2: hard (tank replaces basic, elite replaces tank, boss replaces elite, super_boss replaces boss)
func _translate_enemy_type(enemy_type: String) -> String:
	if _stage_mode != 2:
		return enemy_type
	
	match enemy_type:
		"basic":
			return "tank"
		"tank":
			return "elite_spawn"  # Special marker for spawning as elite
		_:
			return enemy_type

## Translate event types for stage 2
func _translate_event_type(event_type: String) -> String:
	if _stage_mode != 2:
		return event_type
	
	# In stage 2, elite events become boss events
	if event_type == "elite":
		return "boss"
	
	return event_type

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
			
			# Get the translated enemy type from the event
			var enemy_type: String = _active_event.get("enemy", "basic")
			
			while spawn_accumulator >= spawn_interval and spawned < total_count:
				spawn_accumulator -= spawn_interval
				spawned += 1
				# Check if this is an elite_spawn marker (stage 2 tank->elite)
				if enemy_type == "elite_spawn":
					emit_signal("enemy_spawn_requested", "basic", 1, "elite")
				else:
					emit_signal("enemy_spawn_requested", enemy_type, 1, "horde")
			
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
