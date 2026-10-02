extends SceneTree
## Visual-state regression tests; these do not judge rendered aesthetics.
## Run only with disposable saves:
## NEON_DRIFT_TEST_SAVE=1 XDG_DATA_HOME=$(mktemp -d /tmp/neon-drift-visuals.XXXXXX) \
## godot --headless --path . --script res://tests/test_visuals.gd

const EXPECTED_RUN_FIELDS := [
	"elapsed", "player", "facing", "health", "max_health", "score", "kills", "level",
	"energy", "next_level", "dash_left", "dash_cooldown", "invulnerable", "fire_timer",
	"spawn_timer", "wave", "overdrive", "phase_engine", "recovery", "damage_bonus",
	"magnet_bonus", "run_weapon", "earned_credits", "boss_spawned", "boss_defeated",
	"endless", "pulse_timer", "enemies", "bolts", "gems"
]

var game: Node
var checks := 0
var failures: Array[String] = []
var normal_stress_snapshot: Dictionary = {}


func _initialize() -> void:
	if OS.get_environment("NEON_DRIFT_TEST_SAVE") != "1":
		printerr("Set NEON_DRIFT_TEST_SAVE=1 and use a disposable XDG_DATA_HOME to run visual tests.")
		quit(2)
		return
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func near(actual: float, expected: float, description: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (actual %.6f, expected %.6f)" % [description, actual, expected])


func reset(calm := false) -> void:
	for action in ["left", "right", "up", "down"]:
		Input.action_release(action)
	game.profile = game.Progression.new()
	game.reduced_motion = calm
	game.start_game()
	game.spawn_timer = 1000.0
	game.fire_timer = 1000.0
	game.rng.seed = 314159
	game.particles.clear()
	game.rings.clear()
	game.trails.clear()


func run_snapshot() -> Dictionary:
	var snapshot := {"state": game.state}
	for field in EXPECTED_RUN_FIELDS:
		snapshot[field] = game.get(field)
	return snapshot.duplicate(true)


func effect_snapshot() -> Dictionary:
	return {"particles": game.particles.duplicate(true), "rings": game.rings.duplicate(true),
		"trails": game.trails.duplicate(true), "shake": game.shake,
		"screen_flash": game.screen_flash, "toast_timer": game.toast_timer,
		"boss_cinematic": game.boss_cinematic}


func enemy(position: Vector2, kind := 0, hp := 1.0) -> Dictionary:
	return {"p": position, "kind": kind, "hp": hp, "max_hp": hp, "age": 0.0,
		"warning": 0.0, "phase": 0.0, "flash": 0.0, "dir": Vector2.ZERO}


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
	_test_contract_and_tiers()
	_test_effect_bounds()
	_test_calm_toggle_and_rng()
	_test_effect_lifecycle()
	_test_pause_and_upgrade()
	_test_save_compatibility()
	_test_mechanics()
	_test_live_effect_stress(false)
	_test_live_effect_stress(true)
	print("VISUAL REGRESSION RESULT: %d checks, %d failures" % [checks, failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)


func _test_contract_and_tiers() -> void:
	reset()
	check(game.PARTICLE_LIMIT == 720, "normal particle budget stays at 720")
	check(game.RING_LIMIT == 32, "ring budget stays at 32")
	check(game.TRAIL_LIMIT == 40, "trail budget stays at 40")
	check(game.RUN_FIELDS == EXPECTED_RUN_FIELDS, "visual upgrade preserves the exact existing save-field contract")
	for fixture in [[-1, 0], [0, 0], [1, 0], [4, 0], [5, 1], [9, 1], [10, 2], [14, 2], [15, 3], [20, 3], [10000, 3]]:
		game.level = fixture[0]
		var before := run_snapshot()
		var rng_before: int = game.rng.state
		check(game._ship_tier() == fixture[1], "cosmetic tier at level %d" % fixture[0])
		check(run_snapshot() == before and game.rng.state == rng_before, "tier lookup cannot mutate mechanics at level %d" % fixture[0])


func _test_effect_bounds() -> void:
	for calm in [false, true]:
		reset(calm)
		var limit := 120 if calm else 720
		for i in range(1500):
			game._particle(Vector2(640, 374), Vector2(10, 0), Color.WHITE, 1.0, 2.0)
		check(game.particles.size() > 0 and game.particles.size() <= limit, "direct particle creation bounded with calm=%s" % calm)
		for i in range(100):
			game._burst(game.player, Color.WHITE, 70, 200.0)
		check(game.particles.size() <= limit, "repeated bursts respect particle budget with calm=%s" % calm)
		for i in range(100):
			game._ring(game.player, Color.WHITE, 50.0, 1.0)
		check(game.rings.size() > 0 and game.rings.size() <= 32, "repeated rings respect budget with calm=%s" % calm)
		game.dash_left = 0.17
		for i in range(100):
			game._tick(0.0)
		check(game.trails.size() <= 40, "repeated dash updates respect trail budget with calm=%s" % calm)
		if not calm:
			check(not game.trails.is_empty(), "normal dash produces visible afterimages")
		for particle in game.particles:
			check(particle.life > 0 and particle.max > 0 and particle.p.is_finite() and particle.v.is_finite(), "retained particle has finite geometry and positive lifetime")
		game._tick_effects(2.0)
		check(game.particles.is_empty() and game.rings.is_empty() and game.trails.is_empty(), "all bounded effects expire with calm=%s" % calm)


func _test_calm_toggle_and_rng() -> void:
	reset()
	for i in range(800):
		game._particle(game.player, Vector2.RIGHT, Color.WHITE, 1.0, 2.0)
	check(game.particles.size() == 720, "normal effect load can fill the advertised budget")
	var mechanics_before := run_snapshot()
	var rng_before: int = game.rng.state
	key(KEY_V)
	check(game.reduced_motion and game.particles.size() == 120, "V immediately trims an existing full particle load to calm budget")
	check(run_snapshot() == mechanics_before and game.rng.state == rng_before, "calm toggle leaves gameplay and its random stream untouched")
	game._burst(game.player, Color.WHITE, 500, 100.0)
	check(game.particles.size() == 120, "a full calm particle pool cannot grow on burst")
	check(game.rng.state == rng_before, "cosmetic burst randomness cannot consume gameplay RNG")
	key(KEY_V)
	check(not game.reduced_motion and game.particles.size() == 120, "returning to FX keeps live effects without refilling or duplicating them")
	game._burst(game.player, Color.WHITE, 500, 100.0)
	check(game.particles.size() == 620 and game.rng.state == rng_before, "FX can refill normal capacity without shifting gameplay RNG")
	check(run_snapshot() == mechanics_before, "all cosmetic generation leaves gameplay snapshot unchanged")


func _test_effect_lifecycle() -> void:
	reset()
	game._particle(Vector2(100, 150), Vector2(20, -10), Color.WHITE, 1.0, 3.0)
	game._ring(Vector2(100, 150), Color.WHITE, 50.0, 1.0)
	game.dash_left = 0.17
	game._tick(0.0)
	var mechanics_before := run_snapshot()
	game._tick_effects(0.1)
	near(game.particles[0].life, 0.9, "particles age by effect delta")
	check(game.particles[0].p == Vector2(102, 149), "particles integrate velocity without changing arena entities")
	near(game.rings[0].life, 0.9, "rings age by effect delta")
	check(run_snapshot() == mechanics_before, "effect ticking leaves every saved gameplay field unchanged")
	game._tick_effects(2.0)
	check(game.particles.is_empty() and game.rings.is_empty() and game.trails.is_empty(), "effect cleanup removes expired items")
	game.start_game()
	check(game.particles.is_empty() and game.trails.is_empty(), "new expedition clears previous particles and trails")
	check(game.rings.size() <= 1, "new expedition keeps at most its launch ring")


func _test_pause_and_upgrade() -> void:
	for calm in [false, true]:
		for frozen_state in ["paused", "upgrade"]:
			reset(calm)
			game._particle(game.player, Vector2.RIGHT * 50, Color.WHITE, 1.0, 2.0)
			game._ring(game.player, Color.WHITE, 50.0, 1.0)
			game.try_dash()
			game._tick(0.01)
			game.shake = 4.0
			game.screen_flash = 0.2
			game.boss_cinematic = 2.0
			game.state = frozen_state
			var mechanics_before := run_snapshot()
			var effects_before := effect_snapshot()
			game._process(3.0)
			check(run_snapshot() == mechanics_before, "%s freezes all gameplay fields with calm=%s" % [frozen_state, calm])
			check(effect_snapshot() == effects_before, "%s freezes effect collections, flash, shake, and toast with calm=%s" % [frozen_state, calm])
			check(not game.try_dash(), "%s cannot start a dash with calm=%s" % [frozen_state, calm])
			game.state = "playing"
			game._process(0.05)
			check(game.elapsed > mechanics_before.elapsed, "resuming %s advances gameplay with calm=%s" % [frozen_state, calm])
			check(game.particles[0].life < effects_before.particles[0].life, "resuming %s advances existing effects with calm=%s" % [frozen_state, calm])
			near(game.boss_cinematic, 1.95, "resuming %s advances boss cinematic with calm=%s" % [frozen_state, calm])


func _test_save_compatibility() -> void:
	reset()
	game.level = 16
	game.elapsed = 125.0
	game.wave = 3
	game.overdrive = 2
	game.enemies.append(enemy(Vector2(200, 200), 2, 4.0))
	game.gems.append({"p": Vector2(300, 300), "phase": 0.5, "value": 2})
	game._burst(game.player, Color.WHITE, 20, 100.0)
	game._ring(game.player, Color.WHITE, 80.0, 1.0)
	game.boss_cinematic = 2.0
	game.dash_left = 0.17
	game._tick(0.0)
	game.save_run()
	check(game.save_notice.is_empty(), "visual-rich expedition still saves successfully")
	var expected_keys: Array = EXPECTED_RUN_FIELDS.duplicate()
	expected_keys.append("state")
	expected_keys.sort()
	var actual_keys: Array = game.profile.run.keys()
	actual_keys.sort()
	check(actual_keys == expected_keys, "checkpoint adds no tier, particles, rings, trails, or other cosmetic fields")
	check(game.profile.valid_game_run(game.profile.run), "checkpoint remains accepted by existing persistence validator")
	var expected: Dictionary = game.profile.run.duplicate(true)
	var restored = game.Progression.new()
	restored.load_data()
	check(restored.run == expected, "visual-rich checkpoint round trips on disk unchanged")
	game.profile = restored
	game.level = 1
	game.continue_run()
	check(game.level == 16 and game._ship_tier() == 3, "restored old-format level derives ship tier without new save fields")
	check(game.particles.is_empty() and game.rings.is_empty() and game.trails.is_empty(), "resume discards all unsaved effect state")
	near(game.boss_cinematic, 0.0, "resume does not replay an unsaved boss cinematic")
	for field in EXPECTED_RUN_FIELDS:
		if field != "invulnerable":
			check(game.get(field) == expected[field], "visual changes preserve restored gameplay field: " + field)


func _test_mechanics() -> void:
	for calm in [false, true]:
		for current_level in [1, 5, 10, 15, 100]:
			reset(calm)
			game.level = current_level
			var start: Vector2 = game.player
			Input.action_press("right")
			game._tick(0.05)
			near(game.player.x - start.x, minf(390.0, 235.0 + current_level * 4.0) * 0.05, "ship tier leaves movement unchanged at level %d with calm=%s" % [current_level, calm])
			Input.action_release("right")
			near(game._bolt_damage(), 1.0 + floorf(current_level / 5.0), "ship tier leaves damage unchanged at level %d with calm=%s" % [current_level, calm])
			check(game.try_dash(), "dash available at level %d with calm=%s" % [current_level, calm])
			near(game.dash_cooldown, maxf(0.85, 1.55 - (current_level - 1) * 0.05), "ship tier leaves dash cooldown unchanged at level %d with calm=%s" % [current_level, calm])
			start = game.player
			game._tick(0.05)
			near(game.player.x - start.x, 43.0, "ship tier leaves dash speed unchanged at level %d with calm=%s" % [current_level, calm])
		reset(calm)
		game.enemies.append(enemy(game.player + Vector2(100, 0)))
		game._fire()
		check(game.bolts.size() == 1 and game.bolts[0].v == Vector2(690, 0), "projectile cosmetics preserve base fire behavior with calm=%s" % calm)
		game.bolts[0].p = game.enemies[0].p
		game._move_bolts(0.0)
		check(game.enemies.is_empty() and game.kills == 1 and game.score == 10 and game.gems.size() == 1, "impact cosmetics preserve kill rewards with calm=%s" % calm)
		reset(calm)
		game._spawn_boss()
		check(game.boss_spawned and game.enemies.size() == 1 and game.enemies[0].kind == 3, "Warden cosmetic overhaul keeps one boss with calm=%s" % calm)
		near(game.enemies[0].hp, 480.0, "Warden retains original hull with calm=%s" % calm)
		near(game.enemies[0].warning, 2.0, "Warden retains original spawn warning with calm=%s" % calm)
		near(game.enemies[0].attack_timer, 5.0, "Warden retains original attack timing with calm=%s" % calm)
		near(game.boss_cinematic, 2.0, "Warden appearance starts bounded cinematic with calm=%s" % calm)
		game._destroy_enemy(0)
		check(game.boss_defeated and game.enemies.is_empty(), "Warden defeat effects keep boss completion with calm=%s" % calm)
		check(game.profile.credits == 50 and game.earned_credits == 50 and game.kills == 1 and game.score == 10, "Warden defeat retains exact rewards with calm=%s" % calm)
		check(game.particles.size() <= (120 if calm else 720) and game.rings.size() <= 32, "large Warden destruction respects effect budgets with calm=%s" % calm)
		near(game.boss_cinematic, 2.4, "Warden defeat starts bounded cinematic with calm=%s" % calm)
		game._tick_effects(3.0)
		near(game.boss_cinematic, 0.0, "Warden cinematic expires with calm=%s" % calm)
		check(game.particles.is_empty() and game.rings.is_empty(), "Warden destruction fully cleans up with calm=%s" % calm)
		game.boss_cinematic = 2.4
		game.start_game()
		near(game.boss_cinematic, 0.0, "new expedition clears Warden cinematic with calm=%s" % calm)
		reset(calm)
		game.energy = 4
		game.health = 3
		game.gems.append({"p": game.player, "phase": 0.0, "value": 1})
		game._collect_gems(0.0)
		check(game.level == 2 and game.health == 4 and game.state == "upgrade", "level-up effects preserve progression and choice with calm=%s" % calm)
		check(game.energy == 0 and game.next_level == 9 and game.score == 5, "level-up effects preserve XP threshold and rewards with calm=%s" % calm)


func _test_live_effect_stress(calm: bool) -> void:
	reset(calm)
	game.spawn_timer = 0.0
	game.fire_timer = 0.0
	game.level = 15
	game.overdrive = 5
	var max_particles := 0
	var max_rings := 0
	var max_trails := 0
	for frame in range(2400):
		if game.state == "upgrade":
			game.choose_upgrade((game.level - 2) % 3)
		game.invulnerable = 999.0
		if frame % 50 == 0:
			game.try_dash()
		game._process(1.0 / 60.0)
		max_particles = maxi(max_particles, game.particles.size())
		max_rings = maxi(max_rings, game.rings.size())
		max_trails = maxi(max_trails, game.trails.size())
	check(game.state in ["playing", "upgrade"] and game.elapsed > 39.9, "forty-second visual stress run completes with calm=%s" % calm)
	check(game.kills > 0, "stress run exercises live combat effects with calm=%s" % calm)
	check(max_particles <= (120 if calm else 720), "live combat respects particle budget with calm=%s" % calm)
	check(max_rings <= 32 and max_trails <= 40, "live combat respects ring and trail budgets with calm=%s" % calm)
	check(game.save_notice.is_empty(), "live combat autosaves remain valid with calm=%s" % calm)
	if calm:
		check(run_snapshot() == normal_stress_snapshot, "same-seed calm and normal combat preserve every gameplay field")
	else:
		normal_stress_snapshot = run_snapshot()
	print("VISUAL STRESS: calm=%s; 2,400 frames; kills=%d; peak particles=%d rings=%d trails=%d" % [calm, game.kills, max_particles, max_rings, max_trails])
