extends Node
class_name ShadowHelper
## Utility class for creating consistent shadow sprites across all entities.
## Eliminates duplicated shadow creation code in PlayerCore.gd, etc.

## Creates a shadow sprite and adds it as a child of the given entity.
## Returns the created shadow sprite for further customization if needed.
static func create_shadow(entity: Node2D, width: int = 48, height: int = 24, y_offset: float = 0.0) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = TextureCache.get_shadow_ellipse(width, height)
	shadow.z_index = -1
	shadow.position.y = y_offset
	shadow.modulate = Color(0, 0, 0, 0.35)
	entity.add_child(shadow)
	return shadow


## Creates a shadow with entity-specific defaults for players
static func create_player_shadow(player: Node2D) -> Sprite2D:
	return create_shadow(player, 40, 16, 40.0)


## Creates a shadow with entity-specific defaults for enemies
static func create_enemy_shadow(enemy: Node2D) -> Sprite2D:
	return create_shadow(enemy, 48, 24)


## Creates a shadow with entity-specific defaults for summons/allies
static func create_summon_shadow(summon: Node2D) -> Sprite2D:
	return create_shadow(summon, 40, 16, 35.0)
