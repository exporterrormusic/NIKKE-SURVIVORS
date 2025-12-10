extends Resource
class_name TimeOfDayDefinition

## Encapsulates lighting, fog, and modulation values for a time-of-day preset.
@export var time_id: StringName = &""
@export var display_name: String = "Time"
@export var ambient_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 2.0, 0.01) var ambient_intensity: float = 0.85
@export var sky_tint: Color = Color(0.35, 0.45, 0.65, 1.0)
@export var fog_color: Color = Color(0.75, 0.83, 0.95, 1.0)
@export_range(0.0, 1.0, 0.01) var fog_alpha: float = 0.12
@export var light_color: Color = Color(1.0, 0.97, 0.85, 1.0)
@export_range(0.0, 8.0, 0.01) var light_energy: float = 1.0
@export_range(-180.0, 180.0, 1.0) var light_angle_degrees: float = -45.0
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.0

## Screen-space fog settings (Zelda-style overlay fog)
@export var use_screen_fog: bool = false
@export_range(0.0, 0.5, 0.01) var screen_fog_density: float = 0.15
@export var screen_fog_color: Color = Color(0.7, 0.75, 0.85, 1.0)

## Smart Night Shader settings (replaces CanvasModulate when enabled)
@export var use_smart_night_shader: bool = false
@export_range(0.0, 1.0, 0.01) var night_shader_intensity: float = 0.7
@export_range(0.0, 1.0, 0.01) var night_desaturation: float = 0.55
@export_range(0.3, 1.0, 0.01) var night_darkness: float = 0.65

func get_canvas_modulate() -> Color:
	return Color(
		ambient_tint.r * ambient_intensity,
		ambient_tint.g * ambient_intensity,
		ambient_tint.b * ambient_intensity,
		1.0
	)
