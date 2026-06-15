# HoloCure Scaling Clone — Spec

**Goal:** Clone HoloCure's stat/curve scaling exactly for a **10-minute run**, then tune per-weapon
player damage to fit. Player power comes entirely from talents + between-level shop picks (no
automatic per-level damage).

**Decisions (locked):**
1. **Verbatim** — clone HoloCure Stage 1, minutes 0:00–10:00. The run ends when Fubuzilla (the 10:00 boss) dies.
2. **Remove** the automatic `+25%/level` player damage. Strength = talents + shop upgrades.
3. **Adopt HoloCure's scale exactly** (player base HP 65, enemy ATK 2–20, etc.).

## Model differences (what "cloning" actually changes)

| Dimension | HoloCure (target) | Project (before) |
|---|---|---|
| Enemy HP model | absolute per type (8…8000) | base `1` × tier × wave |
| Enemy scaling over time | flat — difficulty via new types on a timer | `+25%/wave` on everything |
| XP curve | `round((4L)^2.1)` (gentle) | `120 × 1.5^n` (geometric) |
| Damage per level | none by default | `+25%/level` auto |
| Crit multiplier | ×1.5 | ×2.0 |
| Player base HP | 65 | 6–12 |

## §1 — XP curve

`xp_to_next(L) = round((4·(L+1))^2.1) − round((4·L)^2.1)`, with the level-1 requirement forced to **79**.
Cumulative = `round((4L)^2.1)`.

| Lvl | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 12 | 15 | 20 |
|--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Per-level | 79 | 106 | 153 | 202 | 252 | 302 | 354 | 407 | 459 | 566 | 732 | 1013 |
| Cumulative | 79 | 185 | 338 | 540 | 792 | 1094 | 1448 | 1855 | 2314 | 3393 | 5422 | 9920 |

Each level-up grants 1 talent point (unchanged). Power comes from the picks, not the level.

## §2 — Enemy schedule (HoloCure Stage 1, 0:00→10:00, verbatim)

Stats are FLAT (no time-scaling). SPD = movement multiplier; `px_per_sec = SPD × 200` (200 = chosen
anchor for SPD 1.0, tune vs. player speed). Trash types step up by *replacing* the dominant basic.

| Time | Enemy | → tier | HP | ATK | SPD | EXP |
|--|--|--|--:|--:|--:|--:|
| 0:00 | Chumbud | basic | 8 | 2 | 0.35 | 6 |
| 0:30 | Deadbeat | basic-heavy | 40 | 4 | 0.40 | 7 |
| **2:00** | **Mega Chumbud** | **mini-boss** | **600** | 6 | 0.50 | 150 |
| 3:00 | Takodachi | basic-heavy | 80 | 4 | 0.40 | 8 |
| 4:00 | KFP Employee | fast/swarm | 20 | 2 | 1.00 | 3 |
| **4:00** | **Tako Grande** | **mini-boss** | **1800** | 10 | 0.75 | 600 |
| 5:00 | Dark Chumbud | tank | 125 | 5 | 0.60 | 12 |
| 5:55 | Dead Batter | tank | 150 | 7 | 0.60 | 9 |
| **6:00** | **Mega Dark Chumbud** | **mini-boss** | **2500** | 10 | 0.90 | 1000 |
| 6:30 | Investi-Gator | tank | 180 | 7 | 0.85 | 9 |
| 7:35 | Hungry Takodachi | tank | 220 | 8 | 0.65 | 9 |
| **8:00** | **Giant Dead Batter** | **mini-boss** | **3500** | 11 | 1.00 | 1500 |
| 9:30 | Disgruntled Employee | fast/swarm | 50 | 4 | 1.15 | 7 |
| **10:00** | **Fubuzilla** | **BOSS (run end)** | **8000** | 15 | 0.80 | 2000 |

Mini-boss ~every 2 min; boss at 10:00. HoloCure's exact spawn *density*/sec is unpublished — keep a
smooth rate ramp (~2.5→5/s) and tune. Implement as a time-keyed event list (WaveDirector already
tracks `_elapsed_time`).

## §3 — Player base stats (HoloCure scale)

Sampled Gawr Gura and Tokino Sora — identical core stats.

| Stat | HoloCure base | Set to |
|---|---|---|
| Max HP | 65 | `65` (standardize, or vary ±10 per Nikke) |
| ATK | 1.00× multiplier (weapon dmg is absolute) | mult 1.0; tune weapon base dmg |
| SPD | 1.40× → ~280 px/s | `base_speed ≈ 280` |
| Crit | 3–5%, ×1.5 | base crit `0.05`, mult `1.5` |
| Haste | 0 base | `attackTime = baseAttackTime/(1+haste/100)` |
| Pickup | 40px +0.4/1% | 40px base |

## §4 — Player damage anchor (tune per-weapon)

No per-level damage, so talents + shop are the whole DPS engine:
- Start: weapon ~3–4/hit → ~2-shots an 8-HP Chumbud.
- Minute 10: build kills Fubuzilla (8000 HP) in ~30–60s → **~135–265 DPS**.
- ⇒ ~50–100× DPS climb over 10 min, entirely from picks.

## Consolidated change list

| # | File:line | From → To |
|--|--|--|
| 1 | PlayerProgression.gd:23,29,52 | geometric → `round((4(L+1))^2.1) − round((4L)^2.1)`, first=79 |
| 2 | PlayerCore.gd (level dmg) | `1+0.25(lvl-1)` → `1.0` |
| 3 | WaveDirector.gd:271 | `get_health_multiplier` → `1.0` |
| 4 | WaveDirector.gd:26-39 | 12-wave grid → time-event schedule (§2), end on Fubuzilla |
| 5 | EnemyTierConfig.gd + rapture_stats.tres | `base 1 × tier` → absolute HP/ATK (§2) |
| 6 | ModularEnemy.gd:833-861 | `5 × tier` EXP → absolute EXP (§2) |
| 7 | Bullet.gd:27 (+ BulletServer, Slash) | crit ×2.0 → ×1.5; base crit 0.15 → 0.05 |
| 8 | PlayerHealth.gd:22 + registry | base_hp 6–12 → 65; base_speed → ~280 |
| 9 | character controllers `attack_cooldown` | apply Haste formula |

Micro-decision: Crown/Nayuta/Sin bursts scale `+50%/level` — kept as ability scaling (they're
actives, like HoloCure Specials).

## Sources
- https://holocure.wiki.gg/wiki/Level_Up
- https://holocure.wiki.gg/wiki/Stage_1
- https://holocure.wiki.gg/wiki/Stat
- https://holocure.wiki.gg/wiki/EXP
- https://holocure.wiki.gg/wiki/Gawr_Gura
- https://holocure.wiki.gg/wiki/Tokino_Sora
