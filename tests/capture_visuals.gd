extends SceneTree
## Native renderer QA fixtures. Run only with isolated XDG_DATA_HOME.
## The evolved/boss fixtures set progression deliberately; no claim of human play.
var game: Node
func _initialize() -> void:
	call_deferred("run")
func capture(label: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("NEON_DRIFT_CAPTURE_DIR")
	if output.is_empty():
		output = "user://"
	get_root().get_texture().get_image().save_png(output.path_join("neon-drift-"+label+".png"))
func run() -> void:
	if OS.get_environment("NEON_DRIFT_TEST_SAVE") != "1":
		printerr("Use a disposable XDG_DATA_HOME and set NEON_DRIFT_TEST_SAVE=1 for capture fixtures.")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.muted = true
	root.size = Vector2i(1280,720)
	await capture("title-visual")
	game.state = "hangar"
	await capture("hangar-visual")
	game.start_game()
	game.rng.seed = 734
	game.fx_rng.seed = 541
	game.level = 18
	game.overdrive = 5
	game.recovery = 4
	game.phase_engine = 3
	game.health = 5
	game.elapsed = 543.0
	game.player = Vector2(690,410)
	game.facing = Vector2(0.8,-0.6)
	game._spawn_boss()
	game.enemies[0].p = Vector2(860,300)
	game.enemies[0].warning = 0
	game.rings.clear()
	for i in range(30):
		game._spawn_enemy()
		var e: Dictionary = game.enemies.back()
		e.p = Vector2(100+game.rng.randf()*1090,220+game.rng.randf()*340)
		e.warning = 0
		if e.p.distance_to(game.player) < 95:
			e.p.x -= 150
	for i in range(25):
		game.gems.append({"p":Vector2(290+i*23,460+sin(i)*72),"phase":float(i),"value":1})
	game.invulnerable = 15
	game.next_level = 10000
	game.pulse_timer = 1.0
	game.boss_cinematic = 0
	for frame in range(20):
		game._tick(1.0/60)
		game._tick_effects(1.0/60)
		game.ambient_time += 1.0/60
	game._burst(Vector2(390,345),game.CORAL,36,210)
	game._ring(Vector2(390,345),game.CORAL,70,0.55)
	game._burst(Vector2(980,470),game.GOLD,30,220)
	game._ring(Vector2(980,470),game.GOLD,60,0.5)
	game._ring(game.player,game.BLUE,170,0.6)
	game._tick_effects(0.14)
	game.invulnerable = 0
	game.toast_timer = 0
	await capture("gameplay-visual")
	game.reduced_motion = true
	await capture("calm-visual")
	game.reduced_motion = false
	game.state = "upgrade"
	await capture("upgrade-visual")
	game.state = "paused"
	await capture("pause-visual")
	game.state = "playing"
	game._destroy_enemy(0)
	game._tick_effects(0.12)
	await capture("boss-defeat-visual")
	print("Native visual fixtures captured")
	quit()
