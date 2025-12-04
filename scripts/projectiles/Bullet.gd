extends Area2D

@onready var sprite = $Sprite2D

var velocity = Vector2.ZERO
var lifetime: float = 0.0
var owner_node: Node = null

# If true, bullet will pierce every damageable target it hits (doesn't queue_free on hit)
@export var pierce_all: bool = false
# Optional limited pierce count; 0 = unlimited when pierce_all is true
@export var pierce_count: int = 0

# Critical hit settings
const CRIT_CHANCE := 0.15  # 15% chance to crit
const CRIT_MULTIPLIER := 2.0  # 2x damage on crit
var base_damage := 3

var _hit_nodes: Array = []

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	
	# Use unshaded material with brightness boost for bloom - preserves sprite color
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = _create_glow_shader()
	shader_mat.set_shader_parameter("brightness_boost", 1.4)  # Boost brightness for bloom
	$Sprite2D.material = shader_mat
	
	# Add dynamic point light for real-time lighting
	var light = PointLight2D.new()
	light.name = "BulletLight"
	light.color = Color(1.0, 0.95, 0.7)  # Warm bullet glow
	light.energy = 0.4
	light.texture = _create_light_texture()
	light.texture_scale = 0.15
	light.shadow_enabled = false  # Bullets don't need shadows
	add_child(light)

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

# Unshaded shader that boosts brightness while preserving sprite colors
func _create_glow_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform float brightness_boost : hint_range(1.0, 3.0) = 1.4;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Boost RGB while preserving color ratios for bloom
	COLOR = vec4(tex.rgb * brightness_boost, tex.a);
}
"""
	return shader

func _physics_process(delta):
	global_position += velocity * delta
	
	lifetime += delta
	if lifetime > 5.0:
		queue_free()

func _on_body_entered(body):
	# Don't damage owner or player if owner is player/turret
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	
	# Don't damage charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return

	# Only apply damage to targets that can take damage
	if not body.has_method("take_damage"):
		return

	# Prevent repeated hits on the same target
	if _hit_nodes.has(body):
		return

	# Roll for critical hit
	var is_crit := randf() < CRIT_CHANCE
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	# Pass hit direction (bullet's travel direction) to enemy for knockback visual
	var hit_direction = velocity.normalized()
	body.take_damage(damage, is_crit, hit_direction)
	_hit_nodes.append(body)

	# If we are not piercing, or we have a limited pierce_count that reached 0, destroy
	if not pierce_all:
		queue_free()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			queue_free()
