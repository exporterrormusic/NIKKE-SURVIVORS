extends Area2D


# This component handles receiving hits from projectiles/weapons.
# It delegates the damage logic to a HealthComponent.

@export var health_component: Node
@export var team: String = "enemy" # "player" or "enemy"


signal hit_received(damage, source_node)

func _ready() -> void:
	# Standard setup for enemy hitboxes
	if team == "enemy":
		collision_layer = 4 # Enemy layer usually
		collision_mask = 2  # Projectiles
	
	# Auto-find health component if not assigned
	if not health_component:
		health_component = get_parent().get_node_or_null("HealthComponent")

# The method projectiles call (polymorphic compatibility with existing system)
func take_damage(amount: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, is_burst: bool = false, source: String = "unknown") -> void:
	# DebugLog.log("[Hitbox] take_damage: " + str(amount) + " from " + source)
	hit_received.emit(amount, null) # For visuals
	
	# Spawn Damage Number (Restored)
	# Spawn Damage Number (Restored)
	if FloatingDamageNumber and is_inside_tree():
		var tree = get_tree()
		if tree and tree.current_scene:
			var parent = tree.current_scene
			if is_crit:
				FloatingDamageNumber.spawn_critical(parent, global_position, amount)
			else:
				FloatingDamageNumber.spawn_damage(parent, global_position, amount)
	
	# Check for parent entity and apply modifiers
	var parent = get_parent()
	var final_damage = amount
	if parent:
		# Vulnerability (Scarlet Talent)
		if parent.has_meta("damage_vulnerability"):
			final_damage = int(final_damage * float(parent.get_meta("damage_vulnerability")))
			
		# Super Boss Reduction (Goddess Fall)
		if parent.has_meta("super_boss_damage_reduction"):
			var reduction = float(parent.get_meta("super_boss_damage_reduction"))
			final_damage = int(final_damage * (1.0 - reduction))
			
	if health_component:
		health_component.damage(final_damage, source)
	
	# Add burst charge to player (unless this hit is from a burst attack)
	if team == "enemy" and not is_burst and is_inside_tree():
		var tree = get_tree()
		if tree:
			var player = tree.get_first_node_in_group("player")
			if player and player.has_method("add_burst_charge"):
				# Skip burst sources
				if not BurstConfig.is_burst_source(source):
					var burst_rate := BurstConfig.get_rate(source)
					player.add_burst_charge(burst_rate)
	
	# Emit damage_dealt to EventBus for stats tracking
	if EventBus and team == "enemy":
		# Create a simple DamageInfo-like dict
		var damage_info = {"amount": final_damage, "source": source, "is_crit": is_crit}
		EventBus.damage_dealt.emit(get_parent(), damage_info)
	
	# Optional: Knockback logic via MovementComponent could go here or signal up
