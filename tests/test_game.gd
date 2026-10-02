extends SceneTree

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
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	check(game.state == "menu", "initial scene shows menu")
	check(game.stars.size() == 75, "ready creates background stars")
	check(InputMap.has_action("dash") and InputMap.has_action("pause_game"), "input actions registered")
	key(KEY_ENTER)
	check(game.state == "playing", "Enter launches game")
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
	game.elapsed = 14.99
	game._tick(0.02)
	check(game.wave == 2, "wave two starts at 15 seconds")
	game.elapsed = 59.99
	game._tick(0.02)
	check(game.wave == 5, "wave five starts at 60 seconds")
	game.elapsed = 74.98
	game.health = 3
	game.score = 200
	game._tick(0.01)
	check(game.state == "playing", "no early victory")
	game._tick(0.02)
	check(game.state == "won", "victory at 75 seconds")
	near(game.elapsed, 75.0, "victory elapsed capped at 75")
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
	near(game.fire_timer, 0.48 - 2 * 0.037 - 0.04, "Overdrive increases fire rate")
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

	# Deterministic full-duration stress run using real update functions.
	reset()
	game.spawn_timer = 0.0
	game.fire_timer = 0.0
	var started := Time.get_ticks_usec()
	var max_enemies := 0
	var max_particles := 0
	for frame in range(4501):
		if game.state == "upgrade":
			game.choose_upgrade((game.level - 2) % 3)
		if game.state != "playing":
			break
		# This protection is test-only; production gameplay contains no shortcut.
		game.invulnerable = 999.0
		game._process(1.0 / 60.0)
		max_enemies = maxi(max_enemies, game.enemies.size())
		max_particles = maxi(max_particles, game.particles.size())
	var duration_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(game.state == "won", "full 75-second simulation reaches victory")
	check(game.enemies.size() < 220, "full run entity counts bounded")
	check(game.particles.size() < 1000, "full run effect counts bounded")
	var saved_record := ConfigFile.new()
	check(saved_record.load("user://record.cfg") == OK, "record is saved successfully")
	check(saved_record.get_value("record", "best", 0) == game.best_score, "saved record matches best score")
	print("SIMULATION: 4501 frames in %.2f ms; max_enemies=%d max_particles=%d" % [duration_ms, max_enemies, max_particles])
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)
