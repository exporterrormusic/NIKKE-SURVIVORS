extends Node
## DEV one-off: bakes the current procedural rocket (BODY + EXHAUST flame) into a PNG,
## then quits. Run with: project_run(mode="custom", scene="res://scenes/tools/RocketBaker.tscn").
## Body is centered in the texture (so a centered Sprite2D pivots on the body center);
## the exhaust extends toward -X behind it.

const OUT_PATH := "res://assets/projectiles/rocket.png"
const TEX_W := 176
const TEX_H := 64

class RocketPainter extends Node2D:
	const EP = preload("res://scripts/projectiles/ExplosiveProjectile.gd")
	func _draw() -> void:
		# Non-special turret-missile look, facing +X, body centered at origin.
		EP.paint_rocket_exhaust(self, Vector2.RIGHT, Vector2.UP, 74.0, 20.0, false, 42.0, 1.0, 1.0)
		EP.paint_rocket_body(self, Vector2.RIGHT, Vector2.UP, 74.0, 20.0, false)

func _ready() -> void:
	_bake()

func _bake() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX_W, TEX_H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var painter := RocketPainter.new()
	painter.position = Vector2(TEX_W * 0.5, TEX_H * 0.5)
	vp.add_child(painter)
	add_child(vp)
	painter.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	print("[RocketBaker] save_png err=", err, " -> ", ProjectSettings.globalize_path(OUT_PATH))
	await get_tree().process_frame
	get_tree().quit()
