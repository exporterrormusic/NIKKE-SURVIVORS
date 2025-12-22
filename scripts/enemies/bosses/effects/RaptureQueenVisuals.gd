extends Node2D

## Main visual controller for RAPTURE QUEEN - N01
## Draws the procedural face and manages sub-components (Hair, Arms, Body)

# References
var _parent: Node2D
var _velocity: Vector2 = Vector2.ZERO

# Face settings
# Face settings
var face_texture: Texture2D
const FACE_COLOR := Color(0.95, 0.95, 0.98) # Pale white/porcelain (Fallback)
const FACE_SIZE := Vector2(50, 70)
const EYE_COLOR := Color(1.0, 0.1, 0.1, 0.0) # Transparent core (using sprite)
const EYE_GLOW_COLOR := Color(1.0, 0.0, 0.0, 0.4)
const MOUTH_COLOR := Color(0.1, 0.0, 0.0, 0.0) # Transparent (using sprite)

# Dynamic state
var _eye_pulse_time: float = 0.0
var _mouth_open_amount: float = 0.0 # 0.0 = closed, 1.0 = fully open (beam)
var _is_teleporting: bool = false
var _teleport_amount: float = 0.0
var _dissolve_amount: float = 0.0
var _dissolve_material: ShaderMaterial = null
var _original_material: Material = null

# Sub-components
const HairScript = preload("res://scripts/enemies/bosses/effects/RaptureQueenHair.gd")
const ArmScript = preload("res://scripts/enemies/bosses/effects/RaptureQueenArm.gd")
const BossFaceTexture = preload("res://assets/enemies/bosses/n01.png")
const UniversalSpriteShader = preload("res://resources/shaders/universal_sprite_shader.gdshader")
const RaptureQueenLiquidShader = preload("res://resources/shaders/bosses/rapture_queen_liquid.gdshader")
const RaptureQueenTeleportShader = preload("res://resources/shaders/bosses/rapture_queen_teleport_dissolve.gdshader")
var _hair: Node2D
var _face_sprite: Sprite2D

func _ready() -> void:
	z_index = 0 # Ensure base layer is 0 so children sort correctly relative to it
	_parent = get_parent()
	
	# Use preloaded texture (guaranteed to be in export)
	face_texture = BossFaceTexture
	
	# 2. Add Face Sprite (Base Layer, Shader)
	_face_sprite = Sprite2D.new()
	_face_sprite.name = "Sprite2D"
	var sprite_offset = Vector2(0, 5) # Move down slightly
	
	if face_texture:
		_face_sprite.texture = face_texture
		# Scale sprite
		var tex_size = face_texture.get_size()
		# Target width ~180px
		var scale_fac = 180.0 / tex_size.x
		_face_sprite.scale = Vector2(scale_fac, scale_fac)
		
		# Apply Universal Shader for Outline
		var shader = UniversalSpriteShader
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			
			# Configure RED Outline
			mat.set_shader_parameter("enable_outline", true)
			mat.set_shader_parameter("outline_color", Color(1.0, 0.0, 0.0, 1.0))
			mat.set_shader_parameter("outline_width", 3.0) # Thicker outline
			mat.set_shader_parameter("glow_scale", 4.0) # Scale glow with size
			
			# Ensure it's bright/unshaded style
			mat.set_shader_parameter("night_boost", 0.5) 
			mat.set_shader_parameter("night_glow_color", Color(1.0, 0.0, 0.0, 1.0))
			
			_face_sprite.material = mat
		
	else:
		pass  # Fallback to procedural drawing if texture not found
			
	# Main Face on TOP of Outline
	_face_sprite.z_index = 1
	_face_sprite.position = sprite_offset
	add_child(_face_sprite)
	
	# 4. Add Procedural Hair (Behind Face, VERY LOW Z-INDEX to not cover bullets)
	_hair = Node2D.new()
	_hair.set_script(HairScript)
	_hair.z_index = -10 # Behind everything except background (Z-Axis Fix kept)
	add_child(_hair)
	
	# 4. Add Procedural Arms (Behind Hair)
	for i in range(8):
		var arm = Node2D.new()
		arm.set_script(ArmScript)
		arm.z_index = -12 # Behind hair (Z-Axis Fix kept)
		add_child(arm)
		
		# Distribute angles: 4 left, 4 right
		var is_right = i % 2 == 0
		var idx_side = i / 2
		var angle_base = deg_to_rad(30.0 + idx_side * 30.0)
		var angle = angle_base if is_right else PI - angle_base
		
		if arm.has_method("setup"):
			arm.setup(angle)
			
	# 5. Setup dissolve shader for teleport effect
	_setup_dissolve_shader()
	
	# 6. Load and setup "Liquid" shader
	_setup_liquid_shader()

func _setup_liquid_shader() -> void:
	# Use preloaded shader constant
	var shader = RaptureQueenLiquidShader
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		
		var noise = FastNoiseLite.new()
		noise.frequency = 0.02
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		
		var noise_tex = NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.seamless = true
		noise_tex.width = 256
		noise_tex.height = 256
		
		mat.set_shader_parameter("noise_tex", noise_tex)
		mat.set_shader_parameter("distortion_strength", 0.05)
		mat.set_shader_parameter("speed", 0.2)
		
		# Assign to self (CanvasGroup) - DISABLED for debugging
		# self.material = mat

func _setup_dissolve_shader() -> void:
	# Create dissolve shader material for teleport effect (preloaded)
	var shader = RaptureQueenTeleportShader
	if shader and _face_sprite:
		_dissolve_material = ShaderMaterial.new()
		_dissolve_material.shader = shader
		
		# Set default parameters
		_dissolve_material.set_shader_parameter("dissolve_amount", 0.0)
		_dissolve_material.set_shader_parameter("flow_speed", 1.5)
		_dissolve_material.set_shader_parameter("edge_glow_color", Color(0.5, 0.0, 0.5, 1.0))  # Purple glow
		_dissolve_material.set_shader_parameter("edge_glow_intensity", 1.5)
		_dissolve_material.set_shader_parameter("edge_thickness", 0.08)
		
		# Store original material
		_original_material = _face_sprite.material

func _process(delta: float) -> void:
	if _parent:
		if "velocity" in _parent:
			_velocity = _parent.velocity
		position = Vector2.ZERO # Always center on parent
	
	_eye_pulse_time += delta * 2.0
	
	# Update Hitboxes
	# DISABLED due to Convex Decomposition errors
	# _update_dynamic_hitboxes()

	queue_redraw()

func set_mouth_open(amount: float) -> void:
	_mouth_open_amount = clamp(amount, 0.0, 1.0)

func set_teleporting(active: bool, amount: float = 0.0) -> void:
	_is_teleporting = active
	_teleport_amount = amount
	
	# Fade main sprite color (Shader modulate)
	if _face_sprite:
		_face_sprite.modulate.a = 1.0 - amount
	
	# Note: Universal shader doesn't automatically fade outline with modulate alpha
	# unless configured to multiply. But usually Modulate Alpha affects everything.
	# We rely on CanvasItem alpha fading.
	
	# Reset self modulate (if used)
	# modulate.a = 1.0 - amount

func set_dissolve_amount(amount: float) -> void:
	_dissolve_amount = clamp(amount, 0.0, 1.0)
	
	# Apply dissolve shader to face sprite
	if _face_sprite and _dissolve_material:
		if _dissolve_amount > 0.0:
			if _face_sprite.material != _dissolve_material:
				_face_sprite.material = _dissolve_material
			_dissolve_material.set_shader_parameter("dissolve_amount", _dissolve_amount)
		else:
			# Restore original material when not dissolving
			if _face_sprite.material != _original_material:
				_face_sprite.material = _original_material
	
	# Apply dissolve to ALL components (hair, arms, body)
	for child in get_children():
		# Fade out hair
		if child.get_script() == HairScript:
			child.modulate.a = 1.0 - _dissolve_amount
		# Fade out arms
		elif child.get_script() == ArmScript:
			child.modulate.a = 1.0 - _dissolve_amount
	
	# Fade body drawn in _draw()
	queue_redraw()

func set_regenerating(active: bool) -> void:
	# Change circle color in _draw?
	# We need a state var for regen color
	pass # simplified for now, or add var later. 
	# User just wants red glow.

func _draw() -> void:
	if _is_teleporting and randf() < _teleport_amount:
		return # Flicker out during teleport
	
	# 0. Draw Body (Neck/Shoulders) - fade with dissolve
	var body_color = Color(0.5, 0.0, 0.0, 1.0 - _dissolve_amount) 
	draw_circle(Vector2(0, 10), 45.0, body_color)
	
	# Rest handled by child nodes (Sprite, Glows, Hair, Arms, RedGlowSprite)
	
# Helper to generate ellipse points
func _get_ellipse_points(center: Vector2, size: Vector2, resolution: int = 32) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(resolution):
		var angle = (i / float(resolution)) * TAU
		var x = cos(angle) * size.x
		var y = sin(angle) * size.y
		points.append(center + Vector2(x, y))
	return points

# Dynamic Hitboxes
var _hair_hitbox: CollisionPolygon2D
var _arm_hitboxes: Array = [] # [{node, poly}]
var _hitboxes_initialized: bool = false

func _init_hitboxes() -> void:
	if _hitboxes_initialized or not _parent: return
	
	var hitbox_comp = _parent.get_node_or_null("HitboxComponent")
	if hitbox_comp:
		# Create polygons for arms
		for child in get_children():
			if child.get_script() == ArmScript:
				var arm_poly = CollisionPolygon2D.new()
				arm_poly.name = "ArmHitbox"
				# ArmHitbox needs to be child of HitboxComponent to register hits
				hitbox_comp.add_child(arm_poly)
				_arm_hitboxes.append({ "node": child, "poly": arm_poly })
		_hitboxes_initialized = true

func _update_dynamic_hitboxes() -> void:
	if not _hitboxes_initialized:
		_init_hitboxes()
		
	# Update Arms
	for data in _arm_hitboxes:
		var arm_node = data.node
		var poly = data.poly
		
		if arm_node.has_method("get_current_points"):
			var points = arm_node.get_current_points()
			if points.size() > 2:
				# Expand line to polygon (simple width extrusion)
				var poly_points = PackedVector2Array()
				var width = 20.0
				
				# Forward pass
				for p in points:
					# Points are local to Arm Node. 
					# Arm Node is child of Visuals (0,0 relative to Parent).
					# HitboxComponent is child of Parent (0,0 relative to Parent).
					# BUT Arm Node is rotated!
					# We need to transform points to Parent space.
					var p_rotated = p.rotated(arm_node.rotation)
					poly_points.append(p_rotated + Vector2(width/2, 0).rotated(arm_node.rotation))
					
				# Backward pass
				for i in range(points.size() - 1, -1, -1):
					var p_rotated = points[i].rotated(arm_node.rotation)
					poly_points.append(p_rotated - Vector2(width/2, 0).rotated(arm_node.rotation))
					
				poly.polygon = poly_points
