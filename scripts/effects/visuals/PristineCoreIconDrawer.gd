# Extracted from scripts/world/PristineCoreOrb.gd (was runtime-compiled embedded source).
extends Node2D

func _draw() -> void:
	# Matches the UI Look (CoreCounter)
	# Scaled down 50% (Radius 24 -> 12)
	
	var radius: float = 12.0
	
	# Main sphere gradient (Red -> Dark Red)
	var segments: int = 24
	for i in range(segments, 0, -1):
		var t: float = float(i) / float(segments)
		var r: float = radius * t
		var color := Color(0.6 + 0.4 * (1.0 - t), 0.1 + 0.2 * (1.0 - t), 0.1 + 0.1 * (1.0 - t))
		draw_circle(Vector2.ZERO, r, color)
	
	# Inner glowing core
	var core_radius: float = radius * 0.5
	for i in range(12, 0, -1):
		var t: float = float(i) / 12.0
		var r: float = core_radius * t
		var alpha: float = 0.8 * (1.0 - t * 0.5)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.5, 0.3, alpha))
	
	# Hot center
	draw_circle(Vector2.ZERO, radius * 0.15, Color(1.0, 0.9, 0.7, 1.0))
	
	# Specular highlight
	var highlight_offset: Vector2 = Vector2(-radius * 0.25, -radius * 0.25)
	var highlight_radius: float = radius * 0.2
	draw_circle(highlight_offset, highlight_radius, Color(1.0, 1.0, 1.0, 0.6))
