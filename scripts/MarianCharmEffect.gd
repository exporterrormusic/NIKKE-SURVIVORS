extends Node2D
class_name MarianCharmEffect

## Visual effect for Marian's charm - applies red-to-blue shader to enemy

var _shader_material: ShaderMaterial = null
var _original_materials: Dictionary = {}  # Store original materials to restore later

func _ready() -> void:
	# Load the red-to-blue shader
	var shader = load("res://resources/shaders/marian_charm.gdshader")
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
		_shader_material.set_shader_parameter("intensity", 1.0)
		_shader_material.set_shader_parameter("pulse_speed", 2.0)
		_shader_material.set_shader_parameter("glow_strength", 0.3)
	
	# Apply shader to parent's sprite
	call_deferred("_apply_shader_to_parent")

func _apply_shader_to_parent() -> void:
	var parent := get_parent()
	if not parent:
		return
	
	# Find all Sprite2D children and apply shader
	_apply_to_sprites(parent)

func _apply_to_sprites(node: Node) -> void:
	if node is Sprite2D or node is AnimatedSprite2D:
		var sprite := node as CanvasItem
		# Store original material
		_original_materials[sprite] = sprite.material
		# Apply our shader
		sprite.material = _shader_material
	
	# Recurse to children
	for child in node.get_children():
		_apply_to_sprites(child)

func _exit_tree() -> void:
	# Restore original materials when effect is removed
	for sprite in _original_materials:
		if is_instance_valid(sprite):
			sprite.material = _original_materials[sprite]
	_original_materials.clear()
