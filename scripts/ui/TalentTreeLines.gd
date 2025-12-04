extends Control

## Simple drawing control for talent tree connection lines

const UNLOCKED_COLOR := Color(0.3, 0.9, 0.4, 1.0)
const LOCKED_COLOR := Color(0.35, 0.35, 0.4, 1.0)

func _draw() -> void:
	var tree_ref = get_meta("tree_ref", null)
	var char_id: int = get_meta("char_id", -1)
	
	if tree_ref == null or char_id < 0:
		return
	
	if not tree_ref.has_method("get_talent_data"):
		return
	
	var talents: Array = tree_ref.get_talent_data(char_id)
	var unlocked: Dictionary = tree_ref.get_unlocked_for_char(char_id)
	
	var node_width: float = 180.0
	var node_height: float = 90.0
	var h_spacing: float = 230.0
	var v_spacing: float = 155.0  # Must match TalentTree.gd
	var grid_width: float = 3.0 * h_spacing
	var start_x: float = (700.0 - grid_width) / 2.0 + h_spacing / 2.0
	
	for talent in talents:
		var requires: Array = talent.get("requires", [])
		if requires.is_empty():
			continue
		
		var to_col: int = talent["col"]
		var to_row: int = talent["row"]
		var to_x: float = start_x + to_col * h_spacing
		var to_y: float = to_row * v_spacing + 5
		
		for req_id in requires:
			for req_talent in talents:
				if req_talent["id"] == req_id:
					var from_col: int = req_talent["col"]
					var from_row: int = req_talent["row"]
					var from_x: float = start_x + from_col * h_spacing
					var from_y: float = from_row * v_spacing + 5
					
					var req_level: int = unlocked.get(req_id, 0)
					var line_color := UNLOCKED_COLOR if req_level > 0 else LOCKED_COLOR
					
					# Draw orthogonal lines
					if from_col == to_col:
						# Straight vertical line (same column)
						# From bottom of source to top of target
						draw_line(Vector2(from_x, from_y + node_height), Vector2(to_x, to_y), line_color, 3.0)
					else:
						# Different column - horizontal branch from source node
						# Line comes out the SIDE of the source node, then goes down to target
						var from_center_y: float = from_y + node_height / 2.0
						
						# Horizontal from side of source node
						if to_col < from_col:
							# Target is to the LEFT
							var from_side_x: float = from_x - node_width / 2.0 - 5
							var to_center_x: float = to_x
							draw_line(Vector2(from_side_x, from_center_y), Vector2(to_center_x, from_center_y), line_color, 3.0)
							# Vertical down to target
							draw_line(Vector2(to_center_x, from_center_y), Vector2(to_center_x, to_y), line_color, 3.0)
						else:
							# Target is to the RIGHT
							var from_side_x: float = from_x + node_width / 2.0 + 5
							var to_center_x: float = to_x
							draw_line(Vector2(from_side_x, from_center_y), Vector2(to_center_x, from_center_y), line_color, 3.0)
							# Vertical down to target
							draw_line(Vector2(to_center_x, from_center_y), Vector2(to_center_x, to_y), line_color, 3.0)
					break
