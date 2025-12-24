# NIKKE SURVIVORS

A Vampire Survivors-style roguelite fan game featuring characters from **Goddess of Victory: NIKKE**.

> ⚠️ **DISCLAIMER**: This is an unofficial, fan-made game. It is not affiliated with, endorsed by, or sponsored by ShiftUp or any official partners. All trademarks and characters belong to their respective owners.

---

## 🎮 How to Play

### Download & Run
- **Windows**: Download the latest release `.exe` from [Releases](../../releases) and run it
- **From Source**: Clone this repo and open in [Godot 4.5+](https://godotengine.org/), then press F5

---

## 🕹️ Controls

| Action | Key |
|--------|-----|
| Move | WASD / Arrow Keys |
| Aim | Mouse |
| Attack | Left Click (hold for auto-fire) |
| Special Attack | Right Click |
| Burst (Ultimate) | E (when gauge is full) |
| Dash | Shift (costs stamina) |
| Switch Character | Mouse Wheel / Q |
| Talent Tree | T |
| Pause | Escape |

---

## 🎯 Gameplay Overview

### Objective
Survive waves of Rapture enemies and defeat the final boss to complete a run.

### Core Loop
1. **Select your squad** – Choose 3 characters (1 Main + 2 Support)
2. **Fight waves** – Enemies spawn in increasing intensity
3. **Collect XP orbs** – Level up to earn skill points
4. **Spend skill points** – Open the Talent Tree to unlock abilities and support characters
5. **Defeat bosses** – Bosses appear on certain waves
6. **Earn Pristine Cores** – Spend them in the Shop for permanent upgrades

### Wave Structure
- **Waves 1-2**: Basic enemies
- **Waves 3+**: Elite enemies begin spawning
- **Waves 5, 7, 9**: Boss encounters
- **Wave 11**: Final Boss: **Rapture Queen N01** + multiple elites

---

## 👥 Characters

11 playable NIKKEs, each with unique weapons and abilities:

| Character | Weapon | Playstyle |
|-----------|--------|-----------|
| Snow White | Rifle | Precision sniper with auto-turrets |
| Scarlet | Sword | Fast melee with dash attacks and HP sacrifice |
| Rapunzel | Launcher | Support healer with rockets |
| Nayuta | SMG | Clone summoner |
| Commander | Assault Rifle | Leader with ally summons |
| Marian | Minigun | Charm specialist with laser beam |
| Crown | Minigun | Cavalry with mount summon |
| Kilo | Shotgun | Explosive shells & shield generation |
| Cecil | SMG | Hacker with drone support |
| Sin | SMG | Manipulator with charm and DOT effects |
| Wells | Sniper | Time manipulator with bullet-time abilities |

**Starting Characters**: Snow White, Scarlet, Rapunzel  
**Unlock Others**: Purchase in Shop with Pristine Rapture Cores

---

## 📈 Progression

### In-Run (Talent Tree)
- Earn XP → Level up → Gain skill points
- Unlock your support squad members mid-run
- Upgrade your Special and Burst abilities

### Permanent (Shop)
- **General Upgrades**: ATK, HP, Speed, Crit Chance, XP Gain
- **Character Upgrades**: Unique powerful abilities (e.g., extra lives, heal on kill, 2x XP)
- **Character Unlocks**: 3 cores each

---

## 🗺️ Game Modes

| Mode | Description |
|------|-------------|
| **Normal** | 11 waves, defeat the final boss to win |
| **Endless** | No wave limit – survive as long as possible |
| **Goddess Fall** | Survive the Rapture Queen |

**Difficulty**: Adjustable slider (higher = tougher enemies, more rewards)

---

## 👾 Enemies

| Type | Description |
|------|-------------|
| **Basic** | Standard melee units, spawn in large groups |
| **Tank** | High HP, glowing orange, resistant to knockback |
| **Shielder** | Blue glow, generates a protective shield for nearby allies |
| **Exploder** | Fast suicide bombers, red glow, explode on contact |
| **Elite** | Mini-bosses with red aura, high stats, drop chests |
| **Boss** | Large unique enemies with special attacks (lasers, missiles) |
| **Super Boss** | Extremely powerful versions with purple shields and regeneration |

---

## 🌙 Day/Night Cycle

The game features a dynamic time-of-day system:
- **Day**: Normal visibility
- **Night**: Darker environment with the player having a subtle glow for visibility
- **Storm**: Special weather effects on certain maps

---

## 🛠️ Debug Features

Access the debug menu by pressing **F1** or **`** (tilde) during gameplay:
- **Spawn Controls**: Spawn specific enemies (Elite, Boss, Super Boss, Tank, Shielder, Exploder)
- **Time Controls**: Speed up game (5x, 10x) or freeze time
- **Visual Options**: Toggle damage numbers, hit flash, or performance stats
- **Invincibility**: Toggle God Mode for testing

---

## 🛠️ Development

Built with **Godot 4.5** using GDScript.

### Project Structure
```
scenes/          # Scene files (.tscn)
scripts/         # GDScript source code
  ├── characters/  # Character controllers
  ├── enemies/     # Enemy AI
  ├── player/      # Player core mechanics
  ├── systems/     # Game managers (saves, achievements, etc.)
  └── ui/          # Menu and HUD scripts
src/             # Additional source modules
  └── world/       # Environment and weather systems
assets/          # Art, sounds, fonts
resources/       # Godot resources (.tres)
```

### Building from Source
1. Install [Godot 4.5+](https://godotengine.org/download)
2. Clone this repository
3. Open `project.godot` in Godot
4. Press F5 to run, or Export for release builds

---

## 📜 License

This is a non-commercial fan project. All NIKKE characters and related IP belong to ShiftUp.

---

*Snow White is best girl. Accept the truth of the poncho cult.* 💜
