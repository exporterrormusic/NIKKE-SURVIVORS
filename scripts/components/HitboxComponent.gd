extends Area2D
class_name HitboxComponent

# This component handles receiving hits from projectiles/weapons.
# It delegates the damage logic to a HealthComponent.

@export var health_component: HealthComponent
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
	hit_received.emit(amount, null) # For visuals
	
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
	
	# Optional: Knockback logic via MovementComponent could go here or signal up
