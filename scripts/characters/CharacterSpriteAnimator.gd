extends AnimatedSprite2D
class_name CharacterSpriteAnimator

const DIRECTION_ROWS := {
	"down": 0,
	"left": 1,
	"right": 2,
	"up": 3,
}
const DEFAULT_SCALE := 0.2
const MOVEMENT_THRESHOLD := 8.0

var _has_sprite := false
var _last_direction: String = "down"
var _scale_factor: float = DEFAULT_SCALE
var _fps: float = 8.0

func _ready() -> void:
	visible = false
	centered = true
	z_index = 10

func configure(sprite_sheet: Texture2D, columns: int, rows: int, fps: float, scale_factor: float = DEFAULT_SCALE) -> void:
	_scale_factor = scale_factor
	_fps = fps
	
	if sprite_sheet == null:
		visible = false
		_has_sprite = false
		return
	
	var texture_size: Vector2 = sprite_sheet.get_size()
	var frame_width := int(texture_size.x / columns)
	var frame_height := int(texture_size.y / rows)
	
	var frames := SpriteFrames.new()
	
	# Create animations for each direction (each row is a direction)
	for direction in DIRECTION_ROWS.keys():
		var row: int = DIRECTION_ROWS[direction]
		if row >= rows:
			continue
		
		frames.add_animation(direction)
		frames.set_animation_speed(direction, fps)
		frames.set_animation_loop(direction, true)
		
		# Add frames for this direction (each column is a frame)
		for col in range(columns):
			var atlas := AtlasTexture.new()
			atlas.atlas = sprite_sheet
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			frames.add_frame(direction, atlas)
	
	sprite_frames = frames
	scale = Vector2(scale_factor, scale_factor)
	# Pixel-art sheets (upscaled) need crisp pixels; high-res sheets (downscaled) need smoothing
	texture_filter = TEXTURE_FILTER_NEAREST if scale_factor >= 1.0 else TEXTURE_FILTER_PARENT_NODE
	_has_sprite = true
	visible = true
	
	# Start with down animation
	animation = "down"
	play("down")

func update_state(move_velocity: Vector2, aim_vector: Vector2) -> void:
	if not _has_sprite or not sprite_frames:
		return
	
	# Determine direction from aim or movement
	var direction := _direction_from_vector(aim_vector)
	if direction.is_empty():
		direction = _direction_from_vector(move_velocity)
	if direction.is_empty():
		direction = _last_direction
	
	# Check if moving
	var is_moving := move_velocity.length() > MOVEMENT_THRESHOLD
	
	if sprite_frames.has_animation(direction):
		if is_moving:
			# Play walk animation
			if animation != direction or not is_playing():
				animation = direction
				play(direction)
		else:
			# Show idle frame (first frame of direction)
			if animation != direction:
				animation = direction
			stop()
			frame = 0
		_last_direction = direction

func _direction_from_vector(vec: Vector2) -> String:
	if abs(vec.x) < 0.01 and abs(vec.y) < 0.01:
		return ""
	if abs(vec.x) > abs(vec.y):
		return "right" if vec.x > 0.0 else "left"
	else:
		return "down" if vec.y > 0.0 else "up"

func clear() -> void:
	_has_sprite = false
	stop()
	frame = 0
	visible = false
	sprite_frames = null
	_last_direction = "down"

func reset() -> void:
	# Resets the animator to a clean state for pooling
	# Ensures sprite is visible and playing the default animation
	
	if not _has_sprite or not sprite_frames:
		# If no sprite was ever configured, we can't do much, but we should ensure we aren't hidden
		# unless we really differ from the "visible" default.
		# For safety, if we have frames, show.
		if sprite_frames:
			visible = true
			play("down")
		else:
			visible = false
		return
		
	visible = true
	modulate = Color.WHITE
	self_modulate = Color.WHITE
	
	# Reset animation
	_last_direction = "down"
	animation = "down"
	frame = 0
	play("down")
