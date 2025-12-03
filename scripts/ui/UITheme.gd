extends Node
class_name UITheme
## Global UI Theme singleton providing consistent styling across all menus.
## Combines NIKKE's sleek sci-fi aesthetic with Holocure's chunky, fun feel.

# =============================================================================
# COLOR PALETTE - NIKKE-inspired with vibrant accents
# =============================================================================

# Backgrounds (dark, subdued - lets content pop)
const BG_DEEP := Color(0.04, 0.055, 0.08, 1.0)          # #0A0E14 - Deepest layer
const BG_MID := Color(0.082, 0.11, 0.157, 1.0)          # #151C28 - Panels, cards
const BG_LIGHT := Color(0.118, 0.157, 0.212, 1.0)       # #1E2836 - Hover states
const BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.5)           # Dark overlay for modals

# Primary Accent - Clean white (main accent)
const ACCENT_PRIMARY := Color(0.95, 0.95, 0.98, 1.0)      # Near-white - Selected, important
const ACCENT_PRIMARY_DIM := Color(0.75, 0.75, 0.8, 1.0)   # Dimmed version
const ACCENT_PRIMARY_GLOW := Color(0.9, 0.9, 0.95, 0.3)   # For glow effects
const ACCENT_HOVER := Color(1.0, 1.0, 1.0, 1.0)           # Bright white for hovers

# Secondary Accent - Warm amber/gold (highlights)
const ACCENT_SECONDARY := Color(1.0, 0.714, 0.15, 1.0)  # #FFB627 - Gold highlights
const ACCENT_SECONDARY_DIM := Color(0.85, 0.6, 0.1, 1.0)

# Tertiary Accent - Soft pink/coral (special elements)
const ACCENT_TERTIARY := Color(1.0, 0.42, 0.615, 1.0)   # #FF6B9D - Pink accents

# Semantic Colors
const COLOR_SUCCESS := Color(0.29, 0.87, 0.5, 1.0)      # #4ADE80 - HP, confirms
const COLOR_DANGER := Color(1.0, 0.34, 0.34, 1.0)       # #FF5757 - Damage, cancel
const COLOR_WARNING := Color(1.0, 0.6, 0.2, 1.0)        # Orange warning

# Text Colors
const TEXT_PRIMARY := Color(0.94, 0.96, 0.97, 1.0)      # #F0F4F8 - Main text
const TEXT_SECONDARY := Color(0.533, 0.573, 0.627, 1.0) # #8892A0 - Descriptions
const TEXT_DISABLED := Color(0.4, 0.42, 0.45, 1.0)      # Disabled text
const TEXT_DARK := Color(0.1, 0.1, 0.12, 1.0)           # Text on light backgrounds

# Border Colors
const BORDER_DEFAULT := Color(0.3, 0.35, 0.45, 0.8)     # Default border
const BORDER_HIGHLIGHT := Color(0.5, 0.55, 0.65, 1.0)   # Highlighted border
const BORDER_GLOW := Color(0.0, 0.83, 1.0, 0.6)         # Glowing border

# =============================================================================
# SIZING - Holocure-inspired chunky feel
# =============================================================================

# Border widths (thicker for that chunky feel)
const BORDER_THIN := 2
const BORDER_NORMAL := 3
const BORDER_THICK := 4
const BORDER_CHUNKY := 5

# Corner radii
const CORNER_NONE := 0
const CORNER_SMALL := 4
const CORNER_MEDIUM := 8
const CORNER_LARGE := 12

# Shadows (visible depth like Holocure)
const SHADOW_OFFSET := Vector2(3, 3)
const SHADOW_SIZE := 4
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.4)

# Hover scale (bouncy like Holocure)
const HOVER_SCALE := 1.05
const HOVER_DURATION := 0.15

# =============================================================================
# STYLE FACTORY METHODS
# =============================================================================

static func create_panel_style(
	bg_color: Color = BG_MID,
	border_color: Color = BORDER_DEFAULT,
	border_width: int = BORDER_NORMAL,
	corner_radius: int = CORNER_MEDIUM,
	with_shadow: bool = true
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	
	if with_shadow:
		style.shadow_color = SHADOW_COLOR
		style.shadow_size = SHADOW_SIZE
		style.shadow_offset = SHADOW_OFFSET
	
	# Add anti-aliasing for smoother edges
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	
	return style


static func create_button_style_normal() -> StyleBoxFlat:
	var style := create_panel_style(
		BG_MID,
		BORDER_DEFAULT,
		BORDER_NORMAL,
		CORNER_MEDIUM,
		true
	)
	return style


static func create_button_style_hover() -> StyleBoxFlat:
	var style := create_panel_style(
		BG_LIGHT,
		ACCENT_PRIMARY,
		BORDER_THICK,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = ACCENT_PRIMARY_GLOW
	style.shadow_size = 6
	return style


static func create_button_style_pressed() -> StyleBoxFlat:
	var style := create_panel_style(
		Color(0.06, 0.08, 0.11, 1.0),
		ACCENT_PRIMARY,
		BORDER_THICK,
		CORNER_MEDIUM,
		false
	)
	return style


static func create_button_style_selected() -> StyleBoxFlat:
	var style := create_panel_style(
		Color(0.0, 0.2, 0.28, 1.0),
		ACCENT_PRIMARY,
		BORDER_CHUNKY,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = ACCENT_PRIMARY_GLOW
	style.shadow_size = 8
	return style


static func create_primary_button_style_normal() -> StyleBoxFlat:
	# Bright inverted style for primary actions (like PLAY)
	var style := create_panel_style(
		ACCENT_PRIMARY,
		Color(1.0, 1.0, 1.0, 1.0),
		BORDER_THICK,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = ACCENT_PRIMARY_GLOW
	style.shadow_size = 6
	return style


static func create_primary_button_style_hover() -> StyleBoxFlat:
	var style := create_panel_style(
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		BORDER_CHUNKY,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = Color(1.0, 1.0, 1.0, 0.4)
	style.shadow_size = 10
	return style


static func create_danger_button_style() -> StyleBoxFlat:
	var style := create_panel_style(
		Color(0.25, 0.08, 0.08, 1.0),
		COLOR_DANGER,
		BORDER_NORMAL,
		CORNER_MEDIUM,
		true
	)
	return style


static func create_tab_style_active() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT_PRIMARY
	style.border_color = Color(0.5, 0.9, 1.0, 1.0)
	style.set_border_width_all(0)
	style.border_width_bottom = BORDER_THICK
	style.set_corner_radius_all(0)
	style.corner_radius_top_left = CORNER_SMALL
	style.corner_radius_top_right = CORNER_SMALL
	return style


static func create_tab_style_inactive() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_MID
	style.border_color = BORDER_DEFAULT
	style.set_border_width_all(0)
	style.border_width_bottom = BORDER_THIN
	style.set_corner_radius_all(0)
	style.corner_radius_top_left = CORNER_SMALL
	style.corner_radius_top_right = CORNER_SMALL
	return style


static func create_card_style() -> StyleBoxFlat:
	var style := create_panel_style(
		BG_MID,
		BORDER_DEFAULT,
		BORDER_NORMAL,
		CORNER_MEDIUM,
		true
	)
	return style


static func create_card_style_hover() -> StyleBoxFlat:
	var style := create_panel_style(
		BG_LIGHT,
		ACCENT_PRIMARY,
		BORDER_THICK,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = ACCENT_PRIMARY_GLOW
	style.shadow_size = 8
	return style


static func create_card_style_selected() -> StyleBoxFlat:
	var style := create_panel_style(
		Color(0.0, 0.15, 0.22, 1.0),
		ACCENT_PRIMARY,
		BORDER_CHUNKY,
		CORNER_MEDIUM,
		true
	)
	style.shadow_color = ACCENT_PRIMARY_GLOW
	style.shadow_size = 10
	return style


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

static func apply_hover_effect(control: Control, tween: Tween = null) -> Tween:
	if tween:
		tween.kill()
	tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)  # Bouncy like Holocure
	tween.tween_property(control, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	return tween


static func remove_hover_effect(control: Control, tween: Tween = null) -> Tween:
	if tween:
		tween.kill()
	tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", Vector2.ONE, HOVER_DURATION)
	return tween


static func apply_press_effect(control: Control) -> Tween:
	var tween := control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property(control, "scale", Vector2.ONE, 0.1)
	return tween


# =============================================================================
# GRADIENT HELPERS
# =============================================================================

static func create_vertical_gradient(top_color: Color, bottom_color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, top_color)
	gradient.set_color(1, bottom_color)
	
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 1
	texture.height = 64
	
	return texture


# =============================================================================
# PROGRESS BAR STYLES
# =============================================================================

static func create_progress_bar_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	style.border_color = BORDER_DEFAULT
	style.set_border_width_all(BORDER_THIN)
	style.set_corner_radius_all(CORNER_SMALL)
	return style


static func create_progress_bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.2)
	style.set_border_width_all(0)
	style.set_corner_radius_all(CORNER_SMALL - 1)
	return style


# =============================================================================
# SEPARATOR STYLES
# =============================================================================

static func get_separator_color() -> Color:
	return Color(0.3, 0.35, 0.45, 0.5)


static func get_separator_highlight_color() -> Color:
	return ACCENT_PRIMARY.darkened(0.3)

