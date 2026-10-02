extends SceneTree
## Campaign behavior regression suite, including a real-tick invulnerable autopilot.
## This is a deterministic integration fixture, NOT a difficulty/balance assessment.
## Run only in a disposable directory:
## DATA=$(mktemp -d /tmp/neon-drift-campaign.XXXXXX)
## NEON_DRIFT_TEST_SAVE=1 XDG_DATA_HOME="$DATA" godot --headless --path . --script res://tests/test_campaign.gd

const Progression = preload("res://progression.gd")
const Campaign = preload("res://campaign.gd")
const Runtime = preload("res://campaign_runtime.gd")
const DT := 0.05
const SIMULATION_LIMIT := 1200.0
var game: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var directory := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("NEON_DRIFT_TEST_SAVE") != "1" or not directory.begins_with("/tmp/") or directory.length() < 6:
		printerr("Refusing save tests: set NEON_DRIFT_TEST_SAVE=1 and a disposable XDG_DATA_HOME under /tmp/.")
		quit(2)
		return
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func near(actual: float, expected: float, description: String, tolerance := 0.001) -> void:
	check(absf(actual - expected) < tolerance, "%s (actual %.4f, expected %.4f)" % [description, actual, expected])

func clean() -> void:
	for path in [Progression.SAVE_PATH, Progression.BACKUP_PATH, Progression.TEMP_PATH, Progression.LEGACY_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func release_controls() -> void:
	for action in ["left", "right", "up", "down", "dash", "pause_game"]:
		Input.action_release(action)

func reset(sector := 0, ship := 0) -> void:
	release_controls()
	game.profile = Progression.new()
	game.profile.sector_unlocked = 2
	game.profile.ship = ship
	game.best_score = 0
	game.start_campaign(sector)
	game.spawn_timer = 1000.0
	game.fire_timer = 1000.0
	game.rng.seed = 13579
	game.invulnerable = 1000.0

func key(code: int, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	game._unhandled_input(event)

func enemy(position: Vector2, hp := 100.0, warning := 0.0) -> Dictionary:
	return {"p":position,"kind":0,"hp":hp,"max_hp":hp,"age":0.0,"warning":warning,"phase":0.0,"flash":0.0,"dir":Vector2.ZERO}

func achievement_reward(id: String) -> int:
	for achievement in Campaign.achievements():
		if achievement.id == id: return achievement.reward
	return -1

func restore_from_disk() -> void:
	game.profile = Progression.new()
	game.profile.load_data()
	check(game.profile.last_error.is_empty(), "checkpoint loads without warning")
	game.state = "menu"
	game.continue_run()

func clear_sector_fixture() -> void:
	# Isolated transition fixture only. The full simulation below never sets
	# objective, boss flags, enemy health, time, damage, or build to bypass play.
	game.campaign.objective = Campaign.sector(game.campaign.sector).objective_target
	game.boss_spawned = true
	game.boss_defeated = true
	game._tick(DT)

func _run() -> void:
	if "--checkpoint-check" in OS.get_cmdline_user_args():
		_read_checkpoint_in_fresh_process()
		return
	clean()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	game.reduced_motion = true
	_test_content()
	_test_keyboard_routes()
	_test_ships()
	_test_objectives()
	_test_hazards()
	_test_evolutions()
	_test_relics_and_checkpoints()
	_test_achievements_and_terminal_guards()
	_test_death_and_legacy_continue()
	_test_populated_campaign_checkpoints()
	_test_normal_damage_smoke()
	_test_full_campaign()
	release_controls()
	game.free()
	clean()
	print("Campaign behavior: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_content() -> void:
	check(Campaign.SECTORS.size() == 3 and Campaign.SHIPS.size() == 3, "three sectors and three ships exist")
	check(Campaign.achievements().size() == 6, "six campaign achievements exist")
	var copy := Campaign.sector(0)
	copy.name = "changed fixture"
	check(Campaign.sector(0).name != copy.name, "sector data cannot mutate shared content")
	copy = Campaign.ship(0)
	copy.hull_bonus = 100
	check(Campaign.ship(0).hull_bonus == 0, "ship data cannot mutate shared content")
	for id in range(3):
		var sector := Campaign.sector(id)
		check(sector.id == id and sector.objective_target > 0 and sector.boss_hp > 0, "sector %d has valid objective and guardian" % id)
		check(sector.hazard_warning >= 1.0 and sector.boss_time > 0, "sector %d has readable warning and finite guardian trigger" % id)
		check(Campaign.evolution(id,2,5,5).is_empty(), "weapon %d requires overdrive rank three" % id)
		check(not Campaign.evolution(id,3,2,2).is_empty(), "weapon %d recipe resolves" % id)
	check(Campaign.evolution(0,3,0,1).is_empty(), "Nova requires recovery rank two")
	check(Campaign.evolution(1,3,1,0).is_empty(), "Starweave requires phase rank two")
	check(Campaign.evolution(2,3,0,1).is_empty(), "Void Lance requires recovery rank two")
	check(Campaign.evolution(99,99,99,99).is_empty(), "unknown weapon has no evolution")

func _test_keyboard_routes() -> void:
	check(game.state == "menu" and game.profile.run.is_empty(), "fresh profile opens title without suspended run")
	check(game.profile.ship == 0 and game.profile.sector_unlocked == 0, "fresh pilot has only first sector and Vector")
	key(KEY_ENTER, true)
	check(game.state == "menu", "echoed menu input is ignored")
	key(KEY_ENTER)
	check(game.state == "sector_map", "fresh Enter opens sector map")
	key(KEY_3)
	check(game.map_sector == 0, "locked sector hotkey cannot select Crown")
	key(KEY_S)
	check(game.profile.ship == 0, "ship cycle skips all locked ships")
	key(KEY_J)
	check(game.state == "journal", "J opens journal")
	key(KEY_ENTER)
	check(game.state == "sector_map", "Enter exits journal to map")
	key(KEY_ESCAPE)
	check(game.state == "menu", "Escape exits map to title")
	key(KEY_H)
	check(game.state == "hangar", "H opens hangar")
	key(KEY_ESCAPE)
	check(game.state == "menu", "Escape exits hangar")
	key(KEY_C)
	check(game.state == "sector_map", "C opens campaign map")
	key(KEY_ENTER)
	check(game.state == "playing" and Runtime.active(game) and game.campaign.sector == 0, "map Enter launches first campaign sector")
	check(game.profile.run.has("campaign") and game.save_notice.is_empty(), "new campaign checkpoint saves")
	key(KEY_ESCAPE)
	check(game.state == "paused", "Escape pauses campaign")
	var before: float = game.campaign.total_time
	game._process(3.0)
	near(game.campaign.total_time,before,"pause freezes campaign clock")
	key(KEY_ENTER)
	check(game.state == "playing", "Enter resumes paused campaign")
	game._go_home()
	check(game.state == "menu" and not game.profile.run.is_empty(), "save and title keeps active campaign")
	key(KEY_ENTER)
	check(game.state == "playing" and Runtime.active(game), "title Enter continues saved campaign")
	game._go_home()
	key(KEY_N)
	check(game.state == "sector_map", "N opens new campaign map")
	key(KEY_ENTER)
	check(game.state == "confirm_new", "new campaign requires confirmation when a run exists")
	var saved: Dictionary = game.profile.run.duplicate(true)
	key(KEY_ESCAPE)
	check(game.state == "menu" and game.profile.run == saved, "cancel new campaign preserves checkpoint")
	key(KEY_C)
	key(KEY_ENTER)
	key(KEY_ENTER)
	check(game.state == "playing" and game.campaign.total_time == 0.0, "confirmed new campaign resets run")
	game._on_focus_lost()
	check(game.state == "paused" and game.profile.run.has("campaign"), "focus loss checkpoints campaign")
	key(KEY_ENTER)
	key(KEY_SPACE)
	check(game.dash_left > 0.0, "Space keyboard route dashes in campaign")
	game.profile.sector_unlocked = 2
	game._go_home()
	key(KEY_C)
	key(KEY_2)
	check(game.map_sector == 1, "unlocked sector hotkey selects Foundry")
	key(KEY_S)
	check(game.profile.ship == 1, "S cycles to unlocked Kestrel")
	key(KEY_3)
	check(game.map_sector == 2, "unlocked third sector selectable")
	key(KEY_1)
	check(game.map_sector == 0, "first-sector hotkey restores full-campaign start")

func _test_ships() -> void:
	for id in range(3):
		reset(0,id)
		var ship := Campaign.ship(id)
		check(game.max_health == 5 + ship.hull_bonus and game.health == game.max_health, "ship %d applies starting hull" % id)
		var original: Vector2 = game.player
		Input.action_press("right")
		game._tick(DT)
		release_controls()
		near(game.player.x-original.x,239.0*ship.speed_mult*DT,"ship %d applies movement multiplier" % id)
		near(game._bolt_damage(),ship.damage_mult,"ship %d applies weapon multiplier" % id)
		check(game.try_dash(), "ship %d dash is available" % id)
		near(game.dash_cooldown,1.55*ship.dash_mult,"ship %d applies dash multiplier" % id)
		check(not game.try_dash(), "ship %d cannot bypass dash cooldown" % id)
		game.save_run()
		restore_from_disk()
		check(game.campaign.ship == id and game.max_health == 5 + ship.hull_bonus, "ship %d survives continue" % id)
	reset()
	game.profile.sector_unlocked = 0
	var snapshot: Dictionary = game.campaign.duplicate(true)
	game.start_campaign(2)
	check(game.campaign == snapshot, "locked direct launch cannot overwrite current run")
	game.start_campaign(-1)
	check(game.campaign == snapshot, "negative direct launch rejected")

func _test_objectives() -> void:
	for id in range(3):
		reset(id)
		var target: int = Campaign.sector(id).objective_target
		game.player = Vector2(640,600)
		for i in range(20): game._tick(DT)
		check(game.campaign.objective == 0, "sector %d does not advance while away from objective" % id)
		var first: Vector2 = Runtime.relay_position(game) if id == 1 else Runtime.objective_position(game)
		game.player = first
		for i in range(3): game._tick(DT)
		check(game.campaign.objective_clock > 0 and game.campaign.objective == 0, "sector %d requires sustained contact" % id)
		var partial: float = game.campaign.objective_clock
		game.player = Vector2(640,600)
		game._tick(DT)
		check(game.campaign.objective_clock < partial, "sector %d decays incomplete contact outside objective" % id)
		var ticks := 0
		while game.campaign.objective < target and ticks < 1200:
			game.player = Runtime.relay_position(game) if id == 1 else Runtime.objective_position(game)
			game._tick(DT)
			ticks += 1
		check(game.campaign.objective == target, "sector %d completes real mission objective ticks" % id)
		check(game.score == target*25, "sector %d objective awards exact score" % id)
		check(game.state == "playing" and not game.boss_defeated, "sector %d objective alone cannot clear sector" % id)
		var completed: int = game.campaign.objective
		for i in range(20): game._tick(DT)
		check(game.campaign.objective == completed, "sector %d objective count stops at target" % id)
		game.campaign.sector_time = Campaign.sector(id).boss_time-DT/2.0
		game._tick(DT)
		var bosses := 0
		for e in game.enemies:
			if e.kind == 3:
				bosses += 1
				near(e.hp,Campaign.sector(id).boss_hp,"sector %d guardian uses sector health" % id)
		check(game.boss_spawned and bosses == 1, "sector %d guardian spawns at its clock" % id)
		game._tick(DT)
		check(game.enemies.size() == 1, "sector %d guardian cannot spawn twice" % id)
		check(game.state == "playing", "sector %d must defeat guardian to exit" % id)
	reset(1)
	var first_relay: Vector2 = Runtime.relay_position(game)
	game.campaign.objective = 5
	check(Runtime.relay_position(game) == first_relay, "relay keeps same field for six charges")
	game.campaign.objective = 6
	check(Runtime.relay_position(game) != first_relay, "relay moves after six charges")

func _test_hazards() -> void:
	for id in range(3):
		reset(id)
		game.invulnerable = 0.0
		var original_health: int = game.health
		Runtime.add_hazard(game,game.player,50.0,0.2,0.5)
		game._tick(DT)
		check(game.health == original_health and game.campaign.hazards[0].warning > 0, "sector %d hazard telegraph is harmless" % id)
		for i in range(4): game._tick(DT)
		check(game.health == original_health-1, "sector %d active hazard damages hull" % id)
		game._tick(DT)
		check(game.health == original_health-1, "sector %d hazard respects invulnerability" % id)
		for i in range(12): game._tick(DT)
		check(game.campaign.hazards.is_empty(), "sector %d expired hazards are removed" % id)
		reset(id)
		game.invulnerable = 0.0
		Runtime.add_hazard(game,game.player,110.0,0.0,0.5)
		check(game.try_dash(), "sector %d can dash from hazard" % id)
		game.invulnerable = 0.0
		game._tick(DT)
		check(game.health == game.max_health, "sector %d dash protects against active hazard" % id)
		reset(id)
		var sector := Campaign.sector(id)
		game.campaign.sector_time = sector.hazard_interval-DT/2.0
		game._tick(DT)
		check(game.campaign.hazards.size() == 1, "sector %d schedules environmental hazard" % id)
		near(game.campaign.hazards[0].r,sector.hazard_radius,"sector %d uses environmental radius" % id)
		near(game.campaign.hazards[0].warning,sector.hazard_warning,"sector %d starts full telegraph" % id)
		game.campaign.hazards.clear()
		Runtime.boss_attack(game,{"p":Vector2(640,300),"age":2.0})
		check(game.campaign.hazards.size() == [3,6,5][id], "sector %d guardian has distinct attack pattern" % id)
		for h in game.campaign.hazards:
			check(h.warning >= 1.0 and h.life > h.warning, "sector %d guardian attack telegraphs before activation" % id)
	reset(2)
	game.player = Vector2(640,374)
	Runtime.add_hazard(game,Vector2(740,374),98.0,0.0,1.0)
	var before: Vector2 = game.player
	game._tick(DT)
	check(game.player.x > before.x, "Crown gravity well pulls player toward center")
	reset(2)
	Runtime.add_hazard(game,Vector2(740,374),98.0,0.0,1.0)
	game.facing = Vector2.UP
	game.try_dash()
	before = game.player
	game._tick(DT)
	near(game.player.x,before.x,"dash ignores gravity pull")
	reset()
	for i in range(100): Runtime.add_hazard(game,Vector2(-100,2000),30.0,1.0,1.0)
	check(game.campaign.hazards.size() == 36, "hazard budget caps at 36")
	check(game.campaign.hazards[0].p == Vector2(65,600), "hazards clamp to arena-safe coordinates")

func _test_evolutions() -> void:
	for weapon in range(3):
		reset()
		game.run_weapon = weapon
		for choice in [0,0,0,1 if weapon == 1 else 2]:
			game.state = "upgrade"
			game.choose_upgrade(choice)
		check(Campaign.evolution(weapon,game.overdrive,game.phase_engine,game.recovery).is_empty(), "weapon %d stays unevolved before final recipe rank" % weapon)
		game.state = "upgrade"
		game.choose_upgrade(1 if weapon == 1 else 2)
		check(not Campaign.evolution(weapon,game.overdrive,game.phase_engine,game.recovery).is_empty(), "weapon %d evolves through real upgrade choices" % weapon)
		check("evolved" in game.profile.achievements, "weapon %d evolution awards achievement" % weapon)
		check(game.profile.credits == achievement_reward("evolved"), "weapon %d evolution reward matches content" % weapon)
		var credits: int = game.profile.credits
		game._check_evolution()
		check(game.profile.credits == credits, "weapon %d evolution reward pays once" % weapon)
		restore_from_disk()
		check(game.run_weapon == weapon and not Campaign.evolution(weapon,game.overdrive,game.phase_engine,game.recovery).is_empty(), "weapon %d evolution build survives continue" % weapon)
	reset()
	game.overdrive = 3
	game.recovery = 2
	game.enemies.append(enemy(game.player+Vector2(120,0)))
	game.enemies.append(enemy(game.player+Vector2(300,0)))
	game.enemies.append(enemy(game.player+Vector2(0,120),100.0,2.0))
	game.evolution_clock = 0.0
	var expected: float = 100.0-game._bolt_damage()*2.0
	game._tick(DT)
	near(game.enemies[0].hp,expected,"Nova Array deals radial damage inside its radius")
	near(game.enemies[1].hp,100.0,"Nova Array leaves distant enemies unharmed")
	near(game.enemies[2].hp,100.0,"Nova Array respects spawn warning immunity")
	game._tick(DT)
	near(game.enemies[0].hp,expected,"Nova Array does not trigger every frame")
	game.evolution_clock = 0.0
	game._tick(DT)
	check(game.enemies[0].hp < expected, "Nova Array repeats after its cooldown")
	reset()
	game.run_weapon = 1
	game.overdrive = 3
	game.phase_engine = 1
	game.enemies.append(enemy(game.player+Vector2(120,0)))
	game._fire()
	var baseline: int = game.bolts.size()
	game.bolts.clear()
	game.phase_engine = 2
	game._fire()
	check(game.bolts.size() == baseline+8, "Starweave adds eight radial stars to regular Fan fire")
	var directions: Array[Vector2] = []
	for i in range(baseline,game.bolts.size()):
		near(game.bolts[i].v.length(),600.0,"Starweave star has defined velocity")
		directions.append(game.bolts[i].v.normalized())
	check(directions[0].dot(directions[4]) < -0.99, "Starweave covers opposite sides of the ship")
	game.enemies.clear()
	game.enemies.append(enemy(game.player+directions[4]*70.0,1.0))
	game._move_bolts(0.15)
	check(game.enemies.is_empty(), "Starweave radial star causes real swept-collision damage")
	reset()
	game.run_weapon = 2
	game.overdrive = 3
	game.recovery = 2
	game.enemies.append(enemy(game.player+Vector2(100,0)))
	game.enemies.append(enemy(game.player+Vector2(220,0)))
	game.enemies.append(enemy(game.player+Vector2(220,70)))
	game.enemies.append(enemy(game.player+Vector2(150,0),100.0,1.0))
	var pierce: float = game._bolt_damage()*0.65
	game._fire()
	near(game.enemies[0].hp,100.0-pierce,"Void Lance directly strikes first aligned enemy")
	near(game.enemies[1].hp,100.0-pierce,"Void Lance pierces second aligned enemy")
	near(game.enemies[2].hp,100.0,"Void Lance does not damage off-axis enemy")
	near(game.enemies[3].hp,100.0,"Void Lance respects spawn warning immunity")
	check(not game.bolts.is_empty(), "Void Lance preserves normal projectile fire")
	reset()
	game.start_game()
	game.spawn_timer = 1000.0
	game.fire_timer = 1000.0
	game.overdrive = 3
	game.recovery = 2
	game.enemies.append(enemy(game.player+Vector2(120,0)))
	game._tick(DT)
	near(game.enemies[0].hp,100.0,"legacy survival does not silently receive campaign Nova behavior")

func _test_relics_and_checkpoints() -> void:
	for choice in range(3):
		reset()
		game.overdrive = 2
		game.phase_engine = 2
		game.recovery = 1
		game.damage_bonus = 0.4
		game.health = 2
		game.score = 321
		game.kills = 17
		game.enemies.append(enemy(Vector2(80,150)))
		game.bolts.append({"p":Vector2(100,100),"v":Vector2.RIGHT,"life":1.0})
		game.gems.append({"p":Vector2(500,500),"phase":0.0,"value":2})
		clear_sector_fixture()
		check(game.state == "intermission" and game.campaign.intermission, "relic %d fixture reaches intermission" % choice)
		check(game.profile.run.state == "paused" and game.profile.run.campaign.intermission, "intermission %d saved as pending paused choice" % choice)
		check(game.save_notice.is_empty(), "intermission %d checkpoint valid" % choice)
		if choice == 0: check_fresh_process("pending relic intermission")
		var time: float = game.campaign.total_time
		game._process(8.0)
		near(game.campaign.total_time,time,"intermission %d freezes mission clock" % choice)
		var credits: int = game.profile.credits
		Runtime.complete(game)
		check(game.profile.credits == credits and game.campaign.claimed == [0], "intermission %d repeated completion cannot duplicate rewards" % choice)
		key(KEY_ESCAPE)
		check(game.state == "menu", "intermission %d Escape saves to title" % choice)
		restore_from_disk()
		check(game.state == "intermission" and game.campaign.claimed == [0], "intermission %d restores pending relic" % choice)
		check(game.score == 321 and game.kills == 17 and game.overdrive == 2, "intermission %d restores current build and score" % choice)
		Runtime.choose_relic(game,-1)
		Runtime.choose_relic(game,3)
		check(game.state == "intermission" and game.campaign.relics.is_empty(), "invalid relic choices cannot dismiss intermission")
		key(KEY_ENTER)
		check(game.state == "intermission", "Enter cannot skip relic selection")
		key(KEY_1+choice)
		check(game.state == "playing" and game.campaign.sector == 1 and not game.campaign.intermission, "relic %d launches next sector" % choice)
		check(game.campaign.relics == [choice] and game.campaign.claimed == [0], "relic %d recorded exactly once" % choice)
		near(game.damage_bonus,0.9 if choice == 0 else 0.4,"relic %d damage effect" % choice)
		check(game.phase_engine == (3 if choice == 1 else 2), "relic %d phase effect" % choice)
		check(game.max_health == (6 if choice == 2 else 5) and game.health == game.max_health, "relic %d hull and full repair effect" % choice)
		check(game.overdrive == 2 and game.recovery == 1 and game.score == 321 and game.kills == 17, "relic %d preserves build and accumulated progress" % choice)
		check(game.campaign.objective == 0 and game.campaign.sector_time == 0.0 and game.campaign.objective_clock == 0.0, "relic %d resets next mission clocks" % choice)
		check(not game.boss_spawned and not game.boss_defeated and game.enemies.is_empty() and game.gems.is_empty() and game.bolts.is_empty(), "relic %d clears prior combat entities and guardian state" % choice)
		check(game.invulnerable >= 2.0 and game.player == game.ARENA.get_center(), "relic %d arrival has safe position and protection" % choice)
		Runtime.choose_relic(game,choice)
		check(game.campaign.relics == [choice] and game.campaign.sector == 1, "relic %d duplicate selection ignored" % choice)
		restore_from_disk()
		check(game.state == "playing" and game.campaign.sector == 1 and game.campaign.relics == [choice], "relic %d next-sector checkpoint continues without applying twice" % choice)
		near(game.damage_bonus,0.9 if choice == 0 else 0.4,"relic %d bonus persists exactly once" % choice)
	reset()
	game.run_weapon = 1
	game.overdrive = 3
	game.phase_engine = 1
	clear_sector_fixture()
	Runtime.choose_relic(game,1)
	check("evolved" in game.profile.achievements and Campaign.evolution(1,3,game.phase_engine,0) == "STARWEAVE", "phase relic can trigger Starweave evolution achievement")
	reset()
	game.phase_engine = 4
	clear_sector_fixture()
	Runtime.choose_relic(game,1)
	check("dash_50" in game.profile.achievements, "phase relic reaching rank five grants Phase Master")

func _test_achievements_and_terminal_guards() -> void:
	reset()
	game.phase_engine = 4
	game.state = "upgrade"
	game.choose_upgrade(1)
	check("dash_50" in game.profile.achievements and game.profile.credits == achievement_reward("dash_50"), "Phase Master threshold and reward match content")
	var credits: int = game.profile.credits
	game._check_evolution()
	check(game.profile.credits == credits, "Phase Master pays only once")
	reset()
	game.profile.total_kills = 999
	game.enemies.append(enemy(game.player+Vector2(70,0),1.0))
	game._fire()
	game._move_bolts(0.1)
	check(game.profile.total_kills == 1000 and "veteran" in game.profile.achievements, "1000th real projectile kill earns Veteran")
	check(game.profile.credits == achievement_reward("veteran"), "Veteran reward matches content")
	credits = game.profile.credits
	game.enemies.append(enemy(game.player+Vector2(70,0),1.0))
	game._fire()
	game._move_bolts(0.1)
	check(game.profile.credits == credits, "Veteran cannot pay again on next kill")
	reset()
	game.profile.sector_unlocked = 0
	var expected_credits := 0
	for id in range(3):
		var achievement_id: String = ["first_sector","second_sector","campaign_clear"][id]
		clear_sector_fixture()
		expected_credits += Campaign.sector(id).reward + achievement_reward(achievement_id)
		if id == 2: expected_credits += 50 # Normal terminal victory payout.
		check(game.profile.credits == expected_credits, "sector %d and achievement payouts match content" % id)
		check(achievement_id in game.profile.achievements, "sector %d earns its achievement" % id)
		check(game.profile.sector_unlocked == mini(id+1,2), "sector %d unlocks next route" % id)
		check(game.profile.ship_unlocked(mini(id+1,2)), "sector %d unlocks next ship" % id)
		credits = game.profile.credits
		Runtime.complete(game)
		check(game.profile.credits == credits, "sector %d completion is idempotent" % id)
		if id < 2: Runtime.choose_relic(game,id)
	check(game.state == "won" and game.profile.campaign_wins == 1, "all three sectors award one full campaign win")
	check(game.campaign.claimed == [0,1,2] and game.campaign.relics == [0,1], "full route records all claims and two relics")
	check(game.profile.run.is_empty(), "campaign victory clears suspended run")
	var score: int = game.score
	game.finish_game(true)
	Runtime.complete(game)
	check(game.profile.credits == credits and game.score == score and game.profile.campaign_wins == 1, "repeat terminal callbacks cannot duplicate win, score, or rewards")
	var restored := Progression.new()
	restored.load_data()
	check(restored.campaign_wins == 1 and restored.run.is_empty() and restored.achievements.size() == 3, "full victory and achievement rewards persist together")
	for start in [1,2]:
		reset(start)
		for id in range(start,3):
			clear_sector_fixture()
			if id < 2: Runtime.choose_relic(game,2)
		check(game.state == "won" and game.profile.campaign_wins == 0, "practice start %d cannot earn a full campaign win" % start)
		check("campaign_clear" not in game.profile.achievements, "practice start %d cannot earn Crownless" % start)
		check(game.profile.run.is_empty(), "practice start %d still closes terminal checkpoint" % start)

func _test_death_and_legacy_continue() -> void:
	reset(1,1)
	game.profile.credits = 83
	game.overdrive = 3
	game.recovery = 2
	game.health = 1
	game.invulnerable = 0.0
	Runtime.add_hazard(game,game.player,60.0,0.0,1.0)
	game._tick(DT)
	check(game.state == "lost" and game.health == 0 and game.profile.run.is_empty(), "lethal campaign hazard loses and clears checkpoint")
	var restored := Progression.new()
	restored.load_data()
	check(restored.credits == 83 and restored.ship == 1 and restored.run.is_empty(), "death retains permanent pilot progress")
	key(KEY_R)
	check(game.state == "playing" and game.campaign.sector == 0 and game.campaign.ship == 1, "R after campaign loss starts full route with selected ship")
	check(game.overdrive == 0 and game.recovery == 0 and game.campaign.claimed.is_empty() and game.campaign.relics.is_empty(), "retry clears prior campaign build and claims")
	check(game.health == game.max_health and game.kills == 0 and game.elapsed == 0.0, "retry restores hull and resets combat counters")
	game.health = 1
	game._damage_player()
	key(KEY_ENTER)
	check(game.state == "playing" and Runtime.active(game), "Enter after campaign loss retries campaign")
	game.health = 1
	game._damage_player()
	key(KEY_ESCAPE)
	check(game.state == "menu", "Escape after campaign loss returns to title")
	# Write a genuine version-one, campaign-free snapshot and restore it through
	# the same Continue route used by the title screen.
	game.start_game()
	game.player = Vector2(460,320)
	game.elapsed = 72.25
	game.overdrive = 2
	game.health = 3
	game.save_run()
	var legacy: Dictionary = game.profile.run.duplicate(true)
	check(not legacy.has("campaign"), "legacy survival snapshot has no campaign")
	var config := ConfigFile.new()
	config.set_value("meta","version",1)
	config.set_value("pilot","credits",27)
	config.set_value("run","snapshot",legacy)
	check(config.save(Progression.SAVE_PATH) == OK, "version-one gameplay fixture writes")
	game.campaign = Runtime.fresh(2,2)
	restore_from_disk()
	check(game.state == "playing" and game.campaign.is_empty() and not Runtime.active(game), "v1 Continue restores legacy survival without campaign leakage")
	check(game.player == Vector2(460,320) and game.overdrive == 2 and game.health == 3 and game.profile.credits == 27, "v1 Continue preserves location, build, hull, and pilot credits")
	near(game.elapsed,72.25,"v1 Continue preserves survival time")
	game._tick(DT)
	near(game.elapsed,72.3,"v1 run continues ticking normally")
	game.health = 1
	game._damage_player()
	key(KEY_R)
	check(game.state == "playing" and game.campaign.is_empty(), "v1 survival retry remains survival")

func steer_toward(target: Vector2, stop_radius := 10.0) -> void:
	release_controls()
	var offset: Vector2 = target-game.player
	if offset.length() <= stop_radius: return
	var direction := offset.normalized()
	if direction.x > 0: Input.action_press("right",direction.x)
	else: Input.action_press("left",-direction.x)
	if direction.y > 0: Input.action_press("down",direction.y)
	else: Input.action_press("up",-direction.y)

func _test_full_campaign() -> void:
	# Integration fixture: only invulnerability is forced. Ordinary input drives
	# movement; spawn/fire clocks, enemy HP, objectives, rewards and upgrades all
	# advance through production code. No direct enemy destruction or boss flags.
	release_controls()
	game.profile = Progression.new()
	game.best_score = 0
	game.rng.seed = 20261002
	game.start_campaign(0)
	var simulated := 0.0
	var transitions: Array[int] = []
	var boss_seen: Array[int] = []
	var damaged_bosses: Array[int] = []
	var peak_enemies := 0
	var choices := 0
	var sampled_valid := true
	while simulated < SIMULATION_LIMIT and game.state not in ["won","lost"]:
		if game.state == "intermission":
			transitions.append(game.campaign.sector)
			check(game.boss_defeated, "autopilot sector %d guardian defeated through combat" % game.campaign.sector)
			check(game.campaign.objective == Campaign.sector(game.campaign.sector).objective_target, "autopilot sector %d real mission complete" % game.campaign.sector)
			Runtime.choose_relic(game,0 if game.campaign.sector == 0 else 1)
			continue
		if game.state == "upgrade":
			var choice := 0 if game.overdrive < 3 else (2 if game.recovery < 2 else (1 if game.phase_engine < 5 else choices%3))
			game.choose_upgrade(choice)
			choices += 1
			continue
		if game.state != "playing": break
		game.invulnerable = 1000.0
		var sector: int = game.campaign.sector
		var objective_target: int = Campaign.sector(sector).objective_target
		var target: Vector2 = game.ARENA.get_center()
		var stop_radius := 12.0
		if game.campaign.objective < objective_target:
			target = Runtime.relay_position(game) if sector == 1 else Runtime.objective_position(game)
			stop_radius = 40.0 if sector == 1 else 12.0
		else:
			var nearest := INF
			for gem in game.gems:
				var distance: float = game.player.distance_squared_to(gem.p)
				if distance < nearest:
					nearest = distance
					target = gem.p
			for e in game.enemies:
				if e.kind == 3:
					target = e.p
					stop_radius = 85.0
					break
		steer_toward(target,stop_radius)
		game._tick(DT)
		game._tick_effects(DT)
		simulated += DT
		peak_enemies = maxi(peak_enemies,game.enemies.size())
		for e in game.enemies:
			if e.kind == 3:
				if sector not in boss_seen: boss_seen.append(sector)
				if e.hp < e.max_hp and sector not in damaged_bosses: damaged_bosses.append(sector)
		if int(simulated*20)%200 == 0:
			sampled_valid = sampled_valid and game.profile.valid_game_run(game.profile.run)
			if not game.save_notice.is_empty(): sampled_valid = false
	release_controls()
	check(game.state == "won", "real-tick campaign autopilot reaches victory within 20 simulated minutes")
	check(game.profile.campaign_wins == 1 and game.campaign.claimed == [0,1,2], "real-tick autopilot completes all three sectors")
	check(transitions == [0,1] and game.campaign.relics == [0,1], "real-tick autopilot passes both relic intermissions")
	check(boss_seen == [0,1,2] and damaged_bosses == [0,1,2], "all three natural guardians spawn and take ordinary weapon damage")
	check(game.boss_defeated and game.campaign.objective == Campaign.sector(2).objective_target, "final natural guardian and salvage objective complete")
	check(choices >= 5 and "evolved" in game.profile.achievements, "autopilot earns upgrades and evolution through collected energy")
	check(peak_enemies <= 95 and game.kills > 0, "autopilot retains bounded enemies and genuine combat kills")
	check(sampled_valid and game.save_notice.is_empty(), "autopilot checkpoints remain valid throughout real play")
	check(game.profile.run.is_empty(), "autopilot victory clears checkpoint")
	var credits: int = game.profile.credits
	var score: int = game.score
	Runtime.complete(game)
	game.finish_game(true)
	check(game.profile.credits == credits and game.profile.campaign_wins == 1 and game.score == score, "real-tick terminal completion cannot duplicate rewards")
	var persisted := Progression.new()
	persisted.load_data()
	check(persisted.campaign_wins == 1 and persisted.credits == credits and persisted.run.is_empty(), "real-tick campaign victory persists on disk")
	print("Autopilot fixture (not balance): %.2fs simulated, %d kills, %d upgrade choices, level %d, peak %d enemies, state=%s" % [simulated,game.kills,choices,game.level,peak_enemies,game.state])

func check_fresh_process(description: String) -> void:
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/test_campaign.gd","--","--checkpoint-check"]),output,true)
	check(status == 0,"fresh process restores " + description)
	for line in output: print(str(line).strip_edges())

func _read_checkpoint_in_fresh_process() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	check(game.state == "menu" and not game.profile.run.is_empty(),"fresh process discovers campaign checkpoint")
	var saved: Dictionary = game.profile.run.duplicate(true)
	check(saved.has("campaign") and game.profile.last_error.is_empty(),"fresh process accepts campaign schema")
	game._launch()
	for field in game.RUN_FIELDS:
		if field == "invulnerable": continue
		check(game.get(field) == saved[field],"fresh process restores field " + field)
	check(game.campaign == saved.campaign,"fresh process restores every campaign field, including vectors and claims")
	var expected_state: String = "intermission" if saved.campaign.intermission else ("upgrade" if saved.state == "upgrade" else "playing")
	check(game.state == expected_state,"fresh process preserves pending choice state")
	check(game.previous_player == game.player,"fresh process resets swept-collision origin")
	var before: float = game.campaign.total_time
	if expected_state in ["intermission","upgrade"]:
		game._process(5.0)
		near(game.campaign.total_time,before,"fresh process pending choice keeps world frozen")
	print("Fresh-process campaign checkpoint: %d checks, %d failures" % [checks,failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)

func _test_populated_campaign_checkpoints() -> void:
	reset(2,2)
	game.campaign.claimed = [0,1]
	game.campaign.relics = [0,2]
	game.campaign.total_time = 380.5
	game.campaign.sector_time = 65.25
	game.campaign.objective = 7
	game.campaign.objective_clock = 0.15
	game.player = Vector2(470,380)
	game.overdrive = 3
	game.recovery = 2
	Runtime.add_hazard(game,Vector2(600,300),98.0,1.2,3.5)
	game.enemies.append(enemy(Vector2(300,300),6.0))
	game._spawn_boss()
	game.gems.append({"p":Vector2(510,400),"phase":0.25,"value":2})
	game.bolts.append({"p":Vector2(500,350),"v":Vector2(690,0),"life":0.7})
	game._on_focus_lost()
	check(game.state == "paused" and game.save_notice.is_empty(), "populated Crown checkpoint saves")
	check_fresh_process("populated Crown combat checkpoint")
	var expected: Dictionary = game.profile.run.duplicate(true)
	game.campaign.hazards[0].warning = 0.1
	game.campaign.claimed.append(2)
	check(game.profile.run.campaign.hazards[0].warning == 1.2 and game.profile.run.campaign.claimed == [0,1], "campaign checkpoint deeply isolates live hazards and claims")
	game.profile.run = expected
	game.continue_run()
	check(game.campaign.claimed == [0,1] and game.campaign.hazards[0].warning == 1.2, "continue restores hazards and claims without live mutation leakage")
	game.state = "upgrade"
	game.save_run()
	check_fresh_process("campaign pending level-up choice")
	restore_from_disk()
	check(game.state == "upgrade", "campaign pending upgrade survives continue")
	var phase: int = game.phase_engine
	key(KEY_2)
	check(game.state == "playing" and game.phase_engine == phase+1, "continued upgrade is selectable exactly once")
	game.choose_upgrade(1)
	check(game.phase_engine == phase+1, "continued upgrade rejects repeat application")

func _test_normal_damage_smoke() -> void:
	# A deliberately simple pilot flies to the first beacon, then stays there.
	# There is no forced protection, damage, time, spawn, or resource modification.
	# This checks normal collision/death integration, not survival balance or AI skill.
	release_controls()
	game.profile = Progression.new()
	game.best_score = 0
	game.rng.seed = 7654321
	game.start_campaign(0)
	var simulated := 0.0
	var damage_events := 0
	var saw_hazard := false
	var saw_enemies := false
	var checkpoint_valid := true
	while simulated < 45.0 and game.state not in ["won","lost"]:
		if game.state == "upgrade":
			game.choose_upgrade(0)
			continue
		if game.state != "playing": break
		steer_toward(Vector2(230,260),10.0)
		var hull: int = game.health
		game._tick(DT)
		game._tick_effects(DT)
		simulated += DT
		if game.health < hull: damage_events += 1
		saw_hazard = saw_hazard or not game.campaign.hazards.is_empty()
		saw_enemies = saw_enemies or not game.enemies.is_empty()
		checkpoint_valid = checkpoint_valid and game.save_notice.is_empty()
	release_controls()
	check(saw_enemies and game.kills > 0,"ordinary-damage smoke generates enemies and normal projectile kills")
	check(saw_hazard and damage_events > 0,"ordinary-damage smoke experiences real telegraphed hazards and hull damage")
	check(game.campaign.objective >= 1,"ordinary-damage smoke collects beacon by navigation")
	check(checkpoint_valid and game.profile.valid_game_run(game.profile.run),"ordinary-damage smoke checkpoints stay valid")
	check(game.state in ["playing","lost"],"ordinary-damage smoke ends in coherent playing or loss state")
	if game.state == "lost":
		check(game.health == 0 and game.profile.run.is_empty(),"ordinary-damage smoke death clears suspended run")
	print("Ordinary-damage smoke (not balance): %.2fs simulated, %d kills, %d damage events, hull %d/%d, state=%s" % [simulated,game.kills,damage_events,game.health,game.max_health,game.state])
