extends SceneTree
## Run only with NEON_DRIFT_TEST_SAVE=1 and a disposable XDG_DATA_HOME:
## godot --headless --path . --script res://tests/test_campaign_persistence.gd

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


func legacy_snapshot() -> Dictionary:
	return {"player": Vector2(623.5, 344.25), "elapsed": 19.25, "health": 4, "max_health": 5,
		"state": "paused", "enemies": [{"p": Vector2(500, 220), "hp": 2.0, "max_hp": 2.0,
			"kind": 1, "dir": Vector2.RIGHT, "age": 2.0, "warning": -0.01, "phase": 1.0, "flash": 0.0}],
		"facing": Vector2.RIGHT, "rng_state": -4294967296, "kills": 11, "score": 110,
		"level": 2, "energy": 0, "next_level": 9, "wave": 1, "overdrive": 0, "phase_engine": 0,
		"recovery": 0, "earned_credits": 2, "run_weapon": 0, "dash_left": 0.0,
		"dash_cooldown": 0.0, "invulnerable": 0.0, "spawn_timer": 0.5, "damage_bonus": 0.0,
		"magnet_bonus": 0.0, "pulse_timer": 6.0, "fire_timer": -2.0, "boss_spawned": false,
		"boss_defeated": false, "endless": false, "bolts": [{"p": Vector2(300, 500), "v": Vector2(690, 0), "life": 0.3}],
		"gems": [{"p": Vector2(240, 320), "phase": 2.0, "value": 2}]}


func campaign() -> Dictionary:
	return {"mode": true, "sector": 1, "sector_time": 70.5, "objective": 7,
		"objective_clock": 0.5, "ship": 1, "claimed": [0], "intermission": false,
		"hazards": [{"p": Vector2(220, 310), "r": 36.0, "life": 2.5, "warning": -0.02}],
		"relics": [0, 2], "total_time": 190.75}


func snapshot() -> Dictionary:
	var result := legacy_snapshot()
	result.campaign = campaign()
	return result


func write_config(version: Variant = 2, run: Variant = {}) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("meta", "version", version)
	config.set_value("pilot", "credits", 73)
	config.set_value("pilot", "best", 4321)
	config.set_value("run", "snapshot", run)
	check(config.save(Progression.SAVE_PATH) == OK, "fixture writes")
	return config


func _run() -> void:
	clean()
	_test_migration()
	clean()
	_test_pilot_fields()
	clean()
	_test_achievements()
	clean()
	_test_campaign_schema()
	clean()
	_test_atomic_checkpoint()
	clean()
	print("Campaign persistence: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_migration() -> void:
	var pilot := Progression.new()
	pilot.load_data()
	check(pilot.ship == 0 and pilot.sector_unlocked == 0 and pilot.campaign_wins == 0 and pilot.achievements.is_empty(), "new pilot campaign defaults")
	check(pilot.ship_unlocked(0) and not pilot.ship_unlocked(1), "starter ship initially unlocked")
	check(not pilot.ship_unlocked(-1) and not pilot.ship_unlocked(3), "unknown ships never unlock")
	var old_run := legacy_snapshot()
	var config := write_config(1, old_run)
	config.set_value("pilot", "hull_rank", 3)
	config.set_value("pilot", "total_kills", 310)
	config.set_value("pilot", "weapon", 2)
	check(config.save(Progression.SAVE_PATH) == OK, "v1 pilot fixture writes")
	pilot.load_data()
	check(pilot.credits == 73 and pilot.best == 4321 and pilot.hull_rank == 3 and pilot.weapon == 2, "v1 pilot values preserved")
	check(pilot.ship == 0 and pilot.sector_unlocked == 0 and pilot.campaign_wins == 0 and pilot.achievements.is_empty(), "v1 campaign values default safely")
	check(pilot.run == old_run and pilot.last_error.is_empty(), "legacy run loads unchanged without campaign")
	check(pilot.save_data(), "v1 save upgrades successfully")
	config = ConfigFile.new()
	check(config.load(Progression.SAVE_PATH) == OK and config.get_value("meta", "version") == 2, "new writes use version 2")
	check(config.get_value("run", "snapshot") == old_run, "v2 migration preserves legacy snapshot exactly")
	var restored := Progression.new()
	restored.load_data()
	check(restored.run == old_run and restored.hull_rank == 3, "migrated pilot reloads")
	var backup := ConfigFile.new()
	check(backup.load(Progression.BACKUP_PATH) == OK and backup.get_value("meta", "version") == 1, "migration retains v1 backup")
	var damaged := FileAccess.open(Progression.SAVE_PATH, FileAccess.WRITE)
	damaged.store_string("[broken\n")
	damaged.close()
	restored.load_data()
	check(restored.run == old_run and restored.last_error.contains("backup"), "v1 backup recovers after v2 primary corruption")
	clean()
	write_config(3)
	var original := FileAccess.get_file_as_string(Progression.SAVE_PATH)
	pilot.load_data()
	check(not pilot.save_data(), "future version stays write protected")
	check(FileAccess.get_file_as_string(Progression.SAVE_PATH) == original, "future version remains unchanged")


func _test_pilot_fields() -> void:
	var pilot := Progression.new()
	pilot.sector_unlocked = 2
	pilot.ship = 2
	pilot.campaign_wins = 9
	pilot.achievements = ["first_sector", "second_sector", "campaign_clear"]
	check(pilot.ship_unlocked(0) and pilot.ship_unlocked(1) and pilot.ship_unlocked(2), "sector two unlocks all three ships")
	pilot.run = snapshot()
	check(pilot.save_data(), "campaign pilot and snapshot save")
	var restored := Progression.new()
	restored.load_data()
	check(restored.ship == 2 and restored.sector_unlocked == 2 and restored.campaign_wins == 9, "new pilot counters round trip")
	check(restored.achievements == pilot.achievements, "achievement IDs round trip")
	check(restored.run == pilot.run, "campaign snapshot round trips exactly with vectors")
	var config := write_config()
	config.set_value("pilot", "ship", 2)
	config.set_value("pilot", "sector_unlocked", 1)
	config.set_value("pilot", "campaign_wins", -99)
	config.set_value("pilot", "achievements", ["first_sector", "first_sector", "fake", 3, true, "veteran"])
	check(config.save(Progression.SAVE_PATH) == OK, "malformed campaign pilot writes")
	restored.load_data()
	check(restored.ship == 1 and restored.sector_unlocked == 1, "selected ship clamps to highest unlocked")
	check(restored.campaign_wins == 0, "negative campaign wins clamp")
	check(restored.achievements == ["first_sector", "veteran"], "unknown, non-string and duplicate achievement IDs discarded")
	for invalid in ["2", INF, NAN, {}, []]:
		config.set_value("pilot", "ship", invalid)
		config.set_value("pilot", "sector_unlocked", invalid)
		config.set_value("pilot", "campaign_wins", invalid)
		config.set_value("pilot", "achievements", invalid)
		check(config.save(Progression.SAVE_PATH) == OK, "invalid pilot fixture writes")
		restored.load_data()
		check(restored.ship == 0 and restored.sector_unlocked == 0 and restored.campaign_wins == 0 and restored.achievements.is_empty(), "invalid campaign pilot values default safely: " + str(invalid))
	config.set_value("pilot", "ship", 999)
	config.set_value("pilot", "sector_unlocked", 999)
	config.set_value("pilot", "campaign_wins", 9223372036854775807)
	check(config.save(Progression.SAVE_PATH) == OK, "oversized campaign pilot fixture writes")
	restored.load_data()
	check(restored.ship == 2 and restored.sector_unlocked == 2 and restored.campaign_wins == Progression.MAX_COUNTER, "oversized campaign pilot counters clamp")
	restored.ship = 2
	restored.sector_unlocked = 0
	restored.campaign_wins = -1
	check(restored.save_data(), "save clamps mutated pilot values")
	restored.load_data()
	check(restored.ship == 0 and restored.campaign_wins == 0, "saved pilot values respect unlock and counter bounds")


func _test_achievements() -> void:
	var pilot := Progression.new()
	pilot.credits = 40
	check(pilot.save_data(), "achievement baseline saves")
	var original := FileAccess.get_file_as_string(Progression.SAVE_PATH)
	check(pilot.award_achievement("first_sector", 25), "known achievement awards once")
	check(pilot.credits == 65 and pilot.achievements == ["first_sector"], "award changes credits and ID together")
	check(not pilot.award_achievement("first_sector", 25), "duplicate achievement rejected")
	check(pilot.credits == 65, "duplicate achievement never changes credits")
	check(not pilot.award_achievement("unknown", 200) and not pilot.award_achievement("evolved", -5), "unknown ID and negative reward rejected")
	check(pilot.credits == 65 and pilot.achievements == ["first_sector"], "invalid awards leave pilot unchanged")
	check(FileAccess.get_file_as_string(Progression.SAVE_PATH) == original, "awarding never writes a standalone save")
	var restored := Progression.new()
	restored.load_data()
	check(restored.credits == 40 and restored.achievements.is_empty(), "uncheckpointed award is not persisted")
	for id in Progression.ACHIEVEMENT_IDS:
		if id != "first_sector":
			check(pilot.award_achievement(id, 0), "supported achievement accepted: " + id)
	check(pilot.achievements.size() == 6, "exactly six supported achievements")
	pilot.achievements = []
	pilot.credits = Progression.MAX_COUNTER - 1
	check(pilot.award_achievement("veteran", 9223372036854775807), "large reward accepted without overflow")
	check(pilot.credits == Progression.MAX_COUNTER, "achievement rewards saturate at counter maximum")


func _test_campaign_schema() -> void:
	var pilot := Progression.new()
	check(pilot.valid_game_run({}), "empty run remains valid")
	check(pilot.valid_game_run(legacy_snapshot()), "legacy schema remains valid")
	check(pilot.valid_game_run(snapshot()), "complete campaign schema accepted")
	for field in campaign():
		var incomplete := snapshot()
		incomplete.campaign.erase(field)
		check(not pilot.valid_game_run(incomplete), "missing campaign field rejected: " + field)
	for malformed in [null, true, [], "campaign", 1, {}]:
		var invalid := snapshot()
		invalid.campaign = malformed
		check(not pilot.valid_game_run(invalid), "non-campaign shape rejected: " + str(malformed))
	for field in ["mode", "intermission"]:
		var invalid := snapshot()
		invalid.campaign[field] = 1
		check(not pilot.valid_game_run(invalid), "campaign bool must be bool: " + field)
	for field in ["sector", "ship", "objective"]:
		for value in [-1, 1.5, "1", true, INF, 10001]:
			var invalid := snapshot()
			invalid.campaign[field] = value
			check(not pilot.valid_game_run(invalid), "invalid campaign integer rejected: %s=%s" % [field, str(value)])
	for field in ["sector", "ship"]:
		var invalid := snapshot()
		invalid.campaign[field] = 3
		check(not pilot.valid_game_run(invalid), "campaign ID upper bound: " + field)
	for field in ["sector_time", "objective_clock", "total_time"]:
		for value in [-0.01, 864001, "1", true, INF, NAN]:
			var invalid := snapshot()
			invalid.campaign[field] = value
			check(not pilot.valid_game_run(invalid), "invalid campaign timer rejected: %s=%s" % [field, str(value)])
		for value in [0, 864000.0]:
			var valid := snapshot()
			valid.campaign[field] = value
			check(pilot.valid_game_run(valid), "campaign timer boundary accepted: %s=%s" % [field, str(value)])
	for claimed in [[0, 0], [-1], [3], [1.0], ["1"], [true], [0, 1, 2, 0], "0", {}]:
		var invalid := snapshot()
		invalid.campaign.claimed = claimed
		check(not pilot.valid_game_run(invalid), "invalid claimed sectors rejected: " + str(claimed))
	for relics in [[-1], [3], [1.0], ["1"], [true], [0, 1, 2, 0], "0", {}]:
		var invalid := snapshot()
		invalid.campaign.relics = relics
		check(not pilot.valid_game_run(invalid), "invalid relics rejected: " + str(relics))
	var boundary := snapshot()
	boundary.campaign.claimed = [0, 1, 2]
	boundary.campaign.relics = [0, 1, 2]
	boundary.campaign.objective = 10000
	check(pilot.valid_game_run(boundary), "maximum campaign collections and objective accepted")
	boundary.campaign.claimed = []
	boundary.campaign.relics = []
	boundary.campaign.hazards = []
	boundary.campaign.objective = 0
	boundary.campaign.mode = false
	check(pilot.valid_game_run(boundary), "empty collections and inactive campaign accepted")
	for hazards in [null, {}, "hazards", [Vector2.ZERO], [1], [{}]]:
		var invalid := snapshot()
		invalid.campaign.hazards = hazards
		check(not pilot.valid_game_run(invalid), "malformed hazards rejected: " + str(hazards))
	for field in ["p", "r", "life", "warning"]:
		var invalid := snapshot()
		invalid.campaign.hazards[0].erase(field)
		check(not pilot.valid_game_run(invalid), "missing hazard field rejected: " + field)
	for value in [Vector2(NAN, 0), Vector2(INF, 0), Vector2(1000001, 0), "position", Vector3.ZERO]:
		var invalid := snapshot()
		invalid.campaign.hazards[0].p = value
		check(not pilot.valid_game_run(invalid), "invalid hazard vector rejected: " + str(value))
	for field in ["r", "life", "warning"]:
		for value in ["1", true, INF, NAN, 864001, -2]:
			var invalid := snapshot()
			invalid.campaign.hazards[0][field] = value
			check(not pilot.valid_game_run(invalid), "invalid hazard number rejected: %s=%s" % [field, str(value)])
	for field in ["r", "life"]:
		var invalid := snapshot()
		invalid.campaign.hazards[0][field] = -0.01
		check(not pilot.valid_game_run(invalid), "negative hazard quantity rejected: " + field)
	var intermission := snapshot()
	intermission.campaign.intermission = true
	check(pilot.valid_game_run(intermission), "paused intermission checkpoint accepted")
	intermission.state = "intermission"
	check(not pilot.valid_game_run(intermission), "intermission is stored as paused rather than new top-level state")
	intermission.state = "upgrade"
	check(not pilot.valid_game_run(intermission), "upgrade state cannot also be intermission")
	intermission.campaign.intermission = false
	check(pilot.valid_game_run(intermission), "regular campaign upgrade checkpoint accepted")
	var unsafe := snapshot()
	unsafe.campaign.object = RefCounted.new()
	check(not pilot.valid_game_run(unsafe), "campaign cannot contain nested objects")
	unsafe = snapshot()
	unsafe.campaign.hazards.resize(4097)
	check(not pilot.valid_game_run(unsafe), "oversized hazard collection rejected")


func _test_atomic_checkpoint() -> void:
	var pilot := Progression.new()
	pilot.credits = 20
	pilot.run = snapshot()
	check(pilot.save_data(), "pre-clear checkpoint saves")
	var original := FileAccess.get_file_as_string(Progression.SAVE_PATH)
	check(pilot.award_achievement("first_sector", 30), "clear reward staged in memory")
	pilot.sector_unlocked = 1
	pilot.run.campaign.claimed = [0, 1]
	pilot.run.campaign.intermission = true
	DirAccess.make_dir_absolute(Progression.TEMP_PATH)
	check(not pilot.save_data(), "checkpoint I/O failure is reported")
	check(FileAccess.get_file_as_string(Progression.SAVE_PATH) == original, "failed checkpoint preserves prior run and credits together")
	var restored := Progression.new()
	restored.load_data()
	check(restored.credits == 20 and restored.achievements.is_empty() and not restored.run.campaign.intermission, "failed checkpoint cannot persist reward separately from run")
	DirAccess.remove_absolute(Progression.TEMP_PATH)
	check(pilot.save_data(), "staged checkpoint succeeds after transient I/O failure")
	restored.load_data()
	check(restored.credits == 50 and restored.achievements == ["first_sector"] and restored.sector_unlocked == 1, "successful checkpoint persists rewards and unlocks")
	check(restored.run.state == "paused" and restored.run.campaign.intermission and restored.run.campaign.claimed == [0, 1], "successful checkpoint persists paused intermission with claims")
	check(not restored.award_achievement("first_sector", 30) and restored.credits == 50, "reloaded checkpoint cannot duplicate achievement reward")
	var invalid := snapshot()
	invalid.campaign.claimed = [0, 0]
	var config := write_config(2, invalid)
	config.set_value("pilot", "sector_unlocked", 2)
	config.set_value("pilot", "ship", 2)
	config.set_value("pilot", "campaign_wins", 7)
	config.set_value("pilot", "achievements", ["first_sector"])
	check(config.save(Progression.SAVE_PATH) == OK, "invalid campaign fixture writes")
	restored.load_data()
	check(restored.run.is_empty() and not restored.last_error.is_empty(), "malformed campaign discards suspended run with warning")
	check(restored.credits == 73 and restored.ship == 2 and restored.campaign_wins == 7 and restored.achievements == ["first_sector"], "malformed campaign preserves pilot progression")
