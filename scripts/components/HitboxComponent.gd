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
		collision_mask = 2 # Projectiles
	
	# Auto-find health component if not assigned
	if not health_component:
		health_component = get_parent().get_node_or_null("HealthComponent")
		
		# EXPORT FIX: If still null, try finding by type/group (desperate search)
		if not health_component:
			for child in get_parent().get_children():
				if child.name.contains("Health") or child.has_signal("health_changed"):
					health_component = child
					break


# The method projectiles call (polymorphic compatibility with existing system)
func take_damage(amount: int, is_crit: bool = false, _direction: Vector2 = Vector2.ZERO, is_burst: bool = false, source: String = "unknown", skip_floating_text: bool = false) -> void:
	# DebugLog.log("[Hitbox] take_damage: " + str(amount) + " from " + source)
	hit_received.emit(amount, null) # For visuals
	
	# Spawn Damage Number (Restored)
	if not skip_floating_text and FloatingDamageNumber and is_inside_tree():
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
	
	# One Hit Kill Cheat
	if team == "enemy" and CheatManager.is_cheat_active("one_hit_kill"):
		final_damage = 9999999
		is_crit = true # Force crit visual for satisfaction
	
	if parent:
		# Vulnerability (Scarlet Burst / Snow White Weak Point)
		if parent.has_meta("damage_vulnerability"):
			final_damage = int(final_damage * float(parent.get_meta("damage_vulnerability")))

		# Armor-Piercing Ammo (Snow White turret) - stacks on top of Weak Point
		if parent.has_meta("armor_pierce_vulnerability"):
			final_damage = int(final_damage * float(parent.get_meta("armor_pierce_vulnerability")))

		# Super Boss Reduction (Goddess Fall)
		if parent.has_meta("super_boss_damage_reduction"):
			var reduction = float(parent.get_meta("super_boss_damage_reduction"))
			final_damage = int(final_damage * (1.0 - reduction))
			
	if not health_component:
		# EXPORT FIX: Emergency lookup
		health_component = get_parent().get_node_or_null("HealthComponent")
		
	if health_component:
		health_component.damage(final_damage, source)
	else:
		# print("ERROR: HitboxComponent on " + get_parent().name + " has NO HealthComponent! Damage ignored.")
		pass

	
	# Add burst charge to player
	if team == "enemy" and is_inside_tree():
		var tree = get_tree()
		if tree:
			# PERFORMANCE: Use TargetCache instead of tree traversal per hit
			var player = TargetCache.get_player()
			if player and player.has_method("add_burst_charge"):
				# Determine rate based on source
				var burst_rate := BurstConfig.get_rate(source)
				
				# Normal hits (not from burst) generate full amount
				if not is_burst:
					# Skip specific burst sources if they somehow weren't flagged as is_burst
					if not BurstConfig.is_burst_source(source) and source != "summon":
						player.add_burst_charge(burst_rate)
				
				# Burst hits usually generate 0, UNLESS player has a modifier active (e.g. Sin talent)
				elif player.get("burst_gen_on_burst_hit_modifier") > 0.0 and source != "summon":
					# Apply modifier (e.g. 0.3 for 30%)
					var mod: float = player.get("burst_gen_on_burst_hit_modifier")
					var modified_rate: float = burst_rate * mod
					player.add_burst_charge(modified_rate)
	
	# Emit damage_dealt to EventBus for stats tracking
	if EventBus and team == "enemy":
		# Create a simple DamageInfo-like dict
		var damage_info = {"amount": final_damage, "source": source, "is_crit": is_crit}
		EventBus.damage_dealt.emit(get_parent(), damage_info)
	
	# Optional: Knockback logic via MovementComponent could go here or signal up

func reset() -> void:
	"""Reset state for object pooling."""
	monitorable = true
	monitoring = true
	
	# Reset collision layers to defaults if they were messed up
	# Enemy tier: Layer 4 (Enemy Hbox), Mask 2 (Projectiles)
	if team == "enemy":
		collision_layer = 4
		collision_mask = 2
