class_name PlayerTalentBridge
extends Node
## Manages the run's talent tree UI for PlayerCore: creation, opening on
## level-up/TAB, skill point granting, and the skill-points notification.
## Gameplay application of unlocked talents stays in PlayerCore (it listens
## to this component's talent_unlocked signal).
## Extracted from PlayerCore for modularity.

signal talent_unlocked(char_id: int, talent_id: String)

var _player: PlayerCore = null
var _skill_points_notify: SkillPointsNotification = null


func initialize(player: PlayerCore) -> void:
	_player = player


func _get_canvas() -> Node:
	var canvas = _player.get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	return canvas


func get_tree_node() -> Control:
	return _get_canvas().get_node_or_null("TalentTree")


## Get the run's talent tree, creating it (hidden) if it doesn't exist yet.
## Pre-created at run start so opening on level-up has no load stutter.
func ensure_tree() -> Control:
	var existing = get_tree_node()
	if existing:
		return existing

	# Create new talent tree using preload for proper initialization
	var TalentTreeScript = preload("res://scripts/ui/TalentTree.gd")
	var tree = TalentTreeScript.new()
	tree.name = "TalentTree"

	# For Controls in CanvasLayer, we need to set anchors properly
	tree.anchor_left = 0.0
	tree.anchor_top = 0.0
	tree.anchor_right = 1.0
	tree.anchor_bottom = 1.0
	tree.offset_left = 0.0
	tree.offset_top = 0.0
	tree.offset_right = 0.0
	tree.offset_bottom = 0.0

	_get_canvas().add_child(tree)

	# Connect signals
	tree.talent_unlocked.connect(_on_tree_talent_unlocked)
	tree.tree_closed.connect(_on_tree_closed)

	# Run-only points: start with whatever progression has banked (usually 0)
	tree.set_skill_points(_player._progression.get_skill_points() if _player._progression else 0)
	return tree


func show_tree() -> void:
	var tree := ensure_tree()
	if tree == null:
		return

	# Hide skill points notification while tree is open
	hide_notification()

	tree.show_tree(_player)
	_player.shop_open = true
	if _player.get_parent().has_method("set_game_paused"):
		_player.get_parent().call_deferred("set_game_paused", true)


func get_talent_level(char_id: int, talent_id: String) -> int:
	var tree := get_tree_node()
	if tree and tree.has_method("get_talent_level"):
		return tree.get_talent_level(char_id, talent_id)
	return 0


## Grant points on level up (does not open the tree; PlayerCore decides that)
func grant_points(amount: int) -> void:
	var tree := ensure_tree()
	if tree:
		tree.add_skill_points(amount)


func add_skill_points(amount: int) -> void:
	# The talent tree is the source of truth for run skill points
	var tree := ensure_tree()
	if tree:
		tree.add_skill_points(amount)
		if _player._progression:
			_player._progression.set_skill_points(tree.get_skill_points())
		update_notification(tree.get_skill_points())
	elif _player._progression:
		_player._progression.add_skill_points(amount)
		update_notification(_player._progression.get_skill_points())

	if _player.overhead_hud:
		_player.overhead_hud.update_skill_points_available(true)


func update_notification(points: int) -> void:
	"""Show or update the skill points notification."""
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		_skill_points_notify = SkillPointsNotification.create(_get_canvas())

	_skill_points_notify.show_notification(points)


func hide_notification() -> void:
	if _skill_points_notify and is_instance_valid(_skill_points_notify):
		_skill_points_notify.show_notification(-1) # -1 = hide


func _on_tree_talent_unlocked(char_id: int, talent_id: String) -> void:
	# Forward to PlayerCore for gameplay application
	talent_unlocked.emit(char_id, talent_id)

	# Sync progression skill points
	var tree := get_tree_node()
	if tree and _player._progression and tree.has_method("get_skill_points"):
		_player._progression.set_skill_points(tree.get_skill_points())


func _on_tree_closed() -> void:
	_player.shop_open = false
	if _player.get_parent().has_method("set_game_paused"):
		_player.get_parent().call_deferred("set_game_paused", false)

	var tree := get_tree_node()
	if tree and _player.overhead_hud:
		_player.overhead_hud.update_skill_points_available(tree.get_skill_points() > 0)

	# Update skill points notification
	if tree:
		update_notification(tree.get_skill_points())
