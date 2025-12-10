extends CanvasLayer
class_name DebugLog

var label: RichTextLabel

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128 # Topmost
	
	label = RichTextLabel.new()
	label.size = Vector2(800, 600)
	label.position = Vector2(20, 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	
	print_log("DebugLog initialized")

func print_log(msg: String):
	print(msg) # Mirror to console for export debugging
	if label:
		label.add_text(msg + "\n")
		# Keep last 20 lines
		var lines = label.get_parsed_text().split("\n")
		if lines.size() > 20:
			label.text = ""
			for i in range(lines.size() - 20, lines.size()):
				label.add_text(lines[i] + "\n")

static func log(msg: String):
	# ALWAYS print to console first, so we capture it in user logs
	print(msg)
	
	# Static helper to find instance and print to on-screen label
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		# Try root first (if added as autoload directly)
		if tree.root.has_node("DebugLog"):
			tree.root.get_node("DebugLog").print_log(msg)
		# Try MenuManager children (current injection point)
		elif tree.root.has_node("MenuManager"):
			var menu = tree.root.get_node("MenuManager")
			if menu.has_node("DebugLog"):
				menu.get_node("DebugLog").print_log(msg)
