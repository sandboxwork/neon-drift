extends SceneTree
## Run only in a disposable user directory:
## NEON_DRIFT_TEST_SAVE=1 XDG_DATA_HOME=/tmp/neon-drift-progression-tests \
## godot --headless --path . --script res://tests/test_progression.gd

const Progression = preload("res://progression.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	if OS.get_environment("NEON_DRIFT_TEST_SAVE") != "1":
		printerr("Set NEON_DRIFT_TEST_SAVE=1 and use a disposable XDG_DATA_HOME to run save tests.")
		quit(2)
		return
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func clean() -> void:
	for path in [Progression.SAVE_PATH, Progression.BACKUP_PATH, Progression.TEMP_PATH, Progression.LEGACY_PATH]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(path)


func write_config(credits: Variant = 0, version: Variant = 1, snapshot: Variant = {}) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("meta", "version", version)
	config.set_value("pilot", "credits", credits)
	config.set_value("run", "snapshot", snapshot)
	check(config.save(Progression.SAVE_PATH) == OK, "fixture writes")
	return config


func snapshot() -> Dictionary:
	return {"player": Vector2(623.5, 344.25), "elapsed": 19.25, "health": 4, "max_health": 5,
		"state": "upgrade", "enemies": [{"p": Vector2(500, 220), "hp": 2.0, "max_hp": 2.0,
			"kind": 1, "dir": Vector2.RIGHT, "age": 2.0, "warning": -0.01, "phase": 1.0, "flash": 0.0}],
		"facing": Vector2.RIGHT, "rng_state": -4294967296, "kills": 11, "score": 110,
		"level": 2, "energy": 0, "next_level": 9, "wave": 1, "overdrive": 0, "phase_engine": 0,
		"recovery": 0, "earned_credits": 2, "run_weapon": 0, "dash_left": 0.0,
		"dash_cooldown": 0.0, "invulnerable": 0.0, "spawn_timer": 0.5, "damage_bonus": 0.0,
		"magnet_bonus": 0.0, "pulse_timer": 6.0, "fire_timer": -2.0, "boss_spawned": false,
		"boss_defeated": false, "endless": false, "bolts": [{"p": Vector2(300, 500), "v": Vector2(690, 0), "life": 0.3}],
		"gems": [{"p": Vector2(240, 320), "phase": 2.0, "value": 2}]}


func _run() -> void:
	clean()
	var pilot := Progression.new()
	pilot.load_data()
	check(pilot.credits == 0 and pilot.best == 0 and pilot.run.is_empty(), "missing save uses defaults")
	check(pilot.last_error.is_empty(), "missing save is not an error")
	check(pilot.weapon_unlocked(0) and not pilot.weapon_unlocked(1), "pulse initially available")
	check(not pilot.weapon_unlocked(-1) and not pilot.weapon_unlocked(3), "unknown weapons rejected")
	check(pilot.upgrade_cost("hull") == 15, "rank zero costs 15")
	check(pilot.upgrade_cost("unknown") == 0, "unknown upgrade has no cost")
	check(not pilot.buy_upgrade("hull") and pilot.hull_rank == 0, "insufficient credits do not upgrade")
	pilot.credits = 500
	check(pilot.buy_upgrade("hull"), "affordable purchase succeeds")
	check(pilot.credits == 485 and pilot.hull_rank == 1, "purchase applies cost and rank")
	check(pilot.upgrade_cost("hull_rank") == 35, "rank alias and rising price")
	var restored := Progression.new()
	restored.load_data()
	check(restored.credits == 485 and restored.hull_rank == 1, "purchase persists immediately")
	for rank in range(1, 5):
		check(pilot.buy_upgrade("hull"), "hull purchase rank %d" % (rank + 1))
	check(pilot.hull_rank == 5 and pilot.credits == 225, "all five hull ranks have exact total cost")
	check(not pilot.buy_upgrade("hull") and pilot.upgrade_cost("hull") == 0, "max rank cannot be purchased")
	check(not pilot.buy_upgrade("unknown"), "unknown purchase rejected")
	pilot.total_kills = 99
	check(not pilot.weapon_unlocked(1), "spread locked before 100 kills")
	pilot.total_kills = 100
	check(pilot.weapon_unlocked(1) and not pilot.weapon_unlocked(2), "spread unlocks at 100")
	pilot.total_kills = 299
	check(not pilot.weapon_unlocked(2), "lance locked before 300 kills")
	pilot.total_kills = 300
	check(pilot.weapon_unlocked(2), "lance unlocks at 300")
	pilot.weapon = 2
	pilot.damage_rank = 2
	pilot.magnet_rank = 3
	pilot.best = 5678
	pilot.run = snapshot()
	check(pilot.save_data(), "full profile and run save")
	restored.load_data()
	check(restored.run == pilot.run, "nested run round trips exactly, including vectors and RNG")
	check(restored.weapon == 2 and restored.damage_rank == 2 and restored.magnet_rank == 3, "loadout round trips")
	check(restored.best == 5678 and restored.total_kills == 300, "records round trip")
	check(FileAccess.file_exists(Progression.BACKUP_PATH), "second save leaves backup")
	check(not FileAccess.file_exists(Progression.TEMP_PATH), "successful save promotes temporary file")

	clean()
	var legacy := ConfigFile.new()
	legacy.set_value("record", "best", 9876)
	legacy.save(Progression.LEGACY_PATH)
	restored.load_data()
	check(restored.best == 9876, "legacy high score migrates without profile")
	check(restored.save_data(), "migrated profile can save")
	restored.best = 12000
	restored.save_data()
	restored.load_data()
	check(restored.best == 12000, "legacy score never lowers newer record")

	clean()
	var malformed := write_config(-99)
	malformed.set_value("pilot", "hull_rank", 999)
	malformed.set_value("pilot", "damage_rank", "5")
	malformed.set_value("pilot", "magnet_rank", -3)
	malformed.set_value("pilot", "total_kills", 99)
	malformed.set_value("pilot", "weapon", 2)
	malformed.set_value("pilot", "best", INF)
	malformed.save(Progression.SAVE_PATH)
	restored.load_data()
	check(restored.credits == 0 and restored.best == 0, "negative and nonfinite counters safely default")
	check(restored.hull_rank == 5 and restored.damage_rank == 0 and restored.magnet_rank == 0, "rank values are bounded and typed")
	check(restored.weapon == 0, "locked saved weapon resets to pulse")
	malformed.set_value("pilot", "credits", 9223372036854775807)
	malformed.save(Progression.SAVE_PATH)
	restored.load_data()
	check(restored.credits == Progression.MAX_COUNTER, "oversized integer counter clamps")

	var invalid := snapshot()
	invalid.health = -1
	write_config(70, 1, invalid)
	restored.load_data()
	check(restored.credits == 70 and restored.run.is_empty(), "invalid run keeps pilot and discards only snapshot")
	check(not restored.last_error.is_empty(), "invalid run produces explanatory warning")
	restored.run = {"player": Vector2.ZERO}
	check(not restored.save_data(), "incomplete run cannot replace last save")
	restored.run = snapshot()
	restored.run.enemies[0].p = Vector2(NAN, 0)
	check(not restored.save_data(), "nonfinite nested vector cannot save")
	restored.run = snapshot()
	restored.run.object = RefCounted.new()
	check(not restored.save_data(), "nested object cannot save")
	var full := snapshot()
	full.elapsed = 7200.0
	full.endless = true
	check(restored.valid_game_run(full), "two-hour Endless snapshot remains valid")
	full.enemies[0].attack_phase = "windup"
	check(not restored.valid_game_run(full), "partial dasher attack state rejected")
	full.enemies[0].attack_timer = 0.6
	full.enemies[0].locked_dir = Vector2.RIGHT
	check(restored.valid_game_run(full), "complete dasher attack state accepted")
	restored.run = full
	check(restored.save_data(), "runtime StringName attack keys save successfully")
	restored.load_data()
	check(restored.run == full, "runtime attack keys and vectors round trip")
	full.enemies[0].kind = 3
	check(not restored.valid_game_run(full), "boss without dash-hit timer rejected")
	full.enemies[0].dash_hit = 0.0
	check(restored.valid_game_run(full), "complete boss state accepted")
	for field in snapshot():
		if field == "rng_state":
			continue
		var missing := snapshot()
		missing.erase(field)
		check(not restored.valid_game_run(missing), "missing required run field rejected: " + field)
	full = snapshot()
	full.enemies[0].kind = "1"
	check(not restored.valid_game_run(full), "wrong enemy type rejected")
	full = snapshot()
	full.bolts[0].erase("v")
	check(not restored.valid_game_run(full), "missing bolt velocity rejected")
	full = snapshot()
	full.gems[0].value = "2"
	check(not restored.valid_game_run(full), "wrong gem value type rejected")
	full = snapshot()
	full.level = "2"
	check(not restored.valid_game_run(full), "wrong run scalar type rejected")
	full = snapshot()
	full.player = Vector2(1e30, 0)
	check(not restored.valid_game_run(full), "extreme finite coordinates rejected")

	clean()
	write_config(600, 99)
	var original := FileAccess.get_file_as_string(Progression.SAVE_PATH)
	restored.load_data()
	check(not restored.last_error.is_empty(), "future save version reports warning")
	restored.credits = 1000
	check(not restored.buy_upgrade("damage") and restored.credits == 1000 and restored.damage_rank == 0, "failed save rolls purchase back")
	check(FileAccess.get_file_as_string(Progression.SAVE_PATH) == original, "unsupported version is never overwritten")
	var unloaded := Progression.new()
	check(not unloaded.save_data(), "saving without loading still protects future format")
	DirAccess.rename_absolute(Progression.SAVE_PATH, Progression.BACKUP_PATH)
	unloaded = Progression.new()
	check(not unloaded.save_data(), "future backup protected when primary is missing")
	restored.load_data()
	check(not restored.save_data(), "future backup loaded in read-only mode")

	clean()
	pilot = Progression.new()
	pilot.credits = 100
	check(pilot.save_data(), "first recovery fixture saves")
	pilot.credits = 200
	check(pilot.save_data(), "second recovery fixture saves")
	var damaged := FileAccess.open(Progression.SAVE_PATH, FileAccess.WRITE)
	damaged.store_string("[broken\n")
	damaged.close()
	restored.load_data()
	check(restored.credits == 100 and restored.last_error.contains("backup"), "corrupt primary recovers prior backup")
	restored.credits = 75
	check(restored.save_data(), "recovered profile can replace corrupt primary")
	restored.load_data()
	check(restored.credits == 75, "repaired primary loads normally")
	var preserved := ConfigFile.new()
	preserved.load(Progression.BACKUP_PATH)
	check(preserved.get_value("pilot", "credits") == 100, "corrupt primary never overwrites good backup")
	DirAccess.remove_absolute(Progression.SAVE_PATH)
	restored.load_data()
	check(restored.credits == 100, "missing primary recovers backup after interrupted rename")

	clean()
	pilot = Progression.new()
	pilot.credits = 200
	pilot.save_data()
	original = FileAccess.get_file_as_string(Progression.SAVE_PATH)
	DirAccess.make_dir_absolute(Progression.TEMP_PATH)
	check(not pilot.buy_upgrade("magnet"), "I/O failure rejects purchase")
	check(pilot.credits == 200 and pilot.magnet_rank == 0, "I/O failure restores balance and rank")
	check(FileAccess.get_file_as_string(Progression.SAVE_PATH) == original, "I/O failure preserves prior file")
	clean()
	print("Progression: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
