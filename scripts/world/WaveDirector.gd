extends Node
class_name WaveDirector

## 10-minute, time-keyed survival director.
## Difficulty comes from tougher enemy TYPES entering over time (flat per-type stats),
## a mini-boss roughly every 2 minutes, and a boss finale at 10:00 that ends the run.
## Enemy stats are absolute and live in EnemyTierConfig (the survivor roster tiers).

signal enemy_spawn_requested(enemy_type: String, count: int, pattern: String)
signal event_started(event_type: String, event_data: Dictionary)
signal event_ended(event_type: String)
signal boss_incoming(boss_type: String, time_until: float)
signal run_complete(survived: bool, final_time: float)
signal time_updated(elapsed: float, remaining: float)
signal wave_changed(wave_number: int)
signal wave_reward_earned(count: int)
signal rapture_event_started()

# Run settings
const RUN_DURATION := 600.0  # 10 minutes; finale boss spawns at this mark
const WAVE_TICK := 30.0      # display / EventBus "wave" cadence (UI + per-wave listeners)
const TOTAL_WAVES := 20

# Dominant trash type by elapsed time (s), sorted ascending.
# The latest entry whose time has passed becomes the streamed trash type.
const TRASH_STEPS := [
	[0.0, "swarmer"], [60.0, "trooper"], [150.0, "marauder"],
	[270.0, "brute"], [360.0, "enforcer"], [450.0, "harrier"],
	[540.0, "devastator"],
]
# Fast / swarm types added to the spawn pool at these times.
const FAST_INTRO := [[240.0, "skitter"], [570.0, "lunger"]]
# One-shot mini-boss spawns (~every 2 minutes).
const MINIBOSSES := [
	[120.0, "warden"], [240.0, "breaker"],
	[360.0, "colossus"], [480.0, "leviathan"],
]

# State
var _elapsed_time := 0.0
var _active := false
var _paused := false
var _spawn_timer := 0.0
var _current_wave := 0
var _current_enemy_count := 0
var _finale_active := false
var _current_trash := "swarmer"
var _fast_pool: Array = []
var _next_miniboss := 0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func start() -> void:
	_elapsed_time = 0.0
	_active = true
	_paused = false
	_spawn_timer = 0.0
	_current_wave = 0
	_finale_active = false
	_current_trash = "swarmer"
	_fast_pool = []
	_next_miniboss = 0
	emit_signal("time_updated", 0.0, RUN_DURATION)
	_update_wave_tick()

func stop() -> void:
	_active = false

func set_enemy_count(count: int) -> void:
	_current_enemy_count = count

func _process(delta: float) -> void:
	if not _active or _paused:
		return

	# Pause the run clock during the untimed finale fight.
	if not _finale_active:
		_elapsed_time += delta

	var display_max := RUN_DURATION if not _finale_active else -1.0
	emit_signal("time_updated", _elapsed_time, display_max)

	if _finale_active:
		return

	_update_wave_tick()
	_update_trash_and_fast()
	_check_minibosses()
	_check_finale()
	_process_spawning(delta)

## Tick a 30s "wave" purely for the HUD and per-wave EventBus listeners
## (Commander wave-heal, shop rewards). Spawning is driven by the time schedule.
func _update_wave_tick() -> void:
	var w := int(_elapsed_time / WAVE_TICK) + 1
	w = mini(w, TOTAL_WAVES)
	if w != _current_wave:
		var prev := _current_wave
		_current_wave = w
		emit_signal("wave_changed", w)
		EventBus.wave_started.emit(w)
		if prev >= 1:
			EventBus.wave_completed.emit(prev)
			_calculate_and_emit_reward(prev)

func _update_trash_and_fast() -> void:
	for step in TRASH_STEPS:
		if _elapsed_time >= step[0]:
			_current_trash = step[1]
	for f in FAST_INTRO:
		if _elapsed_time >= f[0] and not _fast_pool.has(f[1]):
			_fast_pool.append(f[1])

func _check_minibosses() -> void:
	while _next_miniboss < MINIBOSSES.size() and _elapsed_time >= MINIBOSSES[_next_miniboss][0]:
		var mb: String = MINIBOSSES[_next_miniboss][1]
		emit_signal("enemy_spawn_requested", mb, 1, "center")
		emit_signal("event_started", "wave_spawn", {"unit": mb, "count": 1})
		print("[WaveDirector] Mini-boss spawned: %s at %s" % [mb, format_time(_elapsed_time)])
		_next_miniboss += 1

func _check_finale() -> void:
	if _elapsed_time >= RUN_DURATION and not _finale_active:
		_finale_active = true
		_current_wave = TOTAL_WAVES
		emit_signal("wave_changed", TOTAL_WAVES)
		emit_signal("rapture_event_started")
		emit_signal("event_started", "boss", {"count": 1, "name": "FINAL BOSS"})
		# Reuse the proven N01 finale spawn + victory path (Level tracks its death).
		emit_signal("enemy_spawn_requested", "n01_queen", 1, "center")
		print("[WaveDirector] 10:00 reached — FINAL BOSS spawned.")

func _process_spawning(delta: float) -> void:
	var t: float = clampf(_elapsed_time / RUN_DURATION, 0.0, 1.0)
	var rate: float = lerpf(2.5, 6.0, t)        # spawns/sec, smooth ramp
	var max_c: int = int(lerpf(40.0, 130.0, t)) # max concurrent

	if _current_enemy_count >= max_c:
		return

	_spawn_timer += delta
	var interval := 1.0 / maxf(0.1, rate)
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		emit_signal("enemy_spawn_requested", _pick_spawn_type(), 1, "ring")

func _pick_spawn_type() -> String:
	# Occasionally inject an unlocked fast/swarm type; otherwise the current trash.
	if _fast_pool.size() > 0 and _rng.randf() < 0.15:
		return _fast_pool[_rng.randi() % _fast_pool.size()]
	return _current_trash

# --- Victory ---
func notify_boss_defeated(_is_super: bool = false, boss_id: String = "") -> void:
	if boss_id == "n01_queen":
		print("[WaveDirector] Final boss defeated. VICTORY!")
		_win_game()

func notify_rapture_queen_defeated() -> void:
	_win_game()

func _win_game() -> void:
	_active = false
	emit_signal("run_complete", true, _elapsed_time)

# --- Helpers ---
func get_health_multiplier() -> float:
	# HoloCure clone: enemy stats are flat. Difficulty comes from tougher TYPES over time.
	return 1.0

func get_current_wave() -> int: return _current_wave
func is_active() -> bool: return _active
func get_elapsed_time() -> float: return _elapsed_time

func format_time(seconds: float) -> String:
	var m := int(seconds / 60)
	var s := int(seconds) % 60
	return "%d:%02d" % [m, s]

func _calculate_and_emit_reward(_completed_wave: int) -> void:
	# Pristine Cores now drop ONLY from bosses (see Level._spawn_pristine_core_orb_at_boss).
	# Per-wave core rewards were removed so cores aren't handed out during normal waves.
	pass

func debug_jump_to_wave(w: int) -> void:
	if w >= TOTAL_WAVES:
		_elapsed_time = RUN_DURATION
		_check_finale()
		return
	_elapsed_time = maxf(0.0, float(w - 1) * WAVE_TICK)
	_next_miniboss = 0
	while _next_miniboss < MINIBOSSES.size() and MINIBOSSES[_next_miniboss][0] < _elapsed_time:
		_next_miniboss += 1
	_update_trash_and_fast()
	_update_wave_tick()
