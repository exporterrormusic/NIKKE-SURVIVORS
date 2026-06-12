# UI Redesign — NIKKE Style Guide

Reference doc for the full UI refresh. Sources: Behance NIKKE UI 2024 case study, gameui.matme.info screenshot catalogue, in-game analysis, HoloCure wiki/UX research, and a full inventory of this project's current UI.

---

## 1. The NIKKE design language (what makes it read as NIKKE)

NIKKE's UI is **flat, hard-edged, "tactical terminal" minimalism** — a clean military command-OS, not heavy neon cyberpunk. Two visual registers coexist:

- **Admin register** (squad, inventory, character detail, shop): near-white backgrounds, charcoal text, thin hairlines, one saturated accent.
- **Field register** (lobby, battle, alerts): full-bleed art with floating translucent dark widgets, glitch/alert effects, hazard stripes.

### Shape grammar
- **Sharp 90° corners everywhere** (radius 0–2px). This is the single most load-bearing rule.
- **One 45° chamfered corner** per card/tab/frame as a signature accent (~8–16px cut, usually top-right or bottom-left).
- **Oblique lean (−8° to −12°)** on headers, tab labels, highlight bars, and callouts ("FULL BURST") — not whole panels.
- **Diamonds** (45°-rotated squares) for element/type icons; **solid triangles** (▶) as pointers/bullets; **bracket corners** ⌐ ¬ for selection states.

### Palette (approx hex)
| Role | Value |
|---|---|
| Base near-black | `#0E1116`–`#14181F` |
| Panel charcoal | `#1C212A`, raised `#262C36` |
| Translucent HUD black | black @ 35–60% alpha |
| Light page bg (admin) | `#EDEFF2` / `#F4F5F7`, white cards, `#D8DCE1` hairlines |
| Signature cyan (CTA/gauges/selection) | `#35C5F2`, gradient `#5BD2F7 → #1F8FE0` |
| Selection yellow | `#FFD23F` / `#F8C300` |
| Alert red/orange | `#E8392E` / `#FF5722` |
| Rarity | SSR gold `#F8A33B`, SR violet `#A06BE0`, R steel-blue `#5FA8E8` |

Gradients are subtle/short. Glow only on gauges (cyan, 4–8px). **Scanlines / RGB-split glitch / noise only in alert contexts** (boss intro, EMERGENCY banners) — never on everyday menus.

### Typography
- Base UI: **Pretendard** (already in the project ✔).
- Display/alerts: heavy condensed all-caps — NIKKE uses Abolition/Voltec; free stand-ins: **Anton**, **Archivo Black**, **Saira Condensed** (good for stat numerals).
- **Paired-label signature:** big title + tiny all-caps letter-spaced English subtitle underneath at ~40% size, light gray (e.g. "출격" / `SQUAD`). For an English game: big title + small spaced-out sublabel ("CHARACTERS" / `SELECT YOUR NIKKE`).
- Headers: bold condensed all-caps, often ~10° oblique, +5–15% letter-spacing. Numbers: large condensed bold; labels above them in tiny gray caps.

### Panels & decoration
- Flat layers, no soft drop shadows — separation by value steps.
- **2–3px accent bar on the left/top edge** of section headers and selected rows.
- 1px hairline dividers instead of boxed groups.
- Margin greebles (small, low-contrast): **barcodes + fake serial numbers** ("NIKKE-077", "ARK SYSTEM v2.x"), **dot grids**, **plus-sign registration marks**, thin crosshair/reticle motifs.
- **Hazard stripes**: yellow/black for caution, red for boss alerts — on warning popups and locked content.

### Buttons
- Primary CTA: solid cyan rect (sharp or one chamfer), short vertical gradient, white bold all-caps condensed label, optional 2px darker bottom edge. Cost displayed *inside* the button, right-aligned.
- Secondary: light fill, charcoal text, 1px border. Destructive: red. Disabled: solid gray (not transparent).
- States: press = darken + scale ~0.96; selection = yellow underline/fill. No soft hover glows.
- Icon tiles (lobby-style): dark glass rounded-square (~10% radius — the one place mild rounding exists), white flat glyph, label underneath, red notification dot top-right.

### Motion
- Fast snappy slide-ins: 150–250ms, strong ease-out, 20–40px travel, ~30ms stagger per list item.
- Diagonal wipes between major screens.
- Glitch (RGB split, slice displacement, scanline flash) reserved for dramatic moments.
- Gauges fill with a bright leading edge + overshoot flash. Claimables shimmer.

### The 10-point "reads as NIKKE" checklist
1. Sharp corners + one 45° chamfer per card
2. Oblique condensed all-caps headers with English subtitle pairs
3. Light admin screens / dark translucent field screens split
4. Cyan CTAs, yellow selection, red alerts
5. Barcode/serial/plus-mark/dot-grid margin greebles
6. Hazard stripes on warnings
7. Triangle pointers + diamond icons
8. Thin glowing segmented gauges
9. Red notification dots on icon tiles
10. Glitch/scanlines only at dramatic moments

---

## 2. HoloCure — structural/UX lessons (function, not style)

- **Decision-point information**: full stat panel ON the level-up screen; collab recipes ON the level-up screen and pause menu; special-attack text ON character select. Never make the player memorize.
- Level-up screen: left = full current stats; right = 4 choices color-coded by type; Reroll / Eliminate / Hold utility buttons (shop-unlocked, so the screen grows with the player).
- Cheap progress indicators: rank dots, green checks, "SOLD!" stamps, silhouettes for locked.
- **Penalty-free refunds** on permanent upgrades → experimentation.
- Readability toggles (attack opacity, damage numbers, screen shake, hide-HP-if-full).
- Coins awarded win or lose; explicit "Stage Clear" banner.
- **Plan the character grid for roster growth** (HoloCure rebuilt theirs 4+ times).
- Off-screen pointers (arrow to objective) instead of a minimap.
- Full keyboard/controller parity in every menu.

---

## 3. Current project state (inventory summary)

- 1920×1080, `canvas_items` stretch. ~30 UI scripts (~10.7k lines), 16 UI scenes.
- **`scripts/ui/UITheme.gd`** is already the central palette singleton (100+ constants) — current scheme: dark navy bgs (`#0A0E14`), near-white primary, **gold `#FFB627` + pink `#FF6B9D` accents**.
- Fonts: Futura Condensed Extra Bold (titles) + Pretendard Bold/Medium — already very close to NIKKE's stack.
- Rounded corners (3–12px) scattered across ~40–50 inline `.tscn` StyleBoxFlats AND ~118+ runtime `StyleBoxFlat.new()` calls. **No `.theme` resource exists.**
- Screens: Intro, MainMenu, CharacterSelect (+stage phase), ModeSelect, Settings, Leaderboard, Achievements, Shop, plus HUD cluster (HP/Burst/Stamina), XP bar, Talent Tree (in-run), Pause/Defeat/Victory (code-built), HUNT UI, music player, minimap.
- Already-NIKKE-ish components exist: DiagonalStripes, HologramScanlines, VenetianBlindsBackground, SciFiBackButton.

## 4. Approved decisions (2026-06-12)

- **Both registers**: light "admin" screens (Shop, Settings, Achievements, character detail) + dark "field" screens (MainMenu, HUD, Pause, alerts).
- **Full NIKKE palette**: cyan `#35C5F2` primary CTA/gauges, yellow `#FFD23F` selection, red `#E8392E` alerts. Gold/pink retired (gold survives only as SSR rarity).
- **Full decoration treatment**: chamfers, oblique headers, subtitle pairs, barcodes/serials, dot grids, plus-marks, hazard stripes, triangle pointers.
- **Foundation first**: central style factory + palette + sharp-corner sweep before any menu pass.

## 4b. MainMenu — DONE (2026-06-12)

Approved layout: **V1-A** (round-3 mockup, [docs/mockups/main_menu_layouts_v3.html](mockups/main_menu_layouts_v3.html)).
- Left column (alternating ±12px stagger): SHOP (blue card) → LEADERBOARDS → ACHIEVEMENTS → SETTINGS (dark cards).
- Right: big white "Ark-style" PLAY card ("SELECT NIKKE & DEPLOY") with QUIT (dark red) beneath.
- Top-right strip: NOTICE chip (white+blue, red unread dot, opens patch-notes popup) + Pristine Core pill with "+" shop shortcut.
- Logo + greeble strip (barcode + "SOV-2026 // ARK SYS <version>") sized to the logo's visible pixels at runtime; corner version label removed. OUTPOST removed.
- New reusable components: `NikkeCardButton` (5-style card vocabulary), `NikkePopup` (white admin card on scrim; used by patch notes + quit confirm), `CorePillButton`, `NikkeGreebles`. `MainMenuOptionButton` deleted (superseded).
- Scene-first: layout lives in MainMenu.tscn, MainMenu.gd is wiring/popups/focus only.

## 4c. CharacterSelect — DONE (2026-06-12)

Approved: **v7 mockup** ([docs/mockups/character_select_v7.html](mockups/character_select_v7.html)), light admin register.
- 4-column grid (revisit 5-col when roster grows), white chamfered cards, weapon tags, no tier coloring, locked = dimmed + core cost, RANDOM as translucent glass grid slot.
- Click selects (brackets + detail swap <0.4s + mild per-character page tint); cyan DEPLOY slab advances to stage select.
- Diagonal burst-art strip between grid and detail: enters from off-screen right, drifts ±24px/30s cycle; motion drawn (not node position) for sub-pixel smoothness; 5px white edge bands hide aliasing.
- Detail panel: oblique name + "SQUAD // WEAPON" role line (squad data added to CharacterRegistry/CharacterData), stat bars, Special/Burst text.
- New components: `DiagonalArtStrip`, `CharacterSelectCard`, `CharacterDetailPanel`; `CorePillButton` gained light_register. Unlock confirm now uses `NikkePopup`.
- Flow change: **Mode Select removed** — PLAY goes straight to character select.
- 2026-06-12 follow-up: top-right strip is now OPERATOR chip (live portrait+name of selection) + BACK; the core-pill counter was removed from this screen.

## 4d. MissionSelect (stage select) — DONE (2026-06-12)

Approved: **"Field Briefing" A2 looping carousel** ([docs/mockups/stage_select_vA_v4.html](mockups/stage_select_vA_v4.html), 4 mockup rounds).
- Dark field register: the selected zone's art fills the screen (cover-fit, dual gradient shade), floating dark-glass widgets on top.
- Left: mode stack (STANDARD/ENDLESS from StageRegistry, chamfered glass cards, cyan accent when selected) + GODDESS FALL hazard toggle.
- Bottom: infinite-loop center carousel of skewed zone thumbnails (`ZoneCarousel`/`ZoneThumb`, circular shortest-path layout — both sides always populated, edge fade hides the wrap jump). Opens on a random zone; the player's pick is what they play (replaces old roll-on-open randomization). Oblique zone name + "ZONE NN // NN" counter above.
- Right: ops panel — THREAT LEVEL cap, difficulty slider ×1–100 with live ENEMY HP / ENEMY ATK / CORES scaling cells, chamfered cyan MISSION START.
- GODDESS FALL arm FX (background-only, under all UI): red radial vignette + pulse + glitch sweep over the map art, red map tint, "⚠ SHE DESCENDS PROTOCOL ARMED ⚠" banner, MISSION START becomes pulsing red SHE DESCENDS. Timer music + GameManager flags preserved from the old selector; everything disarms on back/ESC.
- Top-right: OPERATOR chip (deployed character) + BACK — mirrored on character select.
- New: `scenes/ui/MissionSelect.tscn` + `MissionSelect.gd`, components `ZoneCarousel`, `ZoneThumb`, `MissionModeButton`, `HazardToggle`, `OperatorChip`; zone data extracted to `scripts/systems/MapRegistry.gd` (mode×zone model: StageRegistry holds modes). Old code-built `StageSelector.gd` deleted.

## 4e. Shop — DONE (2026-06-12)

Approved: **"Supply Terminal" with category tabs** ([docs/mockups/shop_v2.html](mockups/shop_v2.html), 2 rounds; chosen for future category growth — outfits/skins slot in as new tabs, detail pane adapts per item type).
- Light admin register. Left: `NikkeTabBar` rail (UPGRADES only until more categories exist) + `ShopListRow` list (flat glyph tile, name, LV) + RESET & REFUND (white, red border).
- Right: white detail card — glyph watermark, oblique name, desc, LV now ▶ next, CURRENT/NEXT bonus cells, NEXT-N COST cell, chamfered cyan **BUY** and **BUY ×N** (bulk caps at remaining levels; MAXED state hides bulk). Buttons gray when unaffordable; affordability live-updates via core_count_changed.
- Detail panel updates instantly — the CharacterDetailPanel swap motion was tried here and removed per user feedback (stays exclusive to character select; the shop is a rapid-interaction screen).
- Reset now confirms via `NikkePopup` (CANCEL / danger REFUND) instead of firing instantly.
- Emoji icons replaced by flat glyphs (▲ ✚ ≫ ✦ ◈) + per-stat tints, stored in `ShopData.GENERAL_UPGRADES` along with per_level/unit display fields (+ `ShopData.format_bonus()`).
- Scene-first: chrome in ShopMenu.tscn (was 100% code-built); ShopMenu.gd keeps its static gameplay API (get_upgrade_bonus / is_character_unlocked / unlock_character / has_character_upgrade) and save format untouched. `ShopUpgradeGrid.gd` deleted. `CorePillButton` gained `show_plus` (hidden inside the shop). New reusable: `NikkeTabBar`, `ShopListRow`.

## 4f. Settings — DONE (2026-06-12)

Approved: **"Category Rail"** ([docs/mockups/settings_v2.html](mockups/settings_v2.html), 2 rounds; closest to NIKKE's settings).
- Light admin register. Left rail (`CategoryRailButton`): AUDIO / VIDEO / GAMEPLAY / CONTROLS, each with descriptor line, yellow selection.
- AUDIO: Music/SFX sliders with oblique % readouts. VIDEO: resolution dropdown + fullscreen as `NikkeSegmentToggle` (2-cell ON/OFF, replaces the dropdown).
- GAMEPLAY (new): SCREEN SHAKE and DAMAGE NUMBERS readability toggles with hint lines. Gates: `CombatJuice.camera_shake()` early-returns when disabled; `FloatingDamageNumber.spawn()` suppresses DAMAGE/CRITICAL (heals always show). Persisted in SettingsManager "gameplay" section (screen_shake_enabled / damage_numbers_enabled, default ON).
- CONTROLS: 8 keycap binding buttons in a 2-col grid (white keycap chips, yellow blink while capturing; capture logic carried over incl. mouse wheel/extra buttons and the Escape→Pause exception) + new red-bordered RESET BINDINGS TO DEFAULTS (calls SettingsManager.reset_to_defaults()).
- Scene-first SettingsMenu.tscn rewrite; SettingsMenu.gd keeps back_requested (MenuManager + in-game pause overlay) and PROCESS_MODE_ALWAYS. New reusables: `NikkeSegmentToggle`, `CategoryRailButton`.

## 4g. Leaderboards — DONE (2026-06-12)

Approved: **"Operator Gallery"** ([docs/mockups/leaderboard_v2.html](mockups/leaderboard_v2.html) variant E, 2 rounds).
- Light admin register. 4-col grid of `OperatorRecordCard`s — one per registry character (best run each, matching the per-character data model): burst art band, rank numeral overlay (white — gold rejected), abbreviated score, "×diff · WAVE n" line, red ☠ chip for goddess-fall runs. No-data operators grayed with "NO DATA".
- Always-visible detail pane (replaces the old StatsPanel popup): **full-height portrait art strip** on the left (bursts are 9:16 — a tall strip shows them head-to-toe with zero zoom; landscape crops were rejected as "zoomed in"), beside a column with oblique name (length-aware font sizing), RANK NN // BEST SORTIE, stacked caption/value stat blocks (full score / wave / difficulty / date), hazard-bordered "☠ GODDESS FALL RUN" band. Damage breakdown removed (squad system gone). Summary strip (total score/runs) rejected.
- Art framing is data-tuned: `CoverArtRect` (focus_x/focus_y cover-crop component) + per-character `FACE_FOCUS_OVERRIDES` (card vertical anchor) and `DETAIL_FOCUS_X_OVERRIDES` (strip horizontal anchor for off-center subjects like Wells/Cecil). Cards use face-framed portrait-sq; the strip uses burst.
- Ranked-by-score ordering with unranked operators trailing; cards drawn (single _draw pass: cover-UV art, chip, numerals) like ZoneThumb.
- Scene-first LeaderboardMenu.tscn rewrite; back_requested + PROCESS_MODE_ALWAYS kept; old two-column row layout, 🫅 emoji badge, and popup deleted.

## 4h. Achievements — DONE (2026-06-12)

Approved: **"Commendations Rail" + ghost art W2** ([docs/mockups/achievements_v3.html](mockups/achievements_v3.html), 3 rounds — round-1 plain rail was "bland"; banner versions rejected in favor of art *behind* the list).
- Light admin register. Left rail (`AchievementRailRow`): GENERAL (gold crown tile) + one row per operator — portrait chip, name, n/m count (green when complete), thin green completion underbar; locked operators dimmed.
- Right card: oblique category title + "N OF M COMMENDATIONS EARNED" + ALL/COMPLETE/INCOMPLETE segmented filter; selected operator's burst art ghosts behind the list at ~22% (CoverArtRect + white gradient fade; rows are 92%-alpha white so it breathes through; GENERAL shows no ghost).
- `AchievementRow`: drawn medal diamond (gold ✓ = cleared, cyan % = in progress, gray ◆ = untouched), status accent edge, title/desc, cyan progress gauge with comma-formatted counts, drawn CLEARED chip.
- Sort unlocked-first then by progress; two-stage ESC (content → rail → exit) and per-category counts preserved from the old menu.
- Scene-first AchievementsMenu.tscn rewrite (was 100% code-built with VenetianBlinds/SciFiBackButton).

## 4i. Pause + Results — DONE (2026-06-12)

Approved: **P2 "Center Terminal" pause + R1 "After-Action Report" results** ([docs/mockups/pause_results_v2.html](mockups/pause_results_v2.html), 2 rounds — round-1 R1 had absolute-positioned blocks that overlapped; fixed by making the whole right side one flex/VBox column).
- Dark field register, overlay on frozen gameplay (dim ColorRect ~62%; no blur). One scene `PauseMenu.tscn` + `PauseMenu.gd` (CanvasLayer, layer 125) holds BOTH layouts, toggled by mode; all of the old code-built UI replaced scene-first. Signals/API preserved verbatim for Level.gd + bosses: `show_pause/show_defeat/show_victory/hide_menu`, the five `*_requested` signals, ESC-to-close in PAUSE mode only.
- **Pause**: plain "PAUSED" title (user chose Mixed wording), FIELD TELEMETRY glass panel left (portrait + name + SQUAD // x + 2-col `KVCellGrid`: score/wave/time/difficulty/kills/bosses), command column center (`PauseCommandButton` chamfered slabs: RESUME primary cyan w/ ESC hint, RESTART MISSION, CHARACTER SELECT, SETTINGS, CHEATS, ABANDON — MAIN MENU danger), DAMAGE LOG // RECENT HITS right (`NikkeDamageLog` severity-coded rows).
- **Results**: full-height burst strip left (CoverArtRect, ~420px — box aspect 0.583 vs art 0.5625 so virtually no crop) with horizontal+bottom gradient fades and NIKKE // name; right column = verdict (MISSION COMPLETE green / NIKKE DOWN red, themed subtitle), yellow FINAL SCORE + skewed ☠ GODDESS FALL chip on one baseline, 3-col report cells (wave/time/difficulty/kills/bosses/damage dealt), then **reward bar on victory / damage log on defeat** (user: defeat only), commands pinned bottom (PLAY AGAIN / RETRY MISSION primary).
- New components: `PauseCommandButton` (default/primary/danger chamfered slabs), `KVCellGrid` (caption-over-value cells w/ hairline separators, reused by both layouts), `NikkeDamageLog` (reads DamageLog singleton on refresh()).
- Old `StatsPanel.gd` + `DamageLogPanel.gd` DELETED (pause-only consumers). Cheats flow preserved (CheatsMenu instanced into %CheatsHost, mid column hidden while open). Level.gd now instantiates the scene instead of `set_script` on a bare CanvasLayer.
- **Global wording change (user)**: "OPERATOR" → "NIKKE" in all player-facing text — OperatorChip caption, leaderboard header sub, shop upgrade desc suffix ("every Nikke, every run"). Internal class names (OperatorChip, OperatorRecordCard) unchanged.
- Live-review fixes: the overlay **hides the entire in-game HUD** while open (`_hide_game_hud()` hides every positive-layer CanvasLayer except the menu — HUD spans layers 10–126 incl. the music player ABOVE pause at 126 — and restores the exact set on close); all mockup pixel values scaled **×1.5** for the 1920×1080 viewport (mockups are authored at 1280×720); dim raised to 74%.

## 4j. In-Game HUD — DONE (2026-06-12)

Approved: **V3 "Bracket Frames"** ([docs/mockups/hud_v2.html](mockups/hud_v2.html), 2 rounds — round 1 offered Glass Tactical / Frameless / Brackets; user chose V3 + V3-style boss bar + tiny bar labels with values OUTSIDE the bars + **stamina bar removed** (sprint needs no gauge)). Element positions kept from the proven HoloCure layout. All sizes = mockup ×1.5.
- `BracketStyleBox` (new component): translucent dark fill + top-left/bottom-right corner brackets — the shared HUD panel vocabulary (cluster, minimap, music, cores use it or draw the same brackets).
- **PlayerHudCluster**: bracket panel, 90px portrait (thin border, low-HP red tint kept), two rows — HP (green) and BURST (yellow) — small letter-spaced labels left, flat bars, oblique value numerals outside right ("78/100", "45%" → "READY!" pulse). Stamina row deleted; `update_stamina()` kept as a no-op (PlayerCore wiring untouched). All API preserved (configure/update_health/update_burst/set_character/set_burst_unlocked/set_burst_ready, shake, signals).
- **XPUI**: yellow-bordered LV chip + slim flat cyan bar, repositioned from full-width top edge to under the cluster.
- **WaveUI**: skewed dark chip top-center — oblique WAVE text + cyan letter-spaced timer + slim progress strip along the chip bottom. The wave text label moved INSIDE WaveUI (was the separate WaveDisplay label in Level.tscn, now deleted; Level.gd's direct label pokes removed — `wave_changed → update_wave` covers it). Goddess Fall behaviors kept: DEFEAT THE QUEEN red text, countdown, red strip.
- **MiniMap**: bracket frame, 222px, aligned with the 30px HUD margin grid.
- **ScoreUI**: frameless — letter-spaced SCORE caption over right-aligned oblique white numerals (gold dropped, consistent with the leaderboard decision); FPS overlay kept.
- **PristineCoreDisplay**: red-bracket chip, drawn core orb + oblique numerals; pickup flash now brightens the brackets. (HUD-only component — menus use CorePillButton.)
- **MusicPlayerUI**: bracket chip, flat cyan-hover transport buttons, slim progress line; hover-blocking + PROCESS_MODE_ALWAYS untouched.
- **BossHealthBar**: moved top→bottom-center per mockup — skewed red "☠ NAME" chip, segmented fill (purple boss / red super-boss / low-HP blend kept) with red corner brackets, oblique % outside right; shield bar + enrage timer logic preserved.
- Orphan StaminaUI.tscn deleted.

## 4k. Talent Tree — DONE (2026-06-12)

Approved: **C3a "Ability Lanes"** ([docs/mockups/talent_tree_v3.html](mockups/talent_tree_v3.html), 3 rounds — round 1 chose V2 bracket nodes but "the connection system doesn't work, needs to be like WoW"; round 2 offered Vertical Spine / Branching Graph / Ability Lanes, C3 won; round 3 fixed squashed bottom row to uniform node heights + wider nodes + edges that actually touch; final tweak: **arrowheads only on the vertical left-column edges**, side stubs plain).
- In-run overlay (level up / TAB), dark field register. Header TALENTS + "NIKKE // <name>", yellow SKILL POINTS chip top-right, glass FIELD STATUS panel left (portrait, oblique name, LV, KV rows with **green bonus labels**; ATK shows a plain number — the old "×" suffix removed per user), tree lanes right, plain-rect CLOSE chip (**no chamfer on close buttons** — chamfer stays reserved for action slabs).
- Layout (generic over TalentData col/row): SPECIAL and BURST roots in a left column, their 2 mods stacked right; capstone (row2 col2) bottom-left under the roots, signature (row2 col0) bottom-right. All nodes uniform 126px tall.
- `TalentTreeLines.gd` rewritten data-driven: edges computed from live button rects so they always land on node borders — same-row = elbow split (stem/rail/stub, no arrowheads), cross-row = vertical gate with arrowhead; cyan-lit when the prerequisite is owned.
- Bracket nodes (HUD vocabulary): brackets recolor/grow by state (dim locked / white available / yellow grown on hover / cyan ACTIVE / green MAX), yellow cost chip, level pips for multi-rank, state tags. Tooltip restyled (cyan border, oblique title, cost/lock line added).
- Old scanline open/close effect replaced with a simple 0.3s fade. All public API preserved verbatim (static instance, show_tree, skill point methods, signals — PlayerTalentBridge/ShopMenu/CharacterInfoPanel untouched). TalentData untouched.

## 5. Approach

1. **Foundation pass first**: build a `UIStyleFactory` (or extend UITheme) producing the canonical NIKKE styleboxes — sharp rect, chamfered card (via StyleBoxFlat skew/polygon), accent-edge header, hazard stripe, oblique highlight bar, primary/secondary/danger buttons, gauge styles. Update UITheme palette. Kill all `corner_radius > 0` (except icon tiles ~10%).
2. Then **menu by menu**, reusing factory styles: MainMenu → CharacterSelect → ModeSelect → Shop → Settings → Pause/Results → HUD → TalentTree → Achievements/Leaderboard.
3. Decisions logged per menu in this doc as we go.
