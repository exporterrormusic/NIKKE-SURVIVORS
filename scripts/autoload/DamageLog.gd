extends Node
class_name DamageLog
## Tracks recent damage taken by player for debugging/UI display.
## Lazy singleton — created on first access.

const MAX_ENTRIES := 20

static var _instance: DamageLog = null

static func get_instance() -> DamageLog:
	if _instance == null:
		_instance = DamageLog.new()
		_instance.name = "DamageLog"
		if Engine.get_main_loop():
			Engine.get_main_loop().root.add_child(_instance)
	return _instance

# Each entry: {source: String, type: String, amount: int, time: float}
var _entries: Array[Dictionary] = []

## Log a damage event. Called from PlayerHealth.take_damage().
func log_damage(source_name: String, damage_type: String, amount: int) -> void:
	var entry := {
		"source": source_name if source_name != "" else "Unknown",
		"type": damage_type if damage_type != "" else "hit",
		"amount": amount,
		"time": Time.get_ticks_msec() / 1000.0
	}
	
	_entries.append(entry)
	
	# Ring buffer - remove oldest if over limit
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)

## Get all logged entries (newest last).
func get_entries() -> Array[Dictionary]:
	return _entries

## Get entries in reverse order (newest first) for display.
func get_entries_reversed() -> Array[Dictionary]:
	var reversed: Array[Dictionary] = []
	for i in range(_entries.size() - 1, -1, -1):
		reversed.append(_entries[i])
	return reversed

## Clear all entries (called on run start).
func clear() -> void:
	_entries.clear()

## Get formatted time string for an entry.
static func format_time(entry: Dictionary) -> String:
	var t: float = entry.get("time", 0.0)
	var mins := int(t) / 60
	var secs := int(t) % 60
	return "%d:%02d" % [mins, secs]
