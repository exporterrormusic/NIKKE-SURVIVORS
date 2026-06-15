extends Node
class_name BurnDOT
## Damage Over Time component that can be attached to enemies
## Handles refreshing and stacking of burn effects

var damage_percent: float = 0.03  # 3% HP per second for regular enemies
var boss_damage_percent: float = 0.01  # 1% HP per second for bosses
var duration: float = 10.0
## Flat-damage mode (used by Snow White's "Burning" talent). When use_flat is
## true, the DoT deals `flat_total` total damage spread evenly over `duration`
## instead of a percentage of the target's max HP.
var use_flat: bool = false
var flat_total: float = 0.0
## Fixed damage-per-second mode (used by Rapunzel's "Endless Desire"). When
## flat_dps > 0 the DoT deals this much damage per second regardless of duration,
## and can be grown via add_stack(). Takes precedence over flat_total.
var flat_dps: float = 0.0
## Permanent mode (used by Rapunzel's "Endless Desire"): the DoT never expires on
## its own and only ends when the target dies.
var permanent: bool = false
## Damage source string passed to take_damage (so kill attribution can tell this
## DoT apart from the bullet, explosions, etc.).
var damage_source: String = "burn_dot"
var _timer: float = 0.0
var _tick_interval: float = 0.5
var _tick_timer: float = 0.0
var _target: Node2D = null
var _is_boss: bool = false
var _source_id: String = ""  # Identifier for the source (e.g., "snow_white_burn")

func _ready() -> void:
	_timer = duration

func setup(target: Node2D, source_id: String, duration_override: float = -1.0) -> void:
	_target = target
	_source_id = source_id
	_is_boss = target.is_in_group("bosses") or target.is_in_group("elite")
	if duration_override > 0:
		duration = duration_override
	_timer = duration

func refresh() -> void:
	## Refresh the burn duration to full
	_timer = duration

func add_stack(dps_add: float) -> void:
	## Grow a fixed-DPS (Endless Desire) DoT by another stack's worth of damage.
	flat_dps += dps_add

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	# Permanent DoTs (Endless Desire) only end when the target dies.
	if not permanent:
		_timer -= delta
		if _timer <= 0:
			queue_free()
			return

	_tick_timer += delta
	if _tick_timer >= _tick_interval:
		_tick_timer = 0.0
		_apply_damage()

func _apply_damage() -> void:
	if not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	
	# Get target's max HP if available
	var max_hp: int = 100
	if "max_hp" in _target:
		max_hp = _target.max_hp
	elif _target.has_method("get_max_hp"):
		max_hp = _target.get_max_hp()
	
	# Calculate per-tick damage. Flat mode: spread flat_total evenly over the
	# duration. Percent mode: a fraction of the target's max HP.
	var damage: int
	if flat_dps > 0.0:
		damage = int(round(flat_dps * _tick_interval))
	elif use_flat:
		damage = int(round(flat_total * _tick_interval / maxf(duration, 0.001)))
	else:
		var percent := boss_damage_percent if _is_boss else damage_percent
		damage = int(max_hp * percent * _tick_interval)
	damage = maxi(damage, 1)  # At least 1 damage per tick

	# Apply damage without crit (burn is consistent damage)
	_target.take_damage(damage, false, Vector2.ZERO, false, damage_source)
