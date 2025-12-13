extends Node
## UI theme constants and colors.
## Now an autoload singleton - access globally as UITheme.ACCENT_PRIMARYoviding consistent styling across all menus.
## Combines NIKKE's sleek sci-fi aesthetic with Holocure's chunky, fun feel.

# =============================================================================
# FONTS - Lazily loaded to avoid blocking startup
# =============================================================================
static var _font_title: Font = null
static var _font_bold: Font = null
static var _font_medium: Font = null

static var FONT_TITLE: Font:
	get:
		if _font_title == null:
			_font_title = load("res://resources/fonts/futura_condensed_extra_bold.tres")
		return _font_title

static var FONT_BOLD: Font:
	get:
		if _font_bold == null:
			_font_bold = load("res://resources/fonts/pretendard_bold.tres")
		return _font_bold

static var FONT_MEDIUM: Font:
	get:
		if _font_medium == null:
			_font_medium = load("res://resources/fonts/pretendard_medium.tres")
		return _font_medium

# =============================================================================
# COLOR PALETTE - NIKKE-inspired with vibrant accents
# =============================================================================

# Backgrounds (dark, subdued - lets content pop)
const BG_DEEP := Color(0.04, 0.055, 0.08, 1.0)          # #0A0E14 - Deepest layer
const BG_MID := Color(0.082, 0.11, 0.157, 1.0)          # #151C28 - Panels, cards
const BG_LIGHT := Color(0.118, 0.157, 0.212, 1.0)       # #1E2836 - Hover states
const BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.5)           # Dark overlay for modals

# Entry/Card backgrounds (for list items, cards)
const ENTRY_BG := Color(0.1, 0.1, 0.14, 0.95)           # List item background
const ENTRY_BORDER := Color(0.95, 0.95, 0.98, 0.9)      # List item border
const ENTRY_SEPARATOR := Color(0.95, 0.95, 0.98, 0.3)   # Separator lines

# Primary Accent - Clean white (main accent)
const ACCENT_PRIMARY := Color(0.95, 0.95, 0.98, 1.0)      # Near-white - Selected, important
const ACCENT_PRIMARY_DIM := Color(0.75, 0.75, 0.8, 1.0)   # Dimmed version
const ACCENT_PRIMARY_GLOW := Color(0.9, 0.9, 0.95, 0.3)   # For glow effects
const ACCENT_HOVER := Color(1.0, 1.0, 1.0, 1.0)           # Bright white for hovers

# Secondary Accent - Warm amber/gold (highlights)
const ACCENT_SECONDARY := Color(1.0, 0.714, 0.15, 1.0)  # #FFB627 - Gold highlights
const ACCENT_SECONDARY_DIM := Color(0.85, 0.6, 0.1, 1.0)
const RANK_GOLD := Color(0.996, 0.843, 0.392, 1.0)      # Leaderboard rank gold

# Tertiary Accent - Soft pink/coral (special elements)
const ACCENT_TERTIARY := Color(1.0, 0.42, 0.615, 1.0)   # #FF6B9D - Pink accents

# Semantic Colors
const COLOR_SUCCESS := Color(0.29, 0.87, 0.5, 1.0)      # #4ADE80 - HP, confirms
const COLOR_DANGER := Color(1.0, 0.34, 0.34, 1.0)       # #FF5757 - Damage, cancel
const COLOR_WARNING := Color(1.0, 0.6, 0.2, 1.0)        # Orange warning
const COLOR_UNLOCKED := Color(0.392, 0.86, 0.549, 1.0)  # Green for unlocked items
const COLOR_LOCKED := Color(0.4, 0.4, 0.45, 1.0)        # Gray for locked items
const COLOR_CORE := Color(1.0, 0.3, 0.3, 1.0)           # Red for Pristine Rapture Cores

# Text Colors
const TEXT_PRIMARY := Color(0.94, 0.96, 0.97, 1.0)      # #F0F4F8 - Main text
const TEXT_SECONDARY := Color(0.784, 0.792, 0.878, 1.0) # #C8CAE0 - Descriptions, labels
const TEXT_MUTED := Color(0.592, 0.6, 0.694, 1.0)       # Muted/inactive text
const TEXT_DISABLED := Color(0.4, 0.42, 0.45, 1.0)      # Disabled text
const TEXT_DARK := Color(0.1, 0.1, 0.12, 1.0)           # Text on light backgrounds

# Character selection states
const CHAR_NORMAL := Color(0.08, 0.08, 0.12, 0.95)      # Normal character card
const CHAR_HOVER := Color(0.12, 0.12, 0.18, 0.98)       # Hovered character card
const CHAR_SELECTED := Color(0.18, 0.18, 0.25, 1.0)     # Selected character card
const CHAR_LOCKED := Color(0.05, 0.05, 0.07, 0.95)      # Locked character card
const CHAR_PORTRAIT_UNLOCKED := Color(1, 1, 1, 0.95)    # Portrait modulate when unlocked
const CHAR_IN_SQUAD := Color(0.6, 0.6, 0.6, 0.85)       # Dimmed when already in squad
const CHAR_CARD_NORMAL_BG := Color(0.12, 0.12, 0.16, 0.95)
const CHAR_CARD_HOVER_BG := Color(0.18, 0.18, 0.24, 0.98)
const CHAR_CARD_SELECTED_BG := Color(0.26, 0.26, 0.34, 1.0)
const CHAR_CARD_BORDER_NORMAL := Color(0.4, 0.4, 0.5, 0.8)
const CHAR_CARD_BORDER_SELECTED := Color(0.7, 0.8, 1.0, 1.0)
const CHAR_CARD_LOCKED_TINT := Color(0.4, 0.4, 0.4, 1.0)

# Border Colors
const BORDER_DEFAULT := Color(0.3, 0.35, 0.45, 0.8)     # Default border
const BORDER_HIGHLIGHT := Color(0.5, 0.55, 0.65, 1.0)   # Highlighted border
const BORDER_GLOW := Color(0.0, 0.83, 1.0, 0.6)         # Glowing border

# Talent tree colors
const TALENT_HOVER_BORDER := Color(1.0, 0.85, 0.2, 1.0) # Gold hover border
const TALENT_LOCKED := Color(0.35, 0.35, 0.4, 1.0)      # Locked talent
const TALENT_UNLOCKED := Color(0.3, 0.9, 0.4, 1.0)      # Unlocked talent

# Progress bar colors
const PROGRESS_BG := Color(0.15, 0.15, 0.2, 1.0)        # Progress bar background
const PROGRESS_FILL := Color(0.533, 0.611, 0.98, 1.0)   # Progress bar fill

# XP Bar colors
const XP_BAR_FILL := Color(0.2, 0.6, 1.0, 1.0)          # Bright blue XP fill
const XP_BAR_BG := Color(0.12, 0.12, 0.15, 0.95)        # Dark XP bar background
const XP_BAR_BORDER := Color(1.0, 1.0, 1.0, 0.9)        # White XP bar border

# Stat colors (for character info panels)
const STAT_HP := Color(0.4, 0.9, 0.5, 1.0)              # Green for HP
const STAT_ATK := Color(1.0, 0.5, 0.4, 1.0)             # Red for Attack
const STAT_SPD := Color(0.5, 0.7, 1.0, 1.0)             # Blue for Speed
const STAT_CRIT := Color(1.0, 0.85, 0.3, 1.0)           # Gold for Crit

# Ability colors
const COLOR_SPECIAL := Color(1.0, 0.7, 0.2, 1.0)        # Orange for Special abilities
const COLOR_BURST := Color(0.6, 0.4, 1.0, 1.0)          # Purple for Burst abilities

# =============================================================================
# DIFFICULTY SCALING COLORS
# =============================================================================
const DIFF_NORMAL := Color(0.7, 0.75, 0.85, 1.0)        # Grey/white for difficulty 1
const DIFF_EASY := Color(0.4, 0.9, 0.5, 1.0)            # Green for low difficulty
const DIFF_MEDIUM := Color(1.0, 0.85, 0.3, 1.0)         # Yellow for medium
const DIFF_HARD := Color(1.0, 0.5, 0.2, 1.0)            # Orange for hard
const DIFF_EXTREME := Color(1.0, 0.2, 0.2, 1.0)         # Red for extreme

# =============================================================================
# MODIFIER/STAGE COLORS
# =============================================================================
const MOD_STANDARD := Color(0.3, 0.7, 0.4, 1.0)         # Green for standard mode
const MOD_ELITE := Color(0.9, 0.6, 0.2, 1.0)            # Gold for elite hunt
const MOD_ENDLESS := Color(0.6, 0.4, 0.9, 1.0)          # Purple for endless
const MOD_GODDESS := Color(1.0, 0.3, 0.3, 1.0)          # Red for Goddess Fall

# =============================================================================
# PANEL BACKGROUNDS (for specific UI sections)
# =============================================================================
const PANEL_HEADER_BG := Color(0.06, 0.05, 0.1, 0.95)   # Header panels
const PANEL_HEADER_BORDER := Color(0.5, 0.4, 0.7, 0.9)  # Header border (purple tint)
const PANEL_PREVIEW_BG := Color(0.05, 0.06, 0.09, 0.95) # Preview panel
const PANEL_PREVIEW_BORDER := Color(0.4, 0.45, 0.55, 0.8)
const PANEL_DIFF_BG := Color(0.08, 0.08, 0.12, 0.95)    # Difficulty panel
const PANEL_DIFF_BORDER := Color(0.4, 0.45, 0.55, 0.8)
const PANEL_SCALE_BG := Color(0.06, 0.07, 0.1, 0.95)    # Scaling info panel
const PANEL_SCALE_BORDER := Color(0.3, 0.35, 0.45, 0.8)

# Banner colors
const BANNER_BG := Color(0.0, 0.0, 0.0, 0.75)           # Stage name banner
const BANNER_BORDER := Color(0.8, 0.6, 0.2, 0.9)        # Gold banner border
const BANNER_TEXT := Color(1.0, 0.95, 0.8, 1.0)         # Banner text (warm white)
const BANNER_SUBTITLE := Color(0.9, 0.85, 0.7, 1.0)     # Banner subtitle

# =============================================================================
# BUTTON STATES
# =============================================================================
# Standard button
const BTN_NORMAL_BG := Color(0.06, 0.06, 0.09, 0.95)
const BTN_NORMAL_BORDER := Color(0.3, 0.35, 0.45, 0.8)
const BTN_HOVER_BG := Color(0.1, 0.1, 0.14, 0.98)
const BTN_HOVER_BORDER := Color(0.5, 0.55, 0.65, 1.0)
const BTN_PRESSED_BG := Color(0.08, 0.08, 0.12, 1.0)
const BTN_PRESSED_BORDER := Color(0.4, 0.45, 0.55, 0.9)
const BTN_DISABLED_BG := Color(0.04, 0.04, 0.06, 0.9)
const BTN_DISABLED_BORDER := Color(0.2, 0.2, 0.25, 0.6)

# Compatibility aliases
const BUTTON_NORMAL := BTN_NORMAL_BG
const BUTTON_BORDER := BTN_NORMAL_BORDER

# Danger/red button (for Goddess Fall, cancel, etc.)
const BTN_DANGER_BG := Color(0.15, 0.04, 0.04, 0.98)
const BTN_DANGER_BORDER := Color(1.0, 0.2, 0.2, 0.7)
const BTN_DANGER_HOVER_BG := Color(0.2, 0.06, 0.06, 0.98)
const BTN_DANGER_HOVER_BORDER := Color(1.0, 0.3, 0.3, 0.9)
const BTN_DANGER_PRESSED_BG := Color(0.5, 0.05, 0.05, 1.0)
const BTN_DANGER_PRESSED_BORDER := Color(1.0, 0.2, 0.2, 1.0)
const BTN_DANGER_GLOW := Color(1.0, 0.1, 0.1, 0.5)
const BTN_DANGER_PRESSED_GLOW := Color(1.0, 0.0, 0.0, 0.85)

# Danger button hover specific
const BTN_DANGER_HOVER_FULL_BG := Color(0.35, 0.1, 0.1, 1.0)
const BTN_DANGER_HOVER_SHADOW := Color(1.0, 0.3, 0.3, 0.4)

# Success/green button (for confirm, start, etc.)
const BTN_SUCCESS_BG := Color(0.15, 0.5, 0.15, 0.95)
const BTN_SUCCESS_BORDER := Color(0.3, 0.8, 0.3, 0.9)
const BTN_SUCCESS_HOVER_BG := Color(0.2, 0.65, 0.2, 1.0)
const BTN_SUCCESS_HOVER_BORDER := Color(0.4, 1.0, 0.4, 1.0)
const BTN_SUCCESS_TEXT := Color(0.95, 1.0, 0.95, 1.0)

# Back/cancel button (muted red)
const BTN_BACK_BG := Color(0.6, 0.15, 0.15, 0.95)
const BTN_BACK_BORDER := Color(0.8, 0.3, 0.3, 0.9)
const BTN_BACK_HOVER_BG := Color(0.75, 0.2, 0.2, 1.0)
const BTN_BACK_HOVER_BORDER := Color(1.0, 0.4, 0.4, 1.0)

# Shop button states
const BTN_SHOP_AFFORD_BG := Color(0.05, 0.02, 0.02, 0.95)
const BTN_SHOP_AFFORD_BORDER := Color(1.0, 0.25, 0.2, 0.9)
const BTN_SHOP_CANT_BG := Color(0.04, 0.04, 0.05, 0.7)
const BTN_SHOP_CANT_BORDER := Color(0.4, 0.35, 0.35, 0.5)

# =============================================================================
# MISCELLANEOUS UI COLORS
# =============================================================================
const OVERLAY_DARK := Color(0, 0, 0, 0.4)               # Dark screen overlay
const OVERLAY_LIGHT := Color(0, 0, 0, 0.25)             # Light overlay
const TRANSPARENT := Color(0, 0, 0, 0)                  # Fully transparent
const DIVIDER_SUBTLE := Color(0.4, 0.4, 0.45, 0.5)      # Subtle divider line
const DIVIDER_LIGHT := Color(0.5, 0.5, 0.55, 0.25)      # Very subtle divider
const NAME_BAR_BG := Color(0.0, 0.0, 0.0, 0.85)         # Name bar background
const BADGE_BG := Color(0.0, 0.0, 0.0, 0.7)             # Badge background
const BADGE_LEADER := Color(0.4, 1.0, 0.5, 1.0)         # Leader badge color
const BADGE_SUPPORT := Color(0.6, 0.5, 1.0, 1.0)        # Support badge color

# Leaderboard rank tints
const RANK_GREEN_TINT := Color(0.588, 0.949, 0.588, 1.0)
const RANK_GOLD_TINT := Color(1.0, 0.85, 0.4, 1.0)

# Animation flash colors
const FLASH_GOLD := Color(2.0, 1.7, 0.5, 1.0)
const FLASH_GOLD_MID := Color(1.6, 1.4, 0.7, 1.0)
const FLASH_GOLD_ALT := Color(1.8, 1.5, 0.6, 1.0)
const FLASH_GOLD_DIM := Color(1.3, 1.2, 0.9, 1.0)

# Icon colors
const ICON_BASE := Color(0.7, 0.7, 0.7)
const ICON_SELECTED := Color(1, 1, 1)
const ICON_CROWN_GEM := Color(1, 1, 0.4)

# =============================================================================
# VISUAL EFFECTS COLORS
# =============================================================================
# Venetian blinds background
const VFX_VENETIAN_OVERLAY := Color(0.02, 0.05, 0.1, 0.25)
const VFX_VENETIAN_HUE := Color(0.75, 0.9, 1.0, 1.0)
const VFX_VENETIAN_BASE := Color(0.06, 0.08, 0.12)
const VFX_VENETIAN_EDGE := Color(0.6, 0.8, 1.0, 0.15)

# Diagonal stripes
const VFX_STRIPE_RED := Color(1.0, 0.2, 0.15, 0.18)
const VFX_STRIPE_DARK := Color(0.0, 0.0, 0.0, 0.12)

# Hologram scanlines
const VFX_SCANLINE := Color(1.0, 0.8, 0.8, 0.04)
const VFX_SCANLINE_SWEEP := Color(1.0, 0.7, 0.6, 1.0)  # Alpha applied dynamically
const VFX_SCANLINE_EDGE := Color(1.0, 0.7, 0.6, 0.12)

# =============================================================================
# SHOP MENU COLORS
# =============================================================================
# Card backgrounds
const SHOP_CARD_BG := Color(0.1, 0.1, 0.14, 0.95)
const SHOP_CARD_HOVER_BG := Color(0.14, 0.14, 0.2, 0.98)
const SHOP_CARD_PURCHASED_BG := Color(0.25, 0.28, 0.3, 0.95)
const SHOP_CARD_CANT_AFFORD_BG := Color(0.35, 0.08, 0.08, 0.95)
const SHOP_CARD_BORDER := Color(0.4, 0.4, 0.45, 0.7)
const SHOP_CARD_HOVER_BORDER := Color(0.7, 0.7, 0.75, 0.9)
const SHOP_CARD_MAXED_BORDER := Color(0.392, 0.86, 0.549, 1.0)

# Core counter (danger themed)
const SHOP_CORE_BG := Color(0.05, 0.02, 0.02, 0.95)
const SHOP_CORE_BORDER := Color(1.0, 0.25, 0.2, 0.9)
const SHOP_CORE_GLOW := Color(1.0, 0.2, 0.15, 0.4)
const SHOP_CORE_DIVIDER := Color(1.0, 0.3, 0.25, 0.6)
const SHOP_CORE_TEXT := Color(1.0, 0.35, 0.3, 1.0)

# Unlock button states (can afford = red, can't = muted)
const SHOP_UNLOCK_AFFORD_BG := Color(0.05, 0.02, 0.02, 0.95)
const SHOP_UNLOCK_AFFORD_BORDER := Color(1.0, 0.25, 0.2, 0.9)
const SHOP_UNLOCK_AFFORD_HOVER_BG := Color(0.1, 0.04, 0.04, 0.98)
const SHOP_UNLOCK_AFFORD_HOVER_BORDER := Color(1.0, 0.4, 0.35, 1.0)
const SHOP_UNLOCK_AFFORD_PRESSED_BG := Color(0.15, 0.05, 0.05, 1.0)
const SHOP_UNLOCK_AFFORD_PRESSED_BORDER := Color(1.0, 0.5, 0.45, 1.0)
const SHOP_UNLOCK_CANT_BG := Color(0.04, 0.04, 0.05, 0.7)
const SHOP_UNLOCK_CANT_BORDER := Color(0.4, 0.35, 0.35, 0.5)
const SHOP_UNLOCK_CANT_HOVER_BG := Color(0.05, 0.05, 0.06, 0.8)
const SHOP_UNLOCK_CANT_HOVER_BORDER := Color(0.5, 0.45, 0.45, 0.6)
const SHOP_UNLOCK_DISABLED_BG := Color(0.03, 0.03, 0.04, 0.6)
const SHOP_UNLOCK_DISABLED_BORDER := Color(0.3, 0.3, 0.35, 0.4)

# Divider colors
const SHOP_DIVIDER_AFFORD := Color(1.0, 0.3, 0.25, 0.5)
const SHOP_DIVIDER_CANT := Color(0.4, 0.4, 0.45, 0.3)

# Panel styles
const SHOP_PANEL_LOCKED_BG := Color(0.06, 0.065, 0.09, 0.95)
const SHOP_PANEL_UNLOCKED_BG := Color(0.05, 0.055, 0.08, 0.9)
const SHOP_PANEL_ACTIVE_BG := Color(0.1, 0.1, 0.14, 1.0)
const SHOP_PANEL_ACTIVE_BORDER_SELECTED := Color(1.0, 1.0, 1.0, 0.9)
const SHOP_PANEL_ACTIVE_BORDER := Color(0.4, 0.4, 0.45, 0.7)
const SHOP_PANEL_BORDER := Color(0.75, 0.75, 0.8, 0.8)
const SHOP_PANEL_SHADOW := Color(0, 0, 0, 0.35)
const SHOP_PANEL_SHADOW_SELECTED := Color(0, 0, 0, 0.5)

# Unlock panel button (red themed)
const SHOP_UNLOCK_PANEL_BG := Color(0.08, 0.085, 0.12, 0.95)
const SHOP_UNLOCK_PANEL_BORDER := Color(0.6, 0.15, 0.15, 0.8)
const SHOP_UNLOCK_PANEL_HOVER_BG := Color(0.12, 0.1, 0.15, 0.98)
const SHOP_UNLOCK_PANEL_HOVER_BORDER := Color(1.0, 0.3, 0.3, 0.95)
const SHOP_UNLOCK_PANEL_PRESSED_BG := Color(0.15, 0.08, 0.1, 0.98)
const SHOP_UNLOCK_PANEL_PRESSED_BORDER := Color(1.0, 0.4, 0.4, 1.0)
const SHOP_UNLOCK_PANEL_DISABLED_BG := Color(0.06, 0.065, 0.09, 0.7)
const SHOP_UNLOCK_PANEL_DISABLED_BORDER := Color(0.3, 0.3, 0.35, 0.5)

# Character portrait muted (locked)
const SHOP_PORTRAIT_LOCKED := Color(0.3, 0.3, 0.35, 1.0)

# Hint text colors
const SHOP_HINT_DIM := Color(0.7, 0.7, 0.75, 0.8)
const SHOP_HINT_BRIGHT := Color(0.9, 0.9, 0.95, 0.9)
const SHOP_HINT_MUTED := Color(0.5, 0.5, 0.55, 0.7)

# Title outline
const SHOP_TITLE_OUTLINE := Color(0.1, 0.1, 0.15, 1.0)
const SHOP_COUNT_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)

# Orb animation colors (golden orb)
const ORB_GLOW := Color(1.0, 0.7, 0.2)
const ORB_RAY_GLOW := Color(1.0, 0.85, 0.4)
const ORB_RAY_CORE := Color(1.0, 0.9, 0.5, 0.9)
const ORB_RING_DIM := Color(1.0, 0.8, 0.3)
const ORB_RING_BRIGHT := Color(1.0, 0.9, 0.5, 0.7)
const ORB_CENTER_WHITE := Color(1.0, 1.0, 0.9, 1.0)
const ORB_CENTER_CORE := Color(1.0, 1.0, 1.0, 1.0)
const ORB_SPARKLE := Color(1.0, 1.0, 0.8)
const ORB_CARD_GLOW := Color(0.8, 0.8, 0.9)

# Danger orb (red)
const ORB_DANGER_GLOW := Color(1.0, 0.2, 0.2)
const ORB_DANGER_RING := Color(1.0, 0.5, 0.3)
const ORB_DANGER_CENTER := Color(1.0, 0.9, 0.7, 1.0)
const ORB_DANGER_HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.6)
const ORB_DANGER_HIGHLIGHT_CORE := Color(1.0, 1.0, 1.0, 0.9)

# Reset dialog colors
const RESET_TITLE := Color(1.0, 0.4, 0.35, 0.9)
const RESET_SCAN_LINE := Color(1.0, 0.3, 0.2)

# Reset button (category reset)
const RESET_BTN_BG := Color(0.5, 0.15, 0.15, 0.9)
const RESET_BTN_BORDER := Color(0.8, 0.3, 0.3, 0.8)
const RESET_BTN_HOVER_BG := Color(0.7, 0.2, 0.2, 0.95)
const RESET_BTN_HOVER_BORDER := Color(1.0, 0.4, 0.4, 0.9)
const RESET_BTN_PRESSED_BG := Color(0.4, 0.1, 0.1, 0.95)
const RESET_BTN_PRESSED_BORDER := Color(0.6, 0.2, 0.2, 0.9)

# =============================================================================
# STAGE SELECTOR / SLIDER COLORS
# =============================================================================
# Start button (green)
const START_BTN_BG := Color(0.2, 0.7, 0.4, 1.0)
const START_BTN_BORDER := Color(0.4, 1.0, 0.6)
const START_BTN_SHADOW := Color(0.2, 0.8, 0.4, 0.4)
const START_BTN_HOVER_BG := Color(0.25, 0.8, 0.5, 1.0)
const START_BTN_HOVER_BORDER := Color(0.5, 1.0, 0.7)

# Back button (muted)
const BACK_BTN_BG := Color(0.12, 0.12, 0.16, 0.95)
const BACK_BTN_BORDER := Color(0.4, 0.4, 0.5, 0.8)
const BACK_BTN_TEXT := Color(0.85, 0.85, 0.9)

# Map/mission select button (gold themed)
const MAP_BTN_BG := Color(0.0, 0.0, 0.0, 0.5)
const MAP_BTN_BORDER := Color(0.8, 0.6, 0.2, 0.8)
const MAP_BTN_HOVER_BG := Color(0.15, 0.12, 0.08, 0.8)
const MAP_BTN_HOVER_BORDER := Color(1.0, 0.8, 0.3, 1.0)
const MAP_BTN_PRESSED_BG := Color(0.2, 0.15, 0.1, 0.9)
const MAP_BTN_PRESSED_BORDER := Color(1.0, 0.9, 0.5, 1.0)
const MAP_BTN_TEXT := Color(1.0, 0.9, 0.7)

# Difficulty slider
const SLIDER_BG := Color(0.15, 0.15, 0.2, 0.9)
const SLIDER_GRABBER := Color(0.4, 0.6, 0.9, 1.0)
const SLIDER_GRABBER_HIGHLIGHT := Color(0.5, 0.7, 1.0, 1.0)

# Goddess Fall modifier button
const GODDESS_BTN_BG := Color(0.15, 0.08, 0.12, 0.95)
const GODDESS_BTN_BORDER := Color(0.5, 0.25, 0.35, 0.8)
const GODDESS_BTN_HOVER_BG := Color(0.2, 0.1, 0.15, 1.0)
const GODDESS_BTN_HOVER_BORDER := Color(0.7, 0.35, 0.45, 0.9)
const GODDESS_BTN_PRESSED_BG := Color(0.35, 0.08, 0.12, 1.0)
const GODDESS_BTN_PRESSED_BORDER := Color(1.0, 0.3, 0.4, 1.0)
const GODDESS_BTN_SHADOW := Color(1.0, 0.2, 0.3, 0.5)
const GODDESS_ICON := Color(1.0, 0.4, 0.4)
const GODDESS_TITLE := Color(1.0, 0.85, 0.85)
const GODDESS_SUBTITLE := Color(1.0, 0.5, 0.5)

# =============================================================================
# ACHIEVEMENTS MENU COLORS
# =============================================================================
# Title styling
const ACH_TITLE_OUTLINE := Color(0.1, 0.1, 0.15, 1.0)

# Letterbox panel (top bar)
const ACH_LETTERBOX_BORDER := Color(0.75, 0.75, 0.8, 0.8)
const ACH_LETTERBOX_SHADOW := Color(0, 0, 0, 0.35)

# Main panel
const ACH_PANEL_SHADOW := Color(0, 0, 0, 0.5)

# Sidebar/content panels
const ACH_SIDEBAR_BG := Color(0.06, 0.065, 0.09, 0.95)
const ACH_CONTENT_BG := Color(0.05, 0.055, 0.08, 0.9)

# Portrait panel
const ACH_PORTRAIT_BG := Color(0.1, 0.1, 0.14, 1.0)
const ACH_PORTRAIT_BORDER := Color(1.0, 1.0, 1.0, 0.9)
const ACH_PORTRAIT_LOCKED := Color(0.3, 0.3, 0.35, 1.0)

# "LOCKED" text color
const ACH_LOCKED_TEXT := Color(0.95, 0.7, 0.2, 1.0)

# Filter button backgrounds
const ACH_FILTER_BG := Color(0.1, 0.1, 0.14, 0.9)
const ACH_FILTER_HOVER_BG := Color(0.15, 0.15, 0.2, 0.95)

# Divider line
const ACH_DIVIDER := Color(0.5, 0.5, 0.55, 0.25)

# Achievement entry hover states (unlocked vs locked)
const ACH_ENTRY_UNLOCKED_HOVER_BG := Color(0.14, 0.16, 0.22, 0.98)
const ACH_ENTRY_LOCKED_HOVER_BG := Color(0.12, 0.12, 0.18, 0.98)
const ACH_ENTRY_LOCKED_HOVER_BORDER := Color(0.5, 0.5, 0.55, 0.5)

# =============================================================================
# SETTINGS MENU COLORS
# =============================================================================
# Tab button active (light inverted style)
const SETTINGS_TAB_ACTIVE_BG := Color(0.95, 0.95, 0.98, 1.0)
const SETTINGS_TAB_ACTIVE_BORDER := Color(1.0, 1.0, 1.0, 1.0)
const SETTINGS_TAB_ACTIVE_HOVER := Color(0.05, 0.05, 0.08, 1.0)

# Tab button inactive (dark style)
const SETTINGS_TAB_INACTIVE_BG := Color(0.082, 0.11, 0.157, 0.95)
const SETTINGS_TAB_INACTIVE_BORDER := Color(0.4, 0.4, 0.45, 0.8)

# =============================================================================
# DEBUG MENU COLORS
# =============================================================================
const DEBUG_PANEL_BG := Color(0.1, 0.1, 0.15, 0.95)
const DEBUG_PANEL_BORDER := Color(0.8, 0.3, 0.3, 1.0)
const DEBUG_TITLE := Color(1.0, 0.3, 0.3, 1.0)
const DEBUG_SECTION_LABEL := Color(0.7, 0.7, 0.8, 1.0)
const DEBUG_BTN_CLOSE := Color(0.5, 0.5, 0.5)
const DEBUG_BTN_NORMAL := Color(0.3, 0.5, 0.7)
const DEBUG_BTN_TOGGLE := Color(0.5, 0.3, 0.3)
const DEBUG_BTN_DANGER := Color(0.7, 0.2, 0.2)
const DEBUG_TOGGLE_ON := Color(0.2, 0.6, 0.3)
const DEBUG_TOGGLE_OFF := Color(0.5, 0.3, 0.3)

# Shadow colors
const SHADOW_PURPLE := Color(0.4, 0.2, 0.6, 0.8)        # Purple shadow for headers
const SHADOW_HEADER := Color(0.4, 0.2, 0.6, 0.3)        # Header panel shadow

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

