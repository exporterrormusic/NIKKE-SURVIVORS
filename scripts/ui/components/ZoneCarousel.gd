class_name ZoneCarousel
extends Control
## Infinite-loop center carousel of ZoneThumbs (mission select). The selected
## zone is locked to the window center and enlarged; neighbors dim and shrink.
## Thumbs are laid out on a circle (shortest wrap-around distance from the
## scroll position) so both sides of the rail are always populated.

signal zone_changed(index: int)

const ZoneThumbScript := preload("res://scripts/ui/components/ZoneThumb.gd")

@export var thumb_size := Vector2(240, 114)
@export var gap := 15.0
@export var slide_time := 0.35

var selected_index := 0

var _maps: Array = []
var _thumbs: Array[ZoneThumb] = []
var _scroll := 0.0:
	set(value):
		_scroll = value
		_layout()
var _tween: Tween = null


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout)


func set_maps(maps: Array) -> void:
	_maps = maps
	for thumb in _thumbs:
		thumb.queue_free()
	_thumbs.clear()
	for i in maps.size():
		var map: Dictionary = maps[i]
		var thumb: ZoneThumb = ZoneThumbScript.new()
		thumb.map_name = map.get("name", "")
		thumb.map_subtitle = map.get("subtitle", "")
		var preview_path: String = map.get("preview", "")
		if preview_path != "" and ResourceLoader.exists(preview_path):
			thumb.texture = load(preview_path)
		thumb.size = thumb_size
		thumb.pivot_offset = thumb_size * 0.5
		thumb.pressed.connect(_on_thumb_pressed.bind(i))
		add_child(thumb)
		_thumbs.append(thumb)
	_layout()


func select(index: int, animate: bool = true) -> void:
	if _maps.is_empty():
		return
	index = wrapi(index, 0, _maps.size())
	selected_index = index
	for i in _thumbs.size():
		_thumbs[i].selected = (i == index)
	zone_changed.emit(index)

	if _tween and _tween.is_valid():
		_tween.kill()
	var target := _scroll + _circ_delta(float(index), _scroll)
	if animate:
		_tween = create_tween()
		_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(self, "_scroll", target, slide_time)
		_tween.tween_callback(func(): _scroll = wrapf(_scroll, 0.0, float(_maps.size())))
	else:
		_scroll = wrapf(target, 0.0, float(_maps.size()))


func step(delta: int) -> void:
	select(selected_index + delta)


func select_random(animate: bool = false) -> void:
	if not _maps.is_empty():
		select(randi() % _maps.size(), animate)


func _on_thumb_pressed(index: int) -> void:
	if index != selected_index:
		select(index)


## Shortest wrap-around distance from b to a on the N-zone circle
func _circ_delta(a: float, b: float) -> float:
	var n := float(_maps.size())
	if n <= 0.0:
		return 0.0
	return wrapf(a - b + n * 0.5, 0.0, n) - n * 0.5


func _layout() -> void:
	if _thumbs.is_empty() or size.x <= 0:
		return
	var pitch := thumb_size.x + gap
	var center_y := (size.y - thumb_size.y) * 0.5
	for i in _thumbs.size():
		var thumb := _thumbs[i]
		var d := _circ_delta(float(i), _scroll)
		var center_x := size.x * 0.5 + d * pitch
		thumb.position = Vector2(center_x - thumb_size.x * 0.5, center_y)
		var t := clampf(absf(d), 0.0, 1.0)
		var s := lerpf(1.04, 0.86, t)
		thumb.scale = Vector2(s, s)
		var alpha := lerpf(1.0, 0.5, t)
		# Fade out near the window edges so the wrap-around jump is invisible
		var edge := clampf(minf(center_x, size.x - center_x) / (thumb_size.x * 0.9), 0.0, 1.0)
		thumb.modulate.a = alpha * edge
