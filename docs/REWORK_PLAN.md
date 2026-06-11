# SURVIVORS OF VICTORY — Single-Character Rework Plan

Decided 2026-06-11. Supersedes `docs/REMAKE.txt` (The Lift plan is dead).

## Direction (locked in)

- **Traditional Vampire Survivors**: one character, picked at run start, locked for the whole run. No squad, no tag-switching.
- **Talent tree is in-run progression**: skill points from level-ups, reset each run. Level-up keeps the VS rhythm — leveling pauses and opens the talent tree to spend the point.
- **Shop keeps only the generic stat boosts** (ATK / HP / SPD / CRIT / XP), persistent, bought with Pristine Cores.
- **Character-specific shop upgrades move into that character's talent tree** as in-run talents (placement/cost proposed per character, reviewed together).
- **Characters are unlocked by buying with Pristine Cores** (Commander free by default).
- **Squad-referencing effects reworded to solo**; AI summons (Commander burst allies, Nayuta clones, turrets) stay — they don't depend on the squad system.
- **Old saves are wiped** (save version bump). No migration, no refunds.

---

## Phase 1 — Gut the squad mechanic ✅ DONE (2026-06-11)

Single character end to end. The game should boot, run, and finish with one
character and zero squad code paths.

- `CharacterSelectMenu`: pick 1 character instead of 3.
- `GameManager`: `set_selected_characters(indices)` → single index; run/save
  payload `squad_indices` → `character_index`.
- `CharacterSwitcher`: remove (or collapse into a plain single-controller
  holder inside PlayerCore). Remove swap input handling (1/2/3 keys),
  `CharacterSwapEffect`, slot-unlock logic.
- `SquadSlots` UI: remove from HUD.
- `PlayerCore` / `PlayerWeapons` / `PlayerHudCluster` / overhead HUD: strip
  slot/switch references.
- Burst gauge: confirm it's per-run single-gauge (no per-slot state).
- Reword squad-referencing talent/upgrade descriptions and effects to
  player-only (the mechanical rework of migrated shop talents happens in
  Phase 3; this phase just makes existing talents squad-free).
- Sweep: `grep -i squad` should come back clean (or only history/docs).

## Phase 2 — Talent tree rework (structure + flow) ✅ DONE (2026-06-11)

- `TalentData`: delete `unlock` nodes from all 11 trees; `special` becomes
  the root. Remove Commander's "already in your squad" special-casing.
- `TalentTree` UI: remove the 11-character card-selection layer — the tree
  opens directly on the run's character. (Card view may survive as a
  read-only codex later.)
- Level-up flow: on level up, pause and open the talent tree (the popup IS
  the tree). TAB still opens it manually. `PlayerProgression` already grants
  +1 SP per level — keep that.
- Banked points: allow closing the tree without spending (points carry).

## Phase 3 — Shop strip + talent migration ✅ DONE (2026-06-11)

Scheme implemented: signature (was 10 cores) = row-2 root talent, 2 SP, no
prereq (3 SP for Royal Knowledge / Three Wishes). Capstone (was 20 cores) =
3 SP requiring burst (Rapunzel/Crown capstones require special instead).
`ShopMenu.has_character_upgrade()` now reads run talent state.

- `ShopData`: delete `CHARACTER_UPGRADES`; `ShopMenu` / `ShopUpgradeGrid`
  show only `GENERAL_UPGRADES`.
- Migrate each character's 1-2 shop upgrades into their `TalentData` tree as
  in-run talents. For each: proposed node placement, SP cost, and solo
  rewording presented for review before implementation. ~21 talents total.
- `PlayerUpgradeManager`: these effects now activate from talent state, not
  persistent shop purchases.
- Squad-dependent identities that don't survive rewording get redesigned at
  this point (flagged individually).

## Phase 4 — Character unlocks via Pristine Cores ✅ DONE (2026-06-11)

Character select is the storefront: locked cards show the core price, click
to confirm-unlock. Commander is the free default. Tiers: 3 (Scarlet/
Rapunzel/Snow White), 5 (Nayuta/Marian/Kilo), 8 (Crown/Cecil/Sin),
12 (Wells). Shop is general stat upgrades only; its character sidebar and
unlock panel were removed.

- Character select shows locked characters with a core price; buy to unlock.
- Commander free/default. Pricing pass over the other 10 (tiered, e.g.
  cheap early roster → expensive late roster).
- Persist unlocks in save data.

## Phase 5 — Save version bump + cleanup ✅ DONE (2026-06-11)

- `SaveManager.SAVE_VERSION = 2`: older saves are wiped on boot (user
  settings/keybinds survive the wipe).
- Default character changed to **Snow White** (sole DEFAULT_UNLOCKED;
  Commander now costs 3 cores like the other tier-1 characters).
- XP curve: base requirement 100 → 120 (geometric ×1.5 unchanged) per the
  "XP slightly too fast" note. SP economy after the change: signature
  talents (2 SP) land around level 2-3; maxing a 14-16 SP tree is a
  deep-run goal (~level 14+).
- Archived `REMAKE.txt` → `docs/archive/`. Deleted dead `UpgradeShop.gd` +
  `.tscn` (unreferenced legacy shop UI).

---

## Improvement backlog (suggestions, not yet scheduled)

Gameplay / content:
- Talent tree deepening (the "expand later" phase): passive branches,
  mutually exclusive choice nodes, weapon evolutions.
- In-run pickup/event variety (elite events, chests, shrines) to break up
  wave rhythm.
- Difficulty curve pass once solo play is tuned (squad balance assumptions
  are baked into enemy stats).

Code health:
- ✅ DONE (2026-06-11): extracted all 34 runtime-compiled embedded scripts
  (`GDScript.new()` + source strings) into 30 real files under
  `scripts/{characters,enemies}/effects/visuals/` and
  `scripts/effects/visuals/`. Shared: BurnTickEffect (Kilo + Snow White),
  EnemyShadowVisual (boss/elite/tank), EnrageExplosionVisual
  (parameterized colors). CrownController 1130→556, Wells 714→528,
  MarianBeam 814→545 lines.
- `TalentTree.gd` (~985 lines) mixes data access, layout, drawing,
  tooltips, and input — split UI from state.
- Next modularization candidates (assessed 2026-06-11): PlayerCore input/
  talent-bridge/HUD-bridge split; environment_controller scaffolding split;
  Level.gd menus + duplicate PristineCore inner classes; ModularEnemy
  status effects; basic_projectile_visual per-style split; weapon-type map
  duplicated in 3 places → CharacterData.
- `TalentData` as static dictionaries → consider Resource-based talent
  definitions (editor-editable, type-safe).
- EventBus audit after squad removal (dead signals).

UI/UX:
- Talent tree readability when it becomes the level-up popup (it must be
  fast to use 20+ times per run).
- Character select rework doubles as the unlock storefront (Phase 4) —
  design once.
