extends SceneTree
## Run in a disposable save directory: XDG_DATA_HOME=/tmp/neon-drift-game-tests\
## godot --headless --path . --script res://tests/test_game.gd

var game: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func near(actual: float, expected: float, description: String, tolerance := 0.0001) -> void:
	check(absf(actual - expected) < tolerance, "%s (actual %.6f, expected %.6f)" % [description, actual, expected])

func reset() -> void:
	for action in ["left", "right", "up", "down"]:
		Input.action_release(action)
	game.profile = game.Progression.new()
	game.start_game()
	game.spawn_timer = 1000.0
	game.fire_timer = 1000.0
	game.rng.seed = 12345

func enemy(position: Vector2, kind := 0, hp := 1.0, warning := 0.0) -> Dictionary:
	return {"p": position, "kind": kind, "hp": hp, "max_hp": hp, "age": 0.0, "warning": warning, "phase": 0.0, "flash": 0.0, "dir": Vector2.ZERO}

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._unhandled_input(event)

func _run() -> void:
	if "--checkpoint-check" in OS.get_cmdline_user_args():
		_read_checkpoint_in_fresh_process()
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	check(game.state == "menu", "initial scene shows menu")
	check(game.stars.size() == 75, "ready creates background stars")
	check(InputMap.has_action("dash") and InputMap.has_action("pause_game"), "input actions registered")
	key(KEY_ENTER)
	check(game.state == "sector_map", "Enter opens campaign selection")
	key(KEY_ENTER)
	check(game.state == "playing", "campaign Enter launches game")
	near(game.spawn_timer, 0.6, "start grants spawn delay")
	check(game.health == 5 and game.level == 1 and game.score == 0, "start initializes hull/level/score")
	near(game.invulnerable, 1.5, "start grants initial protection")

	reset()
	var original: Vector2 = game.player
	Input.action_press("right")
	game._tick(0.05)
	near(game.player.x, original.x + 239.0 * 0.05, "right movement speed")
	near(game.player.y, original.y, "right movement holds y")
	check(game.facing == Vector2.RIGHT, "movement updates facing")
	reset()
	original = game.player
	Input.action_press("right")
	Input.action_press("down")
	game._tick(0.05)
	near(game.player.distance_to(original), 239.0 * 0.05, "diagonal movement normalized")
	reset()
	game.player = Vector2(1230, 622)
	Input.action_press("right")
	Input.action_press("down")
	game._tick(0.05)
	check(game.player == Vector2(1230, 622), "arena bounds clamp movement")

	reset()
	check(game.try_dash(), "available dash succeeds")
	near(game.dash_cooldown, 1.55, "level-one dash cooldown")
	check(not game.try_dash(), "cooldown rejects repeated dash")
	original = game.player
	game._tick(0.05)
	near(game.player.x, original.x + 43.0, "dash movement speed")
	near(game.dash_cooldown, 1.5, "dash cooldown counts down")
	game.dash_left = 0.0
	game.dash_cooldown = 0.01
	game._tick(0.02)
	check(game.try_dash(), "dash recharges")
	reset()
	game.level = 20
	game.try_dash()
	near(game.dash_cooldown, 0.85, "high-level dash cooldown floor")
	reset()
	game.state = "paused"
	check(not game.try_dash(), "pause rejects dash")
	reset()
	game.enemies.append(enemy(game.player, 2, 4.0))
	game.try_dash()
	game._move_enemies(0.0)
	check(game.enemies.is_empty() and game.kills == 1, "dash kills armored enemy on contact")
	check(game.score == 45 and game.gems.size() == 1 and game.gems[0].value == 2, "dash awards correct score and armored gem")
	check(game.health == 5, "dash protects hull")

	reset()
	game.enemies.append(enemy(game.player + Vector2(100, 0)))
	game._fire()
	check(game.bolts.size() == 1, "auto-fire launches single bolt at level one")
	check(game.bolts[0].v == Vector2(690, 0), "auto-fire aims at enemy")
	game.bolts[0].p = game.enemies[0].p
	game._move_bolts(0.0)
	check(game.enemies.is_empty() and game.bolts.is_empty(), "bullet kills target and is consumed")
	check(game.kills == 1 and game.score == 10 and game.gems.size() == 1, "bullet kill score and gem")
	reset()
	game.enemies.append(enemy(game.player + Vector2(100, 0), 0, 1.0, 0.7))
	game._fire()
	check(game.bolts.is_empty(), "auto-fire ignores spawn-warning enemy")
	game.bolts.append({"p": game.enemies[0].p, "v": Vector2.ZERO, "life": 1.0})
	game._move_bolts(0.0)
	check(game.enemies.size() == 1 and game.bolts.size() == 1, "warning enemy ignores bullets")
	reset()
	game.enemies.append(enemy(game.player + Vector2(100, 0), 2, 4.0))
	game.bolts.append({"p": game.enemies[0].p, "v": Vector2.ZERO, "life": 1.0})
	game._move_bolts(0.0)
	near(game.enemies[0].hp, 3.0, "armored enemy absorbs weak bolt")
	game.level = 5
	game.bolts.append({"p": game.enemies[0].p, "v": Vector2.ZERO, "life": 1.0})
	game._move_bolts(0.0)
	near(game.enemies[0].hp, 1.0, "level-five bolt deals two damage")
	game.bolts.clear()
	game.level = 3
	game._fire()
	check(game.bolts.size() == 2, "level-three fires two bolts")
	game.bolts.clear()
	game.level = 6
	game._fire()
	check(game.bolts.size() == 3, "level-six fires three bolts")
	game.enemies.clear()
	game._move_bolts(2.0)
	check(game.bolts.is_empty(), "expired bolts removed")

	reset()
	game.invulnerable = 0.0
	game.enemies.append(enemy(game.player))
	game.enemies.append(enemy(game.player))
	game._move_enemies(0.0)
	check(game.health == 4, "simultaneous contact damages only once")
	near(game.invulnerable, 1.3, "damage grants 1.3 seconds invulnerability")
	game._move_enemies(0.0)
	check(game.health == 4, "invulnerability blocks subsequent contact")
	game.invulnerable = 0.01
	game.enemies.clear()
	game._tick(0.02)
	game.enemies.append(enemy(game.player))
	game._move_enemies(0.0)
	check(game.health == 3, "contact damages after invulnerability expires")

	reset()
	game.gems.append({"p": game.player + Vector2(80, 0), "phase": 0.0, "value": 1})
	game._collect_gems(0.1)
	check(game.gems[0].p.distance_to(game.player) < 80, "nearby gem magnet attracts")
	game.gems[0].p = game.player
	game._collect_gems(0.0)
	check(game.energy == 1 and game.score == 5 and game.gems.is_empty(), "gem pickup adds energy and score")
	game.energy = 4
	game.health = 3
	game.gems.append({"p": game.player, "phase": 0.0, "value": 2})
	game._collect_gems(0.0)
	check(game.level == 2 and game.energy == 1 and game.next_level == 9, "level up carries surplus energy")
	check(game.health == 4, "level up heals one hull")
	check(game.state == "upgrade", "level up opens upgrade choice")
	game.choose_upgrade(0)
	game.health = 5
	game.energy = 8
	game.gems.append({"p": game.player, "phase": 0.0, "value": 1})
	game._collect_gems(0.0)
	check(game.health == 5 and game.level == 3, "level heal caps at maximum hull")

	reset()
	game.try_dash()
	game.enemies.append(enemy(game.player + Vector2(100, 0)))
	game._particle(game.player, Vector2.RIGHT, Color.WHITE, 1.0, 1.0)
	key(KEY_ESCAPE)
	check(game.state == "paused", "Escape pauses")
	var old_elapsed: float = game.elapsed
	var old_cooldown: float = game.dash_cooldown
	var old_enemy: Vector2 = game.enemies[0].p
	var old_particle_life: float = game.particles[0].life
	game._process(2.0)
	near(game.elapsed, old_elapsed, "pause freezes elapsed")
	near(game.dash_cooldown, old_cooldown, "pause freezes cooldown")
	check(game.enemies[0].p == old_enemy, "pause freezes enemies")
	near(game.particles[0].life, old_particle_life, "pause freezes effects")
	key(KEY_ESCAPE)
	check(game.state == "playing", "Escape resumes")
	game._on_focus_lost()
	check(game.state == "paused", "focus loss pauses")
	key(KEY_ENTER)
	check(game.state == "playing", "Enter resumes pause")

	reset()
	game.elapsed = 59.99
	game._tick(0.02)
	check(game.wave == 2, "wave two starts at 60 seconds")
	game.elapsed = 239.99
	game._tick(0.02)
	check(game.wave == 5, "wave five starts at 240 seconds")
	game.elapsed = 599.98
	game.boss_spawned = true
	game.boss_defeated = true
	game.health = 3
	game.score = 200
	game._tick(0.01)
	check(game.state == "playing", "no early victory")
	game._tick(0.02)
	check(game.state == "won", "victory at 600 seconds with Warden defeated")
	near(game.elapsed, 600.01, "victory preserves actual survival time")
	check(game.score == 1000, "victory score includes survival and hull bonus")
	game.finish_game(true)
	check(game.score == 1000, "victory bonus cannot repeat")
	key(KEY_R)
	check(game.state == "playing" and game.elapsed == 0.0 and game.score == 0, "R restarts victory")
	check(game.health == 5 and game.level == 1 and game.energy == 0, "retry resets progression")
	check(game.enemies.is_empty() and game.gems.is_empty() and game.bolts.is_empty(), "retry clears prior entities")
	game.health = 1
	game.invulnerable = 0.0
	game.enemies.append(enemy(game.player))
	game._move_enemies(0.0)
	check(game.state == "lost" and game.health == 0, "zero hull loses")
	key(KEY_ENTER)
	check(game.state == "playing" and game.health == 5, "Enter retries loss")
	game.finish_game(false)
	key(KEY_ESCAPE)
	check(game.state == "menu", "Escape from terminal screen returns to menu")
	key(KEY_M)
	check(not game.muted, "M toggles sound")
	game.muted = true

	# Upgrade choices freeze the run and preserve uncollected nearby energy.
	reset()
	game.energy = 4
	game.health = 2
	game.invulnerable = 0.0
	game.dash_cooldown = 0.9
	game.gems.append({"p": game.player, "phase": 0.0, "value": 2})
	game.gems.append({"p": game.player, "phase": 0.0, "value": 2})
	game._collect_gems(0.0)
	check(game.state == "upgrade" and game.gems.size() == 1, "choice stops additional gem pickup")
	check(game.energy == 1 and game.health == 3, "choice preserves surplus and level heal")
	var upgrade_elapsed: float = game.elapsed
	var upgrade_effects: float = game.particles[0].life
	game._process(5.0)
	near(game.elapsed, upgrade_elapsed, "upgrade freezes survival timer")
	near(game.dash_cooldown, 0.9, "upgrade freezes dash cooldown")
	near(game.particles[0].life, upgrade_effects, "upgrade freezes particles")
	check(game.gems.size() == 1, "upgrade freezes collection")
	key(KEY_ESCAPE)
	check(game.state == "upgrade", "Escape cannot discard pending upgrade")
	key(KEY_ENTER)
	check(game.state == "upgrade", "Enter cannot skip pending upgrade")
	check(not game.try_dash(), "upgrade rejects dash")
	game.choose_upgrade(-1)
	game.choose_upgrade(3)
	check(game.state == "upgrade" and game.overdrive == 0 and game.phase_engine == 0 and game.recovery == 0, "invalid upgrade indexes rejected")
	key(KEY_1)
	check(game.state == "playing" and game.overdrive == 1, "one key chooses Overdrive and resumes")
	near(game.invulnerable, 1.0, "upgrade resume grants protection")
	game.choose_upgrade(0)
	check(game.overdrive == 1, "choice cannot be applied twice")
	game.enemies.append(enemy(game.player + Vector2(300, 0)))
	game.fire_timer = 0.0
	game._tick(0.0)
	near(game.fire_timer, 0.48 - 2 * 0.018 - 0.035, "Overdrive increases fire rate")
	reset()
	game.state = "upgrade"
	key(KEY_2)
	check(game.phase_engine == 1 and game.state == "playing", "two key chooses Phase Engine")
	original = game.player
	Input.action_press("right")
	game._tick(0.05)
	near(game.player.x - original.x, 254.0 * 0.05, "Phase Engine increases move speed")
	game.try_dash()
	near(game.dash_cooldown, 1.39, "Phase Engine improves dash cooldown")
	reset()
	game.health = 1
	game.state = "upgrade"
	key(KEY_3)
	check(game.recovery == 1 and game.health == 3 and game.state == "playing", "three key chooses Recovery and heals two")
	game.gems.append({"p": game.player + Vector2(140, 0), "phase": 0.0, "value": 1})
	game._collect_gems(0.05)
	check(game.gems[0].p.distance_to(game.player) < 140, "Recovery extends magnet radius")
	game.health = 4
	game.state = "upgrade"
	game.choose_upgrade(2)
	check(game.health == 5, "Recovery hull capped at five")
	reset()
	check(game.overdrive == 0 and game.phase_engine == 0 and game.recovery == 0, "restart clears every upgrade")
	key(KEY_V)
	check(game.reduced_motion, "V enables reduced motion")
	key(KEY_V)
	check(not game.reduced_motion, "V disables reduced motion")

	# Swept collisions must catch glancing contacts even on a 50 ms frame.
	reset()
	var target := Vector2(700, 374)
	game.enemies.append(enemy(target))
	game.bolts.append({"p": target + Vector2(-17.25, 12), "v": Vector2(690, 0), "life": 1.0})
	game._move_bolts(0.05)
	check(game.enemies.is_empty() and game.kills == 1, "swept bolt hits crossed target at 20 fps")
	reset()
	game.enemies.append(enemy(game.player + Vector2(21.5, 20)))
	game.previous_player = game.player
	game.player += Vector2(43, 0)
	game.try_dash()
	game._move_enemies(0.0)
	check(game.enemies.is_empty() and game.kills == 1, "swept dash hits crossed target at 20 fps")

	# Dasher windup locks its attack lane, then attacks without homing.
	reset()
	game.enemies.append(enemy(game.player - Vector2(300, 0), 1, 2.0))
	game._move_enemies(0.01)
	var dasher: Dictionary = game.enemies[0]
	check(dasher.attack_phase == "seek", "dasher initializes in seek phase")
	dasher.attack_timer = 0.0
	var windup_start: Vector2 = dasher.p
	game._move_enemies(0.01)
	check(dasher.attack_phase == "windup" and dasher.p == windup_start, "dasher stops to telegraph before burst")
	near(dasher.attack_timer, 0.65, "dasher provides 650 ms warning")
	check(dasher.locked_dir == Vector2.RIGHT, "windup locks original player direction")
	game.player += Vector2(0, 200)
	game._move_enemies(0.05)
	check(dasher.locked_dir == Vector2.RIGHT and dasher.p == windup_start, "windup lane stays locked when player moves")
	dasher.attack_timer = 0.0
	game._move_enemies(0.05)
	check(dasher.attack_phase == "burst", "windup transitions to burst")
	near(dasher.p.x - windup_start.x, 21.5, "burst moves at telegraphed speed")
	near(dasher.p.y, windup_start.y, "burst does not home toward moved player")
	dasher.attack_timer = 0.0
	game._move_enemies(0.05)
	check(dasher.attack_phase == "seek", "burst returns to recovery seek phase")
	near(dasher.attack_timer, 2.1, "dasher has 2.1 second recovery")
	reset()
	game.spawn_timer = 0.0
	for i in range(95):
		game.enemies.append(enemy(Vector2(60, 150), 0, 1.0, 999.0))
	game._tick(0.01)
	check(game.enemies.size() == 95, "spawn limit prevents runaway enemy growth")

	_test_pilot_growth()
	_test_save_resume()
	_test_boss_and_endless()
	_test_bad_checkpoint_handling()
	_test_salvage_cap()
	_test_full_expedition()
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)

func _test_pilot_growth() -> void:
	reset()
	game.profile.credits = 1000
	game.profile.total_kills = 300
	check(game.profile.buy_upgrade("hull_rank"), "hangar hull purchase succeeds")
	check(game.profile.buy_upgrade("damage_rank"), "hangar reactor purchase succeeds")
	check(game.profile.buy_upgrade("magnet_rank"), "hangar magnet purchase succeeds")
	check(game.profile.credits == 955, "three rank-one upgrades cost 45 cores")
	check(game.max_health == 5 and game.damage_bonus == 0.0 and game.magnet_bonus == 0.0, "hangar purchases do not alter active expedition")
	game._cycle_weapon()
	check(game.profile.weapon == 1 and game.run_weapon == 0, "loadout change applies only to next expedition")
	game.start_game()
	check(game.health == 6 and game.max_health == 6, "new run applies permanent hull")
	near(game.damage_bonus, 0.2, "new run applies permanent reactor")
	near(game.magnet_bonus, 20.0, "new run applies permanent salvage range")
	check(game.run_weapon == 1, "new run applies selected Fan loadout")
	game.enemies.append(enemy(game.player + Vector2(100, 0), 2, 100.0))
	game._fire()
	check(game.bolts.size() == 3, "Fan adds two projectiles at level one")
	near(game._bolt_damage(), 1.2, "reactor increases projectile damage")
	game._cycle_weapon()
	check(game.profile.weapon == 2, "unlocked Lance selectable")
	game.start_game()
	near(game._bolt_damage(), 2.4, "Lance doubles reactor-boosted damage")
	game.overdrive = 3
	game.level = 5
	near(game._bolt_damage(), 5.9, "Lance doubles level and Overdrive damage bonuses")
	game.enemies.append(enemy(game.player + Vector2(100, 0), 2, 100.0))
	game._fire()
	check(game.bolts.size() == 3, "every three Overdrive ranks adds one projectile")
	game.level = 100
	game.overdrive = 100
	game.bolts.clear()
	game._fire()
	check(game.bolts.size() == 7, "projectile growth caps at seven")
	game.fire_timer = 0.0
	game.spawn_timer = 1000.0
	game._tick(0.0)
	near(game.fire_timer, 0.12, "fire rate has safe 120 ms minimum interval")

	reset()
	check(game.profile.weapon_unlocked(0) and not game.profile.weapon_unlocked(1) and not game.profile.weapon_unlocked(2), "fresh pilot has only Pulse")
	game._cycle_weapon()
	check(game.profile.weapon == 0, "cycling skips locked loadouts")
	for i in range(4):
		game.enemies.append(enemy(game.player + Vector2(300, 0)))
		game._destroy_enemy(0)
	check(game.profile.credits == 0 and game.earned_credits == 0 and game.profile.total_kills == 4, "first four kills accumulate lifetime count without core payout")
	game.enemies.append(enemy(game.player + Vector2(300, 0)))
	game._destroy_enemy(0)
	check(game.profile.credits == 1 and game.earned_credits == 1 and game.kills == 5, "fifth elimination earns permanent core")
	game.profile.total_kills = 99
	game.enemies.append(enemy(game.player + Vector2(300, 0)))
	game._destroy_enemy(0)
	check(game.profile.weapon_unlocked(1), "100 lifetime kills unlock Fan")
	game.profile.total_kills = 299
	game.enemies.append(enemy(game.player + Vector2(300, 0)))
	game._destroy_enemy(0)
	check(game.profile.weapon_unlocked(2), "300 lifetime kills unlock Lance")
	game.health = 1
	game.invulnerable = 0.0
	game._damage_player()
	check(game.state == "lost" and game.profile.run.is_empty(), "death clears suspended expedition")
	var persisted = game.Progression.new()
	persisted.load_data()
	check(persisted.credits == 1 and persisted.total_kills == 300 and persisted.weapon_unlocked(2), "death preserves earned cores and lifetime unlocks on disk")
	var permanent: int = game.profile.credits
	game.finish_game(false)
	check(game.profile.credits == permanent, "terminal finish cannot pay rewards twice")
	game.start_game()
	check(game.profile.credits == permanent and game.profile.total_kills == 300, "new expedition keeps pilot progress")
	check(game.earned_credits == 0 and game.kills == 0 and game.level == 1, "new expedition resets run-only growth")

	reset()
	game.level = 7
	game.pulse_timer = 0.0
	game.enemies.append(enemy(game.player + Vector2(120, 0), 2, 3.0))
	game._tick(0.0)
	check(game.enemies.size() == 1, "Nova stays locked below level eight")
	game.level = 8
	game._tick(0.0)
	check(game.enemies.is_empty() and game.kills == 1, "level eight activates damaging Nova")
	near(game.pulse_timer, 6.0, "base Nova recharge is six seconds")
	game.recovery = 2
	game.pulse_timer = 0.0
	game.enemies.append(enemy(game.player + Vector2(190, 0), 2, 5.0))
	game.enemies.append(enemy(game.player + Vector2(190, 20), 2, 5.0, 0.5))
	game._tick(0.0)
	check(game.enemies.size() == 1 and game.enemies[0].warning > 0, "Recovery increases Nova range/damage and Nova respects spawn warning")
	near(game.pulse_timer, 5.5, "Recovery reduces Nova recharge")
	game.recovery = 100
	game.pulse_timer = 0.0
	game._tick(0.0)
	near(game.pulse_timer, 2.5, "Nova interval stops at 2.5 seconds")

func _test_save_resume() -> void:
	reset()
	game.profile.credits = 81
	game.profile.total_kills = 357
	game.profile.hull_rank = 2
	game.profile.damage_rank = 3
	game.profile.magnet_rank = 4
	game.profile.weapon = 2
	game.start_game()
	game.elapsed = 271.25
	game.player = Vector2(431, 285)
	game.facing = Vector2.UP
	game.health = 4
	game.score = 1234
	game.kills = 73
	game.level = 8
	game.energy = 4
	game.next_level = 21
	game.overdrive = 3
	game.phase_engine = 2
	game.recovery = 1
	game.dash_left = 0.07
	game.dash_cooldown = 0.48
	game.invulnerable = 0.1
	game.fire_timer = 0.14
	game.spawn_timer = 0.34
	game.wave = 5
	game.earned_credits = 14
	game.pulse_timer = 2.7
	game.enemies.append(enemy(Vector2(650, 300), 2, 6.4))
	var dasher := enemy(Vector2(850, 400), 1, 3.2)
	dasher.merge({"attack_phase": "windup", "attack_timer": 0.5, "locked_dir": Vector2.LEFT})
	game.enemies.append(dasher)
	game.gems.append({"p": Vector2(470, 285), "phase": 0.75, "value": 2})
	game.bolts.append({"p": Vector2(450, 290), "v": Vector2(690, 0), "life": 0.65})
	game._on_focus_lost()
	check(game.state == "paused" and game.profile.run.state == "paused", "focus loss saves suspended run")
	check(game.save_notice.is_empty(), "valid populated snapshot saves without warning")
	var expected: Dictionary = game.profile.run.duplicate(true)
	var child_output: Array = []
	var child_status := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/test_game.gd", "--", "--checkpoint-check"]), child_output, true)
	check(child_status == 0, "separate Godot process reloads full populated checkpoint")
	for output in child_output:
		print(str(output).strip_edges())
	game.enemies[0].hp = 1.0
	game.gems[0].value = 1
	check(expected.enemies[0].hp == 6.4 and game.profile.run.enemies[0].hp == 6.4, "saved snapshot deeply isolates live enemy mutations")
	check(game.profile.run.gems[0].value == 2, "saved snapshot deeply isolates gem mutations")

	# A new scene and profile load exercises disk deserialization rather than a
	# same-object resume, including typed entity arrays and native Vector2 values.
	var restored = load("res://main.tscn").instantiate()
	root.add_child(restored)
	restored.set_process(false)
	restored.muted = true
	check(restored.state == "menu" and not restored.profile.run.is_empty(), "fresh scene discovers suspended expedition")
	check(restored.profile.credits == 81 and restored.profile.total_kills == 357, "fresh scene loads persistent pilot counters")
	restored._launch()
	check(restored.state == "playing", "continue launches restored expedition")
	for field in game.RUN_FIELDS:
		if field == "invulnerable":
			continue
		check(restored.get(field) == expected[field], "resume round-trips field: " + field)
	near(restored.invulnerable, 1.5, "resume grants 1.5s safety protection")
	check(restored.previous_player == restored.player, "resume resets swept collision origin")
	check(restored.particles.is_empty() and restored.rings.is_empty() and restored.trails.is_empty(), "resume clears transient effects")
	restored.enemies[0].hp = 5.0
	check(restored.profile.run.enemies[0].hp == 6.4, "resumed live entities do not alias saved snapshot")
	restored.free()

	game.profile.run = expected.duplicate(true)
	game.continue_run()
	game.state = "upgrade"
	game.save_run()
	var pending_profile = game.Progression.new()
	pending_profile.load_data()
	check(pending_profile.run.state == "upgrade", "pending upgrade state survives disk save")
	game.profile = pending_profile
	game.state = "menu"
	game._launch()
	check(game.state == "upgrade" and game.overdrive == 3, "continue cannot discard pending level-up choice")
	game.choose_upgrade(1)
	check(game.state == "playing" and game.phase_engine == 3, "restored pending upgrade can be chosen once")
	pending_profile = game.Progression.new()
	pending_profile.load_data()
	check(pending_profile.run.phase_engine == 3 and pending_profile.run.state == "paused", "chosen upgrade immediately persists")

	game._go_home()
	check(game.state == "menu" and not game.profile.run.is_empty(), "save and title keeps current expedition")
	var held_elapsed: float = game.elapsed
	key(KEY_N)
	check(game.state == "sector_map", "new run opens sector selection")
	key(KEY_ENTER)
	check(game.state == "confirm_new", "new-run shortcut asks before replacing saved expedition")
	key(KEY_ESCAPE)
	check(game.state == "menu" and game.profile.run.elapsed == held_elapsed, "cancel new run retains saved expedition")
	key(KEY_ENTER)
	check(game.state == "playing" and game.elapsed == held_elapsed, "title Enter continues without resetting build")
	game._go_home()
	key(KEY_N)
	key(KEY_ENTER)
	key(KEY_ENTER)
	check(game.state == "playing" and game.elapsed == 0.0 and game.level == 1, "confirmed new run resets expedition")
	check(game.profile.credits == 81 and game.profile.hull_rank == 2 and game.run_weapon == 2, "confirmed new run preserves pilot and selected weapon")
	check(game.profile.run.elapsed == 0.0 and game.profile.run.enemies.is_empty(), "confirmed replacement immediately overwrites suspended run")

	reset()
	game.elapsed = 12.0
	game.autosave_timer = 0.01
	game._tick(0.02)
	var autosaved = game.Progression.new()
	autosaved.load_data()
	near(autosaved.run.elapsed, 12.02, "five-second autosave writes current expedition time")
	near(game.autosave_timer, 5.0, "autosave timer resets to five seconds")

func _test_boss_and_endless() -> void:
	reset()
	game.elapsed = 539.98
	game._tick(0.01)
	check(not game.boss_spawned, "Warden does not spawn before nine minutes")
	game._tick(0.02)
	check(game.boss_spawned and game.enemies.size() == 1 and game.enemies[0].kind == 3, "Warden spawns at nine minutes")
	var boss: Dictionary = game.enemies[0]
	near(boss.max_hp, 480.0, "Warden has 480 starting hull")
	check(boss.warning > 1.9, "Warden provides two-second spawn warning")
	game._tick(0.01)
	check(game.enemies.size() == 1, "Warden spawns only once")
	boss.warning = 0.0
	boss.attack_timer = 0.0
	game._move_enemies(0.01)
	check(game.enemies.size() == 5, "Warden summons four reinforcements")
	boss.p = game.player
	game.previous_player = game.player
	game.try_dash()
	game._move_enemies(0.0)
	near(boss.hp, 468.0, "dash damages Warden instead of instantly destroying it")
	game._move_enemies(0.0)
	near(boss.hp, 468.0, "single dash cannot damage Warden repeatedly")
	game.dash_left = 0.0
	game.enemies.clear()
	game.boss_spawned = false
	game.boss_defeated = false
	game._spawn_boss()
	boss = game.enemies[0]
	boss.warning = 0.0
	game.elapsed = 600.0
	game._tick(0.01)
	check(game.state == "playing" and game.elapsed > 600.0, "600 seconds alone cannot win while Warden lives")
	game._destroy_enemy(0)
	check(game.boss_defeated and game.profile.credits == 50 and game.earned_credits == 50, "Warden elimination grants 50 permanent cores")
	game.health = 3
	var pre_victory_score: int = game.score
	game._tick(0.01)
	check(game.state == "won", "Warden defeat after ten minutes completes expedition")
	check(game.profile.credits == 100 and game.earned_credits == 100, "successful extraction grants additional 50 cores")
	check(game.score == pre_victory_score + 800 and game.profile.run.is_empty(), "victory awards score and clears suspended run")
	var reward: int = game.profile.credits
	game.finish_game(true)
	check(game.profile.credits == reward, "repeated victory cannot duplicate core reward")
	game.level = 12
	game.overdrive = 4
	game.phase_engine = 3
	game.recovery = 2
	key(KEY_E)
	check(game.state == "playing" and game.endless and game.health == game.max_health, "E continues victory into Endless and repairs hull")
	check(game.level == 12 and game.overdrive == 4 and game.phase_engine == 3 and game.recovery == 2, "Endless retains completed expedition build")
	check(game.profile.run.endless and game.profile.run.boss_defeated, "Endless transition immediately saves run")
	game._tick(0.05)
	check(game.state == "playing" and game.elapsed > 600.0, "Endless passes extraction threshold without re-winning")
	check(game.profile.credits == reward, "Endless does not duplicate extraction payout")
	var endless_profile = game.Progression.new()
	game.save_run()
	endless_profile.load_data()
	game.profile = endless_profile
	game.state = "menu"
	game._launch()
	check(game.endless and game.state == "playing" and game.level == 12, "Endless build can resume from disk")
	game.elapsed = 3601.0
	game.wave = 61
	game.save_run()
	endless_profile = game.Progression.new()
	endless_profile.load_data()
	check(not endless_profile.run.is_empty() and endless_profile.run.elapsed == 3601.0, "Endless runs beyond one hour remain resumable")
	check(game.save_notice.is_empty(), "one-hour Endless checkpoint saves without warning")
	game.health = 1
	game._damage_player()
	check(game.state == "lost" and game.profile.run.is_empty(), "Endless death clears run")
	check(game.profile.credits == reward, "Endless death keeps extraction and boss rewards")

func _test_bad_checkpoint_handling() -> void:
	reset()
	game.enemies.append(enemy(Vector2(300, 300)))
	game.save_run()
	var valid: Dictionary = game.profile.run.duplicate(true)
	var original_player: Vector2 = game.player
	for field in game.RUN_FIELDS:
		game.profile.run = valid.duplicate(true)
		game.profile.run.erase(field)
		game.state = "menu"
		game.save_notice = ""
		game.continue_run()
		check(game.state == "menu" and not game.save_notice.is_empty() and game.player == original_player, "resume rejects missing field without partial restore: " + field)
	game.profile.run = valid.duplicate(true)
	game.profile.run.enemies[0].p = "corrupted"
	game.state = "menu"
	game.save_notice = ""
	game.continue_run()
	check(game.state == "menu" and not game.save_notice.is_empty(), "resume rejects corrupt entity type before applying state")
	game.profile.run = valid.duplicate(true)
	game.profile.run.health = "corrupted"
	game.save_notice = ""
	game.continue_run()
	check(game.state == "menu" and not game.save_notice.is_empty(), "resume rejects corrupt scalar type before applying state")
	game.profile.run = valid.duplicate(true)
	game.profile.run.state = "lost"
	game.save_notice = ""
	game.continue_run()
	check(game.state == "menu" and not game.save_notice.is_empty(), "resume rejects terminal state masquerading as checkpoint")
	game.profile.run = valid.duplicate(true)
	game.continue_run()
	check(game.state == "playing", "valid checkpoint remains resumable after rejecting corruption")
	game.profile._write_blocked = true
	game.save_run()
	check(not game.save_notice.is_empty(), "checkpoint write failure is visible to player")
	game.profile.total_kills = 300
	game.profile.weapon = 0
	game._cycle_weapon()
	check(game.profile.weapon == 0 and not game.save_notice.is_empty(), "failed loadout save rolls back selection and shows warning")
	game.profile.credits = 100
	game._buy(0)
	check(game.profile.credits == 100 and game.profile.hull_rank == 0 and not game.save_notice.is_empty(), "failed upgrade purchase rolls back charge and rank and shows warning")
	game.health = 1
	game._damage_player()
	check(game.state == "lost" and not game.save_notice.is_empty(), "terminal save failure is visible after death")

func _test_salvage_cap() -> void:
	reset()
	for index in range(512):
		game.gems.append({"p": Vector2(80, 140), "phase": 0.0, "value": 1})
	game.enemies.append(enemy(Vector2(90, 150), 2, 4.0))
	game._destroy_enemy(0)
	check(game.gems.size() == 512, "salvage cap prevents unbounded Endless entity growth")
	var energy_sum := 0
	for gem in game.gems:
		energy_sum += int(gem.value)
	check(energy_sum == 514, "salvage cap merges armored enemy experience without losing it")
	game.enemies.append(enemy(Vector2(90, 150)))
	game._destroy_enemy(0)
	energy_sum = 0
	for gem in game.gems:
		energy_sum += int(gem.value)
	check(game.gems.size() == 512 and energy_sum == 515, "salvage cap preserves subsequent normal drops")
	game.save_run()
	var capped = game.Progression.new()
	capped.load_data()
	check(capped.run.gems.size() == 512 and game.save_notice.is_empty(), "maximum salvage field remains persistable")

func _test_full_expedition() -> void:
	# 36,001 real 60 Hz frames, executed without waiting for wall time. The
	# stationary test pilot has test-only invulnerability, so this establishes
	# runtime/progression integration, NOT human playability or game balance.
	reset()
	game.spawn_timer = 0.0
	game.fire_timer = 0.0
	var started := Time.get_ticks_usec()
	var max_enemies := 0
	var max_particles := 0
	var max_gems := 0
	var frames := 0
	var saw_boss := false
	var chosen := 0
	for frame in range(36001):
		if game.state == "upgrade":
			game.choose_upgrade((game.level - 2) % 3)
			chosen += 1
		if game.state != "playing":
			break
		game.invulnerable = 999.0
		game._process(1.0 / 60.0)
		frames += 1
		max_enemies = maxi(max_enemies, game.enemies.size())
		max_particles = maxi(max_particles, game.particles.size())
		max_gems = maxi(max_gems, game.gems.size())
		saw_boss = saw_boss or game.boss_spawned
	var duration_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(frames >= 36000, "full expedition executes at least 36,000 real 60 Hz frames")
	check(game.state == "won", "full 600-second accelerated simulation reaches victory")
	check(saw_boss and game.boss_defeated, "full simulation spawns and defeats real Warden")
	check(chosen > 0 and game.level >= 8, "full simulation earns upgrade choices and unlocks Nova")
	check(max_enemies <= 96, "full run enemy counts bounded including boss")
	check(max_particles < 1000, "full run effect counts bounded")
	check(max_gems <= 512, "full run gem count remains within salvage cap")
	check(game.save_notice.is_empty(), "full run autosaves remain valid")
	var saved_record := ConfigFile.new()
	check(saved_record.load("user://record.cfg") == OK, "record is saved successfully")
	check(saved_record.get_value("record", "best", 0) == game.best_score, "saved record matches best score")
	var completed = game.Progression.new()
	completed.load_data()
	check(completed.run.is_empty() and completed.credits == game.profile.credits, "completed simulation persists permanent progress and clears run")
	print("SIMULATION: %d frames / %.2f simulated seconds in %.2f ms; level=%d kills=%d upgrades=%d cores=%d max_enemies=%d max_particles=%d max_gems=%d boss_defeated=%s state=%s" % [frames,game.elapsed,duration_ms,game.level,game.kills,chosen,game.profile.credits,max_enemies,max_particles,max_gems,game.boss_defeated,game.state])

func _read_checkpoint_in_fresh_process() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	check(not game.profile.run.is_empty(), "fresh process finds checkpoint")
	game._launch()
	check(game.state == "playing", "fresh process resumes playing state")
	near(game.elapsed, 271.25, "fresh process restores elapsed")
	check(game.player == Vector2(431, 285) and game.facing == Vector2.UP, "fresh process restores position/facing")
	check(game.health == 4 and game.max_health == 7, "fresh process restores hull")
	check(game.score == 1234 and game.kills == 73 and game.level == 8, "fresh process restores score/kills/level")
	check(game.energy == 4 and game.next_level == 21, "fresh process restores pending experience")
	check(game.overdrive == 3 and game.phase_engine == 2 and game.recovery == 1, "fresh process restores entire build")
	near(game.dash_cooldown, 0.48, "fresh process restores dash cooldown")
	near(game.dash_left, 0.07, "fresh process restores active dash")
	near(game.fire_timer, 0.14, "fresh process restores weapon clock")
	near(game.spawn_timer, 0.34, "fresh process restores spawn clock")
	near(game.pulse_timer, 2.7, "fresh process restores Nova clock")
	near(game.damage_bonus, 0.6, "fresh process restores reactor strength")
	near(game.magnet_bonus, 80.0, "fresh process restores magnet strength")
	check(game.run_weapon == 2 and game.earned_credits == 14, "fresh process restores loadout and earned cores")
	check(game.enemies.size() == 2 and game.enemies[0].p == Vector2(650, 300), "fresh process restores enemy positions")
	check(game.enemies[1].attack_phase == "windup" and game.enemies[1].locked_dir == Vector2.LEFT, "fresh process restores dasher attack lane")
	check(game.bolts.size() == 1 and game.bolts[0].v == Vector2(690, 0), "fresh process restores projectiles")
	check(game.gems.size() == 1 and game.gems[0].value == 2, "fresh process restores salvage")
	check(game.profile.credits == 81 and game.profile.total_kills == 357, "fresh process restores permanent counters")
	check(game.profile.hull_rank == 2 and game.profile.damage_rank == 3 and game.profile.magnet_rank == 4, "fresh process restores all permanent ranks")
	check(game.profile.weapon == 2 and game.profile.weapon_unlocked(2), "fresh process restores selected unlocked weapon")
	game._process(1.0 / 60.0)
	check(game.state == "playing" and game.elapsed > 271.25, "fresh process can advance restored state without script errors")
	print("FRESH-PROCESS RESULT: %d checks, %d failures" % [checks, failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)
