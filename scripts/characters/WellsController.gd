extends "res://scripts/characters/CharacterController.gd"
class_name WellsController
## Wells - Time Traveler Sniper
## Special: "Mnemosyne Project" - Bullet Time (Hold E). Uses fuel gauge.
## Burst: "Echoes of Hope" - Summons Marian, Kilo, or Crown.

# Preload scripts
# NOTE: Dynamic load used for SummonedAlly to prevent cyclic dependency with CharacterRegistry
# const SummonedAllyScript = preload("res://scripts/player/SummonedAlly.gd")

# Sniper config (Base is 1650 in registry, overridable here)
var bullet_speed: float = 1650.0

# Special Config (Bullet Time)
var max_fuel: float = 5.0
var current_fuel: float = 5.0
var fuel_recharge_rate: float = 1.0 # 1 sec per sec
var is_time_slowed: bool = false
const TIME_SCALE_SLOW: float = 0.2

# Upgrades
var secrets_of_past_level: int = 0 # 0-3
var dust_to_dust_level: int = 0 # 0-3

# Burst Config
var summon_duration: float = 10.0
var _active_allies: Array = []
var unlock_crown: bool = false
var unlock_kilo: bool = false

# Temporal Breach: Enemy Marian tracking
var _enemy_marian: Node2D = null
var _special_blocked: bool = false

var _filter_rect: ColorRect = null
var _filter_layer: CanvasLayer = null

func _on_initialize() -> void:
    # Set initial fuel
    current_fuel = max_fuel
    # Override base cooldown handling - we handle it manually via fuel
    data.special_cooldown = max_fuel
    special_timer = 0.0 # UI uses this for "Cooldown/Spent", 0 = Ready/Full

func _on_process(delta: float) -> void:
    _handle_time_slow_input(delta)
    _cleanup_allies()
    
    # Sync UI timer for fuel gauge
    # UI Logic: special_timer is "Cooldown".
    # We want: 0 = Full Fuel (Ready). 10 = Empty.
    # So special_timer = (max_fuel - current_fuel)
    special_timer = max_fuel - current_fuel

## Override to provide accurate fuel gauge reading for UI
func get_special_progress() -> float:
    # Returns 1.0 when full, 0.0 when empty
    if max_fuel <= 0:
        return 1.0
    return clampf(current_fuel / max_fuel, 0.0, 1.0)

func _on_cleanup() -> void:
    # Ensure effects are removed if character is swapped/game ends
    _remove_audio_distortion()
    if is_time_slowed:
        _end_time_slow()

func _cleanup_allies() -> void:
    for i in range(_active_allies.size() - 1, -1, -1):
        var ref = _active_allies[i]
        if not ref.get_ref():
            _active_allies.remove_at(i)

func _on_physics_process(delta: float) -> void:
    if is_time_slowed:
        # Enforce slow scale in case it gets reset
        var game_manager = player.get_node_or_null("/root/GameManager")
        if game_manager and game_manager.enemy_time_scale != TIME_SCALE_SLOW:
            game_manager.enemy_time_scale = TIME_SCALE_SLOW
        _apply_active_effects(delta)

func _handle_time_slow_input(delta: float) -> void:
    if not special_unlocked:
        return
    
    # Block special if enemy Marian is active
    if _special_blocked:
        _check_enemy_marian_status()
        # Still recharge fuel even when blocked
        if current_fuel < max_fuel:
            current_fuel += fuel_recharge_rate * delta
            if current_fuel > max_fuel:
                current_fuel = max_fuel
        return

    # Minimum fuel required to START Bullet Time (prevents stuttering)
    const MIN_FUEL_TO_START := 1.0
    
    # Special Attack uses Right Mouse Button (thrust action)
    var can_start := current_fuel >= MIN_FUEL_TO_START
    var can_continue := is_time_slowed and current_fuel > 0.0
    
    if Input.is_action_pressed("thrust") and (can_start or can_continue):
        if not is_time_slowed:
            _start_time_slow()
            
        # Drain fuel
        current_fuel -= delta
        if current_fuel <= 0.0:
            current_fuel = 0.0
            _end_time_slow() # Force stop
            # 10% chance to spawn enemy Marian when fuel empties
            _roll_temporal_breach()
            
    else:
        if is_time_slowed:
            _end_time_slow()
            
        # Recharge fuel
        if current_fuel < max_fuel:
            current_fuel += fuel_recharge_rate * delta
            if current_fuel > max_fuel:
                current_fuel = max_fuel


# Audio Effect indices (cached)
var _music_bus_idx: int = -1
var _sfx_bus_idx: int = -1
var _distortion_effect: AudioEffectLowPassFilter = null
var _distortion_idx_music: int = -1
var _distortion_idx_sfx: int = -1

func _start_time_slow() -> void:
    is_time_slowed = true
    var game_manager = player.get_node_or_null("/root/GameManager")
    if game_manager:
        game_manager.enemy_time_scale = TIME_SCALE_SLOW
    
    # Visual Effect: Monochrome Filter
    _create_mono_filter()
    
    # Audio Effect: Underwater Distortion
    _apply_audio_distortion()
    
    # Pop player out of filter
    player.z_as_relative = false
    player.z_index = 200 # Above filter (50)
    
    # Apply Speed Boost immediately (Talent 2)
    if secrets_of_past_level >= 2:
        _apply_speed_boost(true)
        
func _end_time_slow() -> void:
    is_time_slowed = false
    var game_manager = player.get_node_or_null("/root/GameManager")
    if game_manager:
        game_manager.enemy_time_scale = 1.0
    
    # Cleanup Visual Effect
    # Cleanup Visual Effect
    if is_instance_valid(_filter_rect):
        _filter_rect.queue_free()
    # No layer to free anymore
    # if is_instance_valid(_filter_layer):
    #     _filter_layer.queue_free()
    
    # Cleanup Audio Effect
    _remove_audio_distortion()
        
    # Restore player Z
    player.z_as_relative = true
    player.z_index = 0 # Default
    
    # Remove Speed Boost
    if secrets_of_past_level >= 2:
        _apply_speed_boost(false)

func _perform_special(_direction: Vector2) -> void:
    # Override to prevent "Not Implemented" error
    # Logic is handled via Input in _process, so this is a placeholder
    pass

func _apply_audio_distortion() -> void:
    if _distortion_effect == null:
        _distortion_effect = AudioEffectLowPassFilter.new()
        _distortion_effect.cutoff_hz = 1000.0 # Underwater sound
        _distortion_effect.resonance = 0.5
        
    _music_bus_idx = AudioServer.get_bus_index("Music")
    _sfx_bus_idx = AudioServer.get_bus_index("SFX")
    
    if _music_bus_idx >= 0:
        AudioServer.add_bus_effect(_music_bus_idx, _distortion_effect)
        _distortion_idx_music = AudioServer.get_bus_effect_count(_music_bus_idx) - 1
        
    if _sfx_bus_idx >= 0:
        AudioServer.add_bus_effect(_sfx_bus_idx, _distortion_effect)
        _distortion_idx_sfx = AudioServer.get_bus_effect_count(_sfx_bus_idx) - 1

func _remove_audio_distortion() -> void:
    if _music_bus_idx >= 0 and _distortion_idx_music >= 0:
        # Check if effect is still there (safety)
        if AudioServer.get_bus_effect_count(_music_bus_idx) > _distortion_idx_music:
             AudioServer.remove_bus_effect(_music_bus_idx, _distortion_idx_music)
    
    if _sfx_bus_idx >= 0 and _distortion_idx_sfx >= 0:
        if AudioServer.get_bus_effect_count(_sfx_bus_idx) > _distortion_idx_sfx:
             AudioServer.remove_bus_effect(_sfx_bus_idx, _distortion_idx_sfx)
    
    _distortion_idx_music = -1
    _distortion_idx_sfx = -1


func _create_mono_filter() -> void:
    # Create Fullscreen Effect as Child of Camera (to be covered by bullets but cover world)
    # Find camera
    var camera = player.get_node_or_null("Camera2D")
    if not camera:
        # Fallback to viewport camera if player doesn't have one (unlikely)
        camera = player.get_viewport().get_camera_2d()
        
    if not camera:
        return # Cannot attach
        
    _filter_rect = ColorRect.new()
    _filter_rect.color = Color.WHITE
    # Size matches viewport
    var viewport_size = player.get_viewport_rect().size / camera.zoom
    _filter_rect.size = viewport_size * 2.0 # Oversize to be safe
    _filter_rect.position = - _filter_rect.size / 2.0 # Center on camera
    
    _filter_rect.z_as_relative = false
    _filter_rect.z_index = 50
    _filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    var shader = Shader.new()
    shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap; void fragment() { vec4 bg = texture(screen_texture, SCREEN_UV); float gray = dot(bg.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(gray, gray, gray, bg.a); }"
    
    var mat = ShaderMaterial.new()
    mat.shader = shader
    _filter_rect.material = mat
    
    camera.add_child(_filter_rect)

var _heal_accumulator: float = 0.0

func _apply_active_effects(delta: float) -> void:
    # Talent 1: Heal 25% health per second
    # Secrets level 1+
    if secrets_of_past_level >= 1:
        if player.has_method("heal"):
            var heal_amount = player.max_hp * 0.25 * delta
            _heal_accumulator += heal_amount
            if _heal_accumulator >= 1.0:
                var h_int = int(_heal_accumulator)
                _heal_accumulator -= h_int
                player.heal(h_int)
            
    # Talent 2 (Dust to Dust): DOT to enemies
    if dust_to_dust_level >= 1:
        _apply_dust_damage_tick(delta)

func _apply_speed_boost(enabled: bool) -> void:
    # PlayerCore has a `speed` export property directly
    # Base speed is 320 (registry). +100% = +320.
    var bonus = 320.0
    if "speed" in player:
        if enabled:
            player.speed += bonus
        else:
            player.speed -= bonus

func _apply_dust_damage(delta: float) -> void:
    # 10 / 25 / 34 % per second
    var pct = 0.10
    if dust_to_dust_level >= 2: pct = 0.25
    if dust_to_dust_level >= 3: pct = 0.34
    
    var boss_pct = 0.05
    
    # Iterate all enemies
    var enemies = TargetCache.get_enemies()
    for enemy in enemies:
        if not is_instance_valid(enemy): continue
        if not enemy.has_method("take_damage"): continue
        
        # Calculate damage
        var max_h = 100
        if "max_hp" in enemy: max_h = enemy.max_hp
        
        var damage_pct = pct
        if enemy.is_in_group("boss") or enemy.is_in_group("super_boss") or enemy.name.contains("N01"):
            damage_pct = boss_pct
            
        var damage = max_h * damage_pct * delta
        
        # Apply damage (No crit, source='wells_dust')
        # Ensure at least 1 damage if pct > 0
        var _dmg_int = max(1, int(damage))
        
        # Use take_damage
        # Since this runs every frame, it might spam damage numbers.
        # Ideally we accumulate or use a timer.
        # For 'per second', continuous small hits are fine, or we can use a cooldown.
        # But 'take_damage' usually triggers hit flash/sound. doing this 60 times/sec per enemy is bad.
        # Optimization: Accumulate delta and tick once per 0.5s or 0.2s?
        # User said: "per full second... i.e. 3 seconds... enemies all die"
        # Continuous ticking is implied.
        # Let's try 0.2s ticks.
        pass

var _dust_tick_timer: float = 0.0
func _apply_dust_damage_tick(delta: float) -> void:
    # We call this from physics process, so we can accumulate
    _dust_tick_timer += delta
    if _dust_tick_timer < 0.2:
        return
        
    var dt = _dust_tick_timer # Actual time passed
    _dust_tick_timer = 0.0
    
    # Damage percentages per level based on enemy tier
    # Normal enemies: 10/25/34% max HP/s
    # Tanks/Elites/Shielders/Bombers: 5/10/15% max HP/s
    # Bosses: 1/2/3% max HP/s
    var normal_rates: Array[float] = [0.10, 0.25, 0.34]
    var mid_rates: Array[float] = [0.05, 0.10, 0.15]
    var boss_rates: Array[float] = [0.01, 0.02, 0.03]
    var normal_pct: float = normal_rates[dust_to_dust_level - 1]
    var mid_pct: float = mid_rates[dust_to_dust_level - 1]
    var boss_pct: float = boss_rates[dust_to_dust_level - 1]
    
    var enemies = TargetCache.get_enemies()
    for enemy in enemies:
        if not is_instance_valid(enemy): continue
        if not enemy.has_method("take_damage"): continue
        if enemy.get("hp") <= 0: continue
        
        var max_h = 100
        if "max_hp" in enemy: max_h = enemy.max_hp
        
        # Determine enemy tier for damage calculation
        var damage_pct: float = normal_pct
        
        # Boss tier (lowest damage)
        if enemy.is_in_group("boss") or enemy.is_in_group("super_boss") or enemy.name.contains("N01"):
            damage_pct = boss_pct
        # Mid tier: tanks, elites, shielders, bombers
        elif enemy.is_in_group("tank") or enemy.is_in_group("elite") or enemy.is_in_group("shielder") or enemy.is_in_group("exploder"):
            damage_pct = mid_pct
            
        var damage = max_h * damage_pct * dt
        var dmg_int = int(damage)
        # Probabilistic damage for fractional part
        if randf() < (damage - dmg_int):
            dmg_int += 1
            
        if dmg_int > 0:
             enemy.take_damage(dmg_int, false, Vector2.ZERO, false, "wells_dust")

func attack(direction: Vector2) -> bool:
    # Talent 3: Infinite Ammo during Bullet Time
    if is_time_slowed and secrets_of_past_level >= 3:
        if attack_timer > 0:
            return false
            
        # Allow shooting while reloading if infinite ammo? 
        # Usually yes, or interrupt reload.
        # Let's just interrupt reload if we try to shoot.
        if is_reloading:
            is_reloading = false
            reload_timer = 0.0
            reload_finished.emit() # Force finish or just cancel?
            # Creating a "cancel" might be cleaner but let's just allow shooting.
            
        attack_timer = data.attack_cooldown
        _perform_attack(direction)
        return true
    
    return super.attack(direction)

func _perform_attack(direction: Vector2) -> void:
    # Fire Sniper Round (Standard High Velocity Pierce?)
    # "Uses a Sniper"
    _fire_sniper(direction)


func _on_burst_start() -> void:
    _summon_allies()

func _summon_allies() -> void:
    # Build list of unlocked allies
    var available_types = [3] # MARIAN (Default)
    
    if unlock_crown:
        available_types.append(5) # CROWN
    if unlock_kilo:
        available_types.append(4) # KILO
        
    available_types.shuffle()
    
    var actual_count = available_types.size()
    
    # Summon all unlocked allies with stagger
    for i in range(actual_count):
        var type = available_types[i]
        if i == 0:
            _spawn_ally(type, i, actual_count)
        else:
            # Delay 0.15s per ally
            var timer = player.get_tree().create_timer(0.15 * i)
            timer.timeout.connect(_spawn_ally.bind(type, i, actual_count))

func _spawn_ally(ally_type: int, index: int, total_count: int) -> void:
    # Dynamic load
    var ally_script = load("res://scripts/player/SummonedAlly.gd")
    if not ally_script: return
    
    var ally = ally_script.new()
    ally.ally_type = ally_type
    
    # Standard setup
    ally.owner_player = player
    ally.player_level = player.level if "level" in player else 1
    ally.lifetime = summon_duration
    
    # Position: Spread around player (semicircle or circle)
    # Commander uses: angle = TAU * index / count + PI/4. Offset 80.
    var angle = TAU * float(index) / float(total_count) + PI / 4.0
    var offset = Vector2(cos(angle), sin(angle)) * 80.0
    
    player.get_parent().add_child(ally)
    ally.global_position = player.global_position + offset
    _active_allies.append(weakref(ally))

func apply_talent(talent_id: String) -> void:
    match talent_id:
        "special":
            special_unlocked = true
            reset_special_cooldown()
        "special_upgrade1":
            # Secrets of the Past (Max 3)
            secrets_of_past_level += 1
        "special_upgrade2":
            # Dust to Dust (Max 3)
            dust_to_dust_level += 1
        "burst_upgrade1":
            # A Great King: Unlock Crown
            unlock_crown = true
        "burst_upgrade2":
            # A Fellow Nerd: Unlock Kilo
            unlock_kilo = true

func _fire_sniper(direction: Vector2) -> void:
    # Use Snow White's bullet logic (Piercing Sniper)
    var bullet = ProjectileCache.create_snow_white_bullet()
    if not bullet: return
    
    player.get_parent().add_child(bullet)
    bullet.global_position = player.global_position + direction * 30
    bullet.velocity = direction * bullet_speed
    bullet.rotation = direction.angle()
    bullet.owner_node = player
    bullet.base_damage = player.calc_damage()
    bullet.pierce_all = true # Sniper pierces

    if player.audio_director:
        player.audio_director.play_weapon_fire_sound("sniper")

# ============= TEMPORAL BREACH: Enemy Marian System =============

func _roll_temporal_breach() -> void:
    # Always spawn enemy Marian when fuel empties
    _spawn_enemy_marian()

func _check_enemy_marian_status() -> void:
    # Unblock special if enemy Marian is dead
    if _enemy_marian == null or not is_instance_valid(_enemy_marian):
        _special_blocked = false
        _enemy_marian = null

func _spawn_enemy_marian() -> void:
    # Block special ability
    _special_blocked = true
    
    # Spawn electric spark effect on player (fuel broke)
    _spawn_spark_effect()
    
    # Calculate spawn position FAR from player (400-600 units away)
    var angle = randf() * TAU
    var distance = randf_range(400.0, 600.0)
    var spawn_pos = player.global_position + Vector2(cos(angle), sin(angle)) * distance
    
    # Spawn portal effect at spawn position
    _spawn_temporal_breach_effect(spawn_pos)
    
    # Load dedicated Future Marian scene
    var enemy_scene = load("res://scenes/enemies/FutureMarian.tscn")
    if not enemy_scene:
        _special_blocked = false
        return
    
    var enemy = enemy_scene.instantiate()
    if not enemy:
        _special_blocked = false
        return
    
    # Configure HP based on wave
    var boss_hp := _get_current_boss_hp()
    enemy.max_hp = boss_hp
    
    # Add to scene at spawn position FIRST (so @onready vars work)
    player.get_parent().add_child(enemy)
    enemy.global_position = spawn_pos
    
    # Setup Marian sprite frames AFTER adding to tree
    var marian_tex = load("res://assets/characters/marian/marian-sprite.png")
    if marian_tex and enemy.has_method("setup_sprite"):
        enemy.setup_sprite(marian_tex, 3, 4)
    
    # Store reference
    _enemy_marian = enemy
    
    # Connect death signal
    if enemy.has_signal("died"):
        enemy.died.connect(_on_enemy_marian_died)

func _get_current_boss_hp() -> int:
    # Get wave number from WaveDirector or GameManager
    var wave_num := 1
    var game_manager = player.get_node_or_null("/root/GameManager")
    if game_manager and "current_wave" in game_manager:
        wave_num = game_manager.current_wave
    
    # Boss HP scales with wave: 25 + 50/wave
    var boss_hp := 25 + wave_num * 50
    return boss_hp

func _spawn_temporal_breach_effect(spawn_pos: Vector2) -> void:
    # Create portal visual at spawn position
    var effect = Node2D.new()
    effect.set_script(_get_portal_script())
    player.get_parent().add_child(effect)
    effect.global_position = spawn_pos
    
    # Show screen-wide warning via WaveUI
    var wave_ui = player.get_tree().get_first_node_in_group("wave_ui")
    if wave_ui and wave_ui.has_method("show_event"):
        wave_ui.show_event("boss", {"name": "FUTURE MARIAN"}, 30.0) # 30s elapsed to ensure warning shows
    else:
        # Fallback: try EventBus
        if EventBus and EventBus.has_signal("boss_warning"):
            EventBus.boss_warning.emit("FUTURE MARIAN")

func _spawn_spark_effect() -> void:
    # Create electric spark effect when fuel depletes
    var sparks = Node2D.new()
    sparks.set_script(_get_spark_script())
    player.add_child(sparks)
    sparks.position = Vector2(0, -80) # Near the HUD


func _on_enemy_marian_died() -> void:
    _special_blocked = false
    _enemy_marian = null

func _get_portal_script() -> GDScript:
    var script := preload("res://scripts/characters/effects/visuals/WellsPortal.gd")
    return script

func _get_temporal_glow_script() -> GDScript:
    var script := preload("res://scripts/characters/effects/visuals/WellsTemporalGlow.gd")
    return script

func _get_spark_script() -> GDScript:
    var script := preload("res://scripts/characters/effects/visuals/WellsSpark.gd")
    return script
