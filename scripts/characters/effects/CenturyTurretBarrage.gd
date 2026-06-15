extends Node2D
class_name CenturyTurretBarrage
## Snow White's "A CENTURY OF PREP TIME" burst talent: deploys 20 turrets in a
## grid across the whole map and zooms the camera out for spectacle (the same
## effect as Rapunzel's "6,000? Really?"). Self-frees after the show.

const TURRET_COUNT := 10 # 5x2 grid
const TURRET_AMMO := 4
const MAP_SIZE := 4000.0
const MARGIN := 300.0

var owner_node: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null and owner_node:
		parent_node = owner_node.get_parent()
	if parent_node == null:
		queue_free()
		return

	var camera := get_viewport().get_camera_2d()
	_zoom_out(camera)

	var map_min := -MAP_SIZE / 2.0 + MARGIN
	var map_max := MAP_SIZE / 2.0 - MARGIN
	var cols := 5
	var rows := 2
	var positions: Array[Vector2] = []
	for row in range(rows):
		for col in range(cols):
			var tx := float(col) / float(cols - 1) if cols > 1 else 0.5
			var ty := float(row) / float(rows - 1) if rows > 1 else 0.5
			positions.append(Vector2(lerpf(map_min, map_max, tx), lerpf(map_min, map_max, ty)))

	var tree := get_tree()
	for i in range(positions.size()):
		# Use Snow White's own turret scene so the barrage looks identical to her
		# deployed turrets (and fires her homing, full-visual missiles). Left as a
		# plain turret (no aura/permanent/detonation talents configured).
		var turret = ProjectileCache.create_turret()
		turret.ammo = TURRET_AMMO
		turret.max_ammo = TURRET_AMMO
		turret.spawner_node = owner_node
		turret.fire_delay = float(i) * 0.05 # stagger to avoid a one-frame hitch
		parent_node.add_child(turret)
		turret.global_position = positions[i]
		# Spread instancing across frames (5 per frame)
		if (i + 1) % 5 == 0 and i + 1 < positions.size():
			await tree.process_frame
			if not is_instance_valid(parent_node):
				return

	# Zoom back in once the turrets have had time to fire.
	var zoom_back := get_tree().create_timer(4.0)
	var cam_ref := camera
	zoom_back.timeout.connect(func(): _zoom_in_static(cam_ref))

	# Self-free after the spectacle (turrets are independent nodes that outlive us).
	await get_tree().create_timer(6.5).timeout
	if is_instance_valid(self):
		queue_free()

func _zoom_out(camera: Camera2D) -> void:
	var tree := get_tree()
	if not tree:
		return
	if CombatJuice.instance:
		var t := tree.create_tween()
		t.tween_property(CombatJuice.instance, "_base_zoom", Vector2(0.5, 0.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif camera:
		var t := tree.create_tween()
		t.tween_property(camera, "zoom", Vector2(0.5, 0.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

static func _zoom_in_static(camera: Camera2D) -> void:
	if CombatJuice.instance:
		var tree = CombatJuice.instance.get_tree()
		if tree:
			var t := tree.create_tween()
			t.tween_property(CombatJuice.instance, "_base_zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif camera and is_instance_valid(camera):
		var tree = camera.get_tree()
		if tree:
			var t := tree.create_tween()
			t.tween_property(camera, "zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
