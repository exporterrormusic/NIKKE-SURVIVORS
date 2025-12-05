extends Node2D
class_name SuperBossAura

## Super Boss Empowerment Aura (Goddess Fall Mode)
## - Enemies within 2/3 screen distance fire at 2x rate
## - Buffed enemies take 50% less damage
## - Buffed enemies are tinted red

const AURA_RADIUS := 640.0  # ~2/3 of 960 (half screen width)
const BUFF_CHECK_INTERVAL := 0.25  # Check for enemies every 0.25 seconds
const FIRE_RATE_MULT := 2.0  # 2x fire rate
const DAMAGE_REDUCTION := 0.5  # Take 50% less damage

const BUFF_TINT := Color(1.0, 0.5, 0.5, 1.0)  # Red tint for buffed enemies

var _boss: Node2D = null
var _buffed_enemies: Array[Node2D] = []
var _check_timer := 0.0

# Visual effect
var _aura_visual: Node2D = null

func _ready() -> void:
	_boss = get_parent()
	_create_aura_visual()

func _create_aura_visual() -> void:
	# Create pulsing red aura around boss
	_aura_visual = Node2D.new()
	_aura_visual.name = "AuraVisual"
	add_child(_aura_visual)
	_aura_visual.set_script(load("res://scripts/enemies/effects/SuperBossAuraVisual.gd") if ResourceLoader.exists("res://scripts/enemies/effects/SuperBossAuraVisual.gd") else null)

func _process(delta: float) -> void:
	if not is_instance_valid(_boss):
		queue_free()
		return
	
	_check_timer += delta
	if _check_timer >= BUFF_CHECK_INTERVAL:
		_check_timer = 0.0
		_update_buffed_enemies()

func _update_buffed_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var boss_pos := _boss.global_position
	
	# Remove buffs from enemies that left the aura
	for enemy in _buffed_enemies.duplicate():
		if not is_instance_valid(enemy):
			_buffed_enemies.erase(enemy)
			continue
		
		var dist: float = enemy.global_position.distance_to(boss_pos)
		if dist > AURA_RADIUS or enemy == _boss:
			_remove_buff(enemy)
			_buffed_enemies.erase(enemy)
	
	# Add buffs to enemies that entered the aura
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy == _boss:
			continue
		if enemy in _buffed_enemies:
			continue
		
		var dist: float = enemy.global_position.distance_to(boss_pos)
		if dist <= AURA_RADIUS:
			_apply_buff(enemy)
			_buffed_enemies.append(enemy)

func _apply_buff(enemy: Node2D) -> void:
	# Apply red tint
	var sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
	if sprite:
		# Store original modulate
		if not enemy.has_meta("original_modulate"):
			enemy.set_meta("original_modulate", sprite.modulate)
		sprite.modulate = sprite.modulate * BUFF_TINT
	
	# Mark as buffed for damage reduction
	enemy.add_to_group("super_boss_buffed")
	enemy.set_meta("super_boss_damage_reduction", DAMAGE_REDUCTION)
	
	# Increase fire rate if enemy can shoot
	if enemy.has_method("set_fire_rate_multiplier"):
		enemy.set_fire_rate_multiplier(FIRE_RATE_MULT)
	elif "fire_rate" in enemy:
		if not enemy.has_meta("original_fire_rate"):
			enemy.set_meta("original_fire_rate", enemy.fire_rate)
		enemy.fire_rate = enemy.fire_rate / FIRE_RATE_MULT  # Lower = faster

func _remove_buff(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	
	# Restore original tint
	var sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
	if sprite and enemy.has_meta("original_modulate"):
		sprite.modulate = enemy.get_meta("original_modulate")
	
	# Remove buff group
	if enemy.is_in_group("super_boss_buffed"):
		enemy.remove_from_group("super_boss_buffed")
	enemy.remove_meta("super_boss_damage_reduction")
	
	# Restore fire rate
	if enemy.has_method("set_fire_rate_multiplier"):
		enemy.set_fire_rate_multiplier(1.0)
	elif "fire_rate" in enemy and enemy.has_meta("original_fire_rate"):
		enemy.fire_rate = enemy.get_meta("original_fire_rate")

func _exit_tree() -> void:
	# Clean up all buffs when aura is destroyed
	for enemy in _buffed_enemies:
		_remove_buff(enemy)
	_buffed_enemies.clear()
