extends Node2D
## NEON DRIFT. All art is drawn procedurally; no network or external dependencies.

const SIZE := Vector2(1280, 720)
const ARENA := Rect2(32, 108, 1216, 532)
const SURVIVAL_TIME := 600.0
const BOSS_TIME := 540.0
const Progression = preload("res://progression.gd")
const Campaign = preload("res://campaign.gd")
const CampaignRuntime = preload("res://campaign_runtime.gd")
const CampaignUI = preload("res://campaign_ui.gd")
const I18n = preload("res://i18n.gd")
var campaign: Dictionary = {}
var map_sector := 0
var evolution_clock := 0.0
const BG := Color("080e1c")
const PANEL := Color("101b2d")
const INK := Color("e9f3ff")
const MUTED := Color("70869e")
const MINT := Color("64ffda")
const BLUE := Color("7b9dff")
const CORAL := Color("ff687d")
const GOLD := Color("ffcc7a")
const MAIN_BUTTON := Rect2(78, 465, 332, 60)
const RETRY_BUTTON := Rect2(468, 424, 344, 56)
const MENU_BUTTON := Rect2(468, 496, 344, 44)
const PAUSE_BUTTON := Rect2(1184, 24, 60, 46)

# Cosmetic budgets do not affect enemies, collision, or saved progression.
const PARTICLE_LIMIT := 720
const RING_LIMIT := 32
const TRAIL_LIMIT := 40
var boss_cinematic := 0.0
var boss_cinematic_pos := Vector2.ZERO
var boss_cinematic_color := CORAL
var profile = Progression.new()
var max_health := 5
var damage_bonus := 0.0
var magnet_bonus := 0.0
var run_weapon := 0
var earned_credits := 0
var boss_spawned := false
var boss_defeated := false
var endless := false
var pulse_timer := 6.0
var autosave_timer := 5.0
var save_notice := ""
const RUN_FIELDS := ["elapsed", "player", "facing", "health", "max_health", "score", "kills", "level", "energy", "next_level", "dash_left", "dash_cooldown", "invulnerable", "fire_timer", "spawn_timer", "wave", "overdrive", "phase_engine", "recovery", "damage_bonus", "magnet_bonus", "run_weapon", "earned_credits", "boss_spawned", "boss_defeated", "endless", "pulse_timer", "enemies", "bolts", "gems"]

var ui_font: Font = preload("res://assets/ui.ttf")
var title_font: Font = preload("res://assets/title.ttf")
var state := "menu"
var ambient_time := 0.0
var elapsed := 0.0
var player := Vector2(640, 374)
var facing := Vector2.RIGHT
var health := 5
var score := 0
var best_score := 0
var kills := 0
var level := 1
var energy := 0
var next_level := 5
var dash_left := 0.0
var dash_cooldown := 0.0
var invulnerable := 0.0
var fire_timer := 0.0
var spawn_timer := 0.4
var wave := 1
var toast := ""
var toast_timer := 0.0
var screen_flash := 0.0
var shake := 0.0
var muted := false
var reduced_motion := false
var overdrive := 0
var phase_engine := 0
var recovery := 0
var previous_player := Vector2.ZERO
var enemies: Array[Dictionary] = []
var bolts: Array[Dictionary] = []
var gems: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var trails: Array[Dictionary] = []
var stars: Array[Vector3] = []
var glow_texture: GradientTexture2D
var fx_rng := RandomNumberGenerator.new()
var rng := RandomNumberGenerator.new()
var sounds: Dictionary = {}
var audio_pool: Array[AudioStreamPlayer] = []
var audio_index := 0

func _ready() -> void:
	rng.randomize()
	fx_rng.randomize()
	for i in range(75):
		stars.append(Vector3(rng.randf_range(0,1280), rng.randf_range(0,720), rng.randf()))
	glow_texture = GradientTexture2D.new()
	glow_texture.width = 128
	glow_texture.height = 128
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5,0.5)
	glow_texture.fill_to = Vector2(1.0,0.5)
	var glow_gradient := Gradient.new()
	glow_gradient.offsets = PackedFloat32Array([0.0,0.18,0.5,1.0])
	glow_gradient.colors = PackedColorArray([Color(1,1,1,0.35),Color(1,1,1,0.19),Color(1,1,1,0.045),Color(1,1,1,0)])
	glow_texture.gradient = glow_gradient
	_setup_inputs()
	_setup_audio()
	I18n.install_fonts(ui_font, title_font)
	I18n.load_settings()
	profile.load_data()
	best_score = profile.best
	save_notice = profile.last_error
	get_window().focus_exited.connect(_on_focus_lost)
	queue_redraw()

func _setup_inputs() -> void:
	var bindings := {"left": [KEY_A,KEY_LEFT], "right": [KEY_D,KEY_RIGHT], "up": [KEY_W,KEY_UP], "down": [KEY_S,KEY_DOWN], "dash": [KEY_SPACE], "pause_game": [KEY_ESCAPE, KEY_P]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)

func _setup_audio() -> void:
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -16.0
		add_child(voice)
		audio_pool.append(voice)
	sounds["shoot"] = _tone(710, 360, 0.055, 0.15)
	sounds["hit"] = _tone(160, 65, 0.11, 0.45)
	sounds["gem"] = _tone(880, 1250, 0.09, 0.2)
	sounds["dash"] = _tone(260, 820, 0.16, 0.25)
	sounds["upgrade"] = _tone(460, 1600, 0.34, 0.3)
	sounds["finish"] = _tone(350, 1000, 0.65, 0.3)

func _tone(start_hz: float, end_hz: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var data := PackedByteArray()
	var count := int(duration * 22050)
	data.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var progress := float(i) / count
		phase += TAU * lerpf(start_hz, end_hz, progress) / 22050.0
		var envelope := sin(PI * progress) * (1.0 - progress)
		var sample := int(sin(phase) * envelope * amplitude * 32767)
		data.encode_s16(i * 2, sample)
	sound.data = data
	return sound

func _sound(key: String) -> void:
	if muted or audio_pool.is_empty():
		return
	var voice := audio_pool[audio_index % audio_pool.size()]
	audio_index += 1
	voice.stream = sounds[key]
	voice.play()

func _on_focus_lost() -> void:
	if state == "playing":
		state = "paused"
		save_run()

func start_game(persist: bool = true) -> void:
	campaign = {}
	evolution_clock = 0.0
	state = "playing"
	elapsed = 0.0
	player = ARENA.get_center()
	previous_player = player
	facing = Vector2.RIGHT
	max_health = 5 + profile.hull_rank
	health = max_health
	damage_bonus = profile.damage_rank * 0.2
	magnet_bonus = profile.magnet_rank * 20.0
	run_weapon = profile.weapon
	earned_credits = 0
	boss_spawned = false
	boss_defeated = false
	endless = false
	pulse_timer = 6.0
	autosave_timer = 5.0
	score = 0
	kills = 0
	level = 1
	overdrive = 0
	phase_engine = 0
	recovery = 0
	energy = 0
	next_level = 5
	dash_left = 0.0
	dash_cooldown = 0.0
	invulnerable = 1.5
	fire_timer = 0.0
	spawn_timer = 0.6
	wave = 1
	shake = 0.0
	screen_flash = 0.0
	enemies.clear()
	bolts.clear()
	gems.clear()
	particles.clear()
	boss_cinematic = 0.0
	rings.clear()
	trails.clear()
	toast = I18n.t("STAY MOVING.  COLLECT ENERGY.")
	toast_timer = 3.0
	_ring(player, MINT, 120, 0.65)
	if persist: save_run()

func save_run() -> void:
	if state not in ["playing", "paused", "upgrade", "intermission"]:
		return
	var snapshot := {"state": "upgrade" if state == "upgrade" else "paused"}
	for field in RUN_FIELDS:
		snapshot[field] = get(field)
	if not campaign.is_empty():
		snapshot["campaign"] = campaign.duplicate(true)
	profile.run = snapshot.duplicate(true)
	profile.best = best_score
	save_notice = "" if profile.save_data() else "SAVE FAILED: progress is only in this session"

func continue_run() -> void:
	if profile.run.is_empty():
		return
	if not profile.valid_game_run(profile.run):
		save_notice = "Saved run cannot be read. Start a new expedition."
		return
	var snapshot: Dictionary = profile.run.duplicate(true)
	for field in RUN_FIELDS:
		if not profile.run.has(field):
			save_notice = "Saved run cannot be read. Start a new expedition."
			return
	for field in RUN_FIELDS:
		set(field, snapshot[field])
	campaign = snapshot.get("campaign", {}).duplicate(true)
	previous_player = player
	particles.clear()
	boss_cinematic = 0.0
	rings.clear()
	trails.clear()
	state = "upgrade" if profile.run.state == "upgrade" else "playing"
	if campaign.get("intermission",false):
		state = "intermission"
	invulnerable = maxf(invulnerable, 1.5)
	toast = I18n.t("EXPEDITION RESTORED  /  YOUR BUILD IS INTACT")
	toast_timer = 3.0

func _go_home() -> void:
	save_run()
	state = "menu"

func _launch() -> void:
	if profile.run.is_empty():
		state = "sector_map"
	else:
		continue_run()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key == KEY_V:
			reduced_motion = not reduced_motion
			if reduced_motion and particles.size() > 120:
				particles.resize(120)
		if key == KEY_M:
			muted = not muted
		if key == KEY_L:
			I18n.toggle()
		if key == KEY_F12:
			_save_screenshot()
		if state == "sector_map":
			if key in [KEY_1,KEY_2,KEY_3] and key-KEY_1 <= profile.sector_unlocked:
				map_sector = key-KEY_1
			elif key == KEY_S:
				_cycle_ship()
			elif key == KEY_ENTER:
				_request_campaign()
			elif key == KEY_J:
				state = "journal"
			elif key == KEY_ESCAPE:
				state = "menu"
			return
		if state == "journal":
			if key in [KEY_ESCAPE,KEY_ENTER]: state = "sector_map"
			return
		if state == "intermission":
			if key in [KEY_1,KEY_2,KEY_3]: CampaignRuntime.choose_relic(self,key-KEY_1)
			elif key == KEY_ESCAPE: _go_home()
			return
		if state == "upgrade" and key in [KEY_1, KEY_2, KEY_3]:
			choose_upgrade(key - KEY_1)
		elif state == "menu":
			if key == KEY_ENTER:
				_launch()
			elif key == KEY_C:
				state = "sector_map"
			elif key == KEY_H:
				state = "hangar"
			elif key == KEY_N:
				state = "sector_map"
		elif state == "hangar":
			if key in [KEY_1, KEY_2, KEY_3]:
				_buy(key - KEY_1)
			elif key == KEY_W:
				_cycle_weapon()
			elif key in [KEY_ESCAPE, KEY_ENTER]:
				state = "menu"
		elif state == "confirm_new":
			if key == KEY_ENTER:
				start_campaign(map_sector)
			elif key == KEY_ESCAPE:
				state = "menu"
		elif state == "paused" and key == KEY_ENTER:
			state = "playing"
		elif state in ["lost", "won"]:
			if key == KEY_ENTER or key == KEY_R:
				_retry_run()
			elif key == KEY_E and state == "won":
				endless = true
				state = "playing"
				health = max_health
				save_run()
		if event.is_action_pressed("pause_game"):
			if state == "playing":
				state = "paused"
				save_run()
			elif state == "paused":
				state = "playing"
			elif state in ["lost", "won"]:
				_go_home()
		if event.is_action_pressed("dash") and state == "playing":
			try_dash()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cursor := get_global_mouse_position()
		if state == "sector_map":
			for i in range(3):
				if Rect2(80+i*400,190,360,210).has_point(cursor) and i <= profile.sector_unlocked: map_sector = i
			if Rect2(80,430,720,58).has_point(cursor): _cycle_ship()
			elif Rect2(850,430,350,58).has_point(cursor): _request_campaign()
			elif Rect2(80,520,340,48).has_point(cursor): state = "journal"
			elif Rect2(860,520,340,48).has_point(cursor): state = "menu"
			return
		if state == "journal":
			if Rect2(468,589,344,48).has_point(cursor): state = "sector_map"
			return
		if state == "intermission":
			for i in range(3):
				if Rect2(178+i*314,285,296,190).has_point(cursor): CampaignRuntime.choose_relic(self,i)
			if Rect2(468,550,344,44).has_point(cursor): _go_home()
			return
		if state == "upgrade":
			for i in range(3):
				if Rect2(178 + i * 314, 294, 296, 200).has_point(cursor):
					choose_upgrade(i)
		elif state == "menu":
			if MAIN_BUTTON.has_point(cursor):
				_launch()
			elif Rect2(78,536,332,44).has_point(cursor):
				state = "hangar"
			elif Rect2(78,586,332,36).has_point(cursor):
				state = "sector_map"
		elif state == "hangar":
			for i in range(3):
				if Rect2(178+i*314,250,296,170).has_point(cursor):
					_buy(i)
			if Rect2(390,447,500,48).has_point(cursor):
				_cycle_weapon()
			elif Rect2(468,551,344,48).has_point(cursor):
				state = "menu"
		elif state in ["paused", "lost", "won", "confirm_new"]:
			if RETRY_BUTTON.has_point(cursor):
				if state == "paused":
					state = "playing"
				elif state == "confirm_new":
					start_campaign(map_sector)
				else:
					_retry_run()
			elif MENU_BUTTON.has_point(cursor):
				_go_home()
			elif state == "won" and Rect2(468,550,344,42).has_point(cursor):
				endless = true
				state = "playing"
				health = max_health
				save_run()
		elif state == "playing" and PAUSE_BUTTON.has_point(cursor):
			state = "paused"
			save_run()

func _buy(index: int) -> void:
	profile.buy_upgrade(["hull_rank", "damage_rank", "magnet_rank"][index])
	save_notice = profile.last_error

func _cycle_weapon() -> void:
	for offset in range(1,4):
		var candidate: int = (profile.weapon + offset) % 3
		if profile.weapon_unlocked(candidate):
			var previous_weapon: int = profile.weapon
			profile.weapon = candidate
			if not profile.save_data():
				profile.weapon = previous_weapon
			save_notice = profile.last_error
			return

func try_dash() -> bool:
	if dash_cooldown > 0.0 or state != "playing":
		return false
	dash_left = 0.17
	dash_cooldown = maxf(0.85, 1.55 - (level - 1) * 0.05 - phase_engine * 0.16)
	if CampaignRuntime.active(self): dash_cooldown *= Campaign.ship(campaign.ship).dash_mult
	invulnerable = maxf(invulnerable, 0.24)
	_ring(player, MINT, 50, 0.3)
	_sound("dash")
	return true

func _process(delta: float) -> void:
	ambient_time += delta
	if state == "playing":
		_tick(minf(delta, 0.05))
	if state not in ["paused", "upgrade", "intermission"]:
		_tick_effects(delta)
	queue_redraw()

func _tick(delta: float) -> void:
	elapsed += delta
	if CampaignRuntime.active(self):
		CampaignRuntime.tick(self,delta)
		if state != "playing": return
	if not CampaignRuntime.active(self) and elapsed >= SURVIVAL_TIME and boss_defeated and not endless:
		finish_game(true)
		return
	autosave_timer -= delta
	if autosave_timer <= 0:
		save_run()
		autosave_timer = 5.0
	if not CampaignRuntime.active(self) and elapsed >= BOSS_TIME and not boss_spawned:
		_spawn_boss()
	var new_wave := int(elapsed / 60.0) + 1
	if new_wave != wave:
		wave = new_wave
		toast = I18n.f("WAVE %02d  /  SIGNAL INTENSIFYING", wave)
		toast_timer = 2.4
		_ring(player, BLUE, 260, 0.8)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	dash_left = maxf(0, dash_left - delta)
	invulnerable = maxf(0, invulnerable - delta)
	toast_timer = maxf(0, toast_timer - delta)
	screen_flash = maxf(0, screen_flash - delta * 2.8)
	shake = maxf(0, shake - delta * 30)
	var direction := Input.get_vector("left", "right", "up", "down")
	if direction.length_squared() > 0:
		facing = direction.normalized()
	previous_player = player
	var speed := minf(390.0, 235.0 + level * 4.0 + phase_engine * 15.0)
	if CampaignRuntime.active(self): speed *= Campaign.ship(campaign.ship).speed_mult
	if dash_left > 0:
		player += facing * 860.0 * delta
		if trails.size() >= TRAIL_LIMIT:
			trails.pop_front()
		trails.append({"p": player, "angle": facing.angle(), "life": 0.27, "max": 0.27})
	else:
		player += direction * speed * delta
		if direction.length_squared() > 0 and rng.randf() < 0.55:
			_particle(player - facing * 13, -facing * 30, MINT, 0.25, 2.2)
	player = player.clamp(ARENA.position + Vector2(18,18), ARENA.end - Vector2(18,18))
	spawn_timer -= delta
	if spawn_timer <= 0:
		if enemies.size() < 95:
			_spawn_enemy()
		spawn_timer = maxf(0.24, 0.95 - elapsed * 0.0012)
		if CampaignRuntime.active(self): spawn_timer /= Campaign.sector(campaign.sector).spawn_scale
	fire_timer -= delta
	if fire_timer <= 0 and not enemies.is_empty():
		_fire()
		fire_timer = maxf(0.12, 0.48 - level * 0.018 - overdrive * 0.035)
	if CampaignRuntime.active(self):
		evolution_clock -= delta
		if evolution_clock <= 0 and Campaign.evolution(run_weapon,overdrive,phase_engine,recovery) == "NOVA ARRAY":
			evolution_clock = 2.5
			_ring(player,MINT,230,0.65)
			for j in range(enemies.size()-1,-1,-1):
				if enemies[j].warning <= 0 and enemies[j].p.distance_to(player) < 230:
					enemies[j].hp -= _bolt_damage()*2.0
					if enemies[j].hp <= 0: _destroy_enemy(j)
	_move_enemies(delta)
	if state != "playing":
		return
	_move_bolts(delta)
	_collect_gems(delta)
	if state == "playing" and level >= 8:
		pulse_timer -= delta
		if pulse_timer <= 0:
			pulse_timer = maxf(2.5, 6.0 - recovery * 0.25)
			_ring(player, BLUE, 170 + recovery * 12, 0.6)
			for i in range(enemies.size()-1,-1,-1):
				if enemies[i].warning <= 0 and enemies[i].p.distance_to(player) < 170 + recovery * 12:
					enemies[i].hp -= 3 + recovery
					if enemies[i].hp <= 0:
						_destroy_enemy(i)

func _spawn_enemy() -> void:
	var edge := rng.randi_range(0,3)
	var pos: Vector2
	match edge:
		0: pos = Vector2(ARENA.position.x + 18, rng.randf_range(140,608))
		1: pos = Vector2(ARENA.end.x - 18, rng.randf_range(140,608))
		2: pos = Vector2(rng.randf_range(70,1210), ARENA.position.y + 18)
		_: pos = Vector2(rng.randf_range(70,1210), ARENA.end.y - 18)
	if pos.distance_to(player) < 180:
		pos = ARENA.get_center() * 2.0 - pos
	var kind := 0
	if elapsed > 60 and rng.randf() < 0.28:
		kind = 1
	if elapsed > 120 and rng.randf() < 0.24:
		kind = 2
	var hp := 1.0 if kind == 0 else (2.0 if kind == 1 else 4.0)
	hp *= 1.0 + floorf(elapsed / 120.0) * 0.6
	if CampaignRuntime.active(self):
		hp *= Campaign.sector(campaign.sector).enemy_health_scale
		if campaign.sector == 1 and rng.randf() < 0.35: kind = 1
		if campaign.sector == 2 and rng.randf() < 0.3: kind = 2
	enemies.append({"p": pos, "kind": kind, "hp": hp, "max_hp": hp, "age": 0.0, "warning": 0.7, "phase": rng.randf() * TAU, "flash": 0.0, "dir": Vector2.ZERO})

func _move_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		e.age += delta
		e.flash = maxf(0, e.flash - delta * 5)
		if e.warning > 0:
			e.warning -= delta
			continue
		var to_player: Vector2 = player - e.p
		var direction := to_player.normalized()
		var speed := 78.0 + minf(elapsed, 900) * 0.08
		if e.kind == 1:
			# Dashers show a locked attack lane before lunging. They never home during a lunge.
			if not e.has("attack_phase"):
				e.attack_phase = "seek"
				e.attack_timer = 1.4
				e.locked_dir = direction
			e.attack_timer -= delta
			if e.attack_timer <= 0:
				if e.attack_phase == "seek":
					e.attack_phase = "windup"
					e.attack_timer = 0.65
					e.locked_dir = direction
				elif e.attack_phase == "windup":
					e.attack_phase = "burst"
					e.attack_timer = 0.3
				else:
					e.attack_phase = "seek"
					e.attack_timer = 2.1
			if e.attack_phase == "windup":
				direction = e.locked_dir
				speed = 0.0
			elif e.attack_phase == "burst":
				direction = e.locked_dir
				speed = 430.0
			else:
				speed = 90.0
		elif e.kind == 2:
			speed = 57.0 + minf(elapsed,900) * 0.04
		elif e.kind == 3:
			speed = Campaign.sector(campaign.sector).boss_speed if CampaignRuntime.active(self) else 48.0
			e.attack_timer -= delta
			if e.attack_timer <= 0:
				e.attack_timer = 5.0
				if CampaignRuntime.active(self):
					e.attack_timer = Campaign.sector(campaign.sector).boss_fire_interval
					CampaignRuntime.boss_attack(self,e)
				for reinforcement in range(4):
					if enemies.size() < 95:
						_spawn_enemy()
			e.dash_hit = maxf(0.0, e.dash_hit - delta)
		if CampaignRuntime.active(self): speed *= Campaign.sector(campaign.sector).enemy_speed_scale
		e.dir = direction
		e.p += direction * speed * delta
		var radius := 38.0 if e.kind == 3 else (13.0 if e.kind != 2 else 21.0)
		var collision_point: Vector2 = Geometry2D.get_closest_point_to_segment(e.p, previous_player, player) if dash_left > 0 else player
		if e.p.distance_to(collision_point) < radius + 12:
			if dash_left > 0:
				if e.kind != 3:
					_destroy_enemy(i, true)
				elif e.dash_hit <= 0:
					e.hp -= 12.0 + phase_engine * 3.0
					e.dash_hit = 0.5
					e.flash = 1.0
					if e.hp <= 0:
						_destroy_enemy(i, true)
			elif invulnerable <= 0:
				_damage_player()
				e.p += direction * -45
				if state != "playing":
					return

func _fire() -> void:
	var closest := INF
	var target := player + facing * 100
	var found := false
	for enemy in enemies:
		if enemy.warning > 0:
			continue
		var distance: float = enemy.p.distance_squared_to(player)
		if distance < closest:
			closest = distance
			target = enemy.p
			found = true
	if not found:
		return
	var direction := (target - player).normalized()
	var count := mini(7, 1 + int(level / 3) + int(overdrive / 3) + (2 if run_weapon == 1 else 0))
	for i in range(count):
		var angle := (float(i) - (count - 1) * 0.5) * 0.16
		bolts.append({"p": player + direction * 18, "v": direction.rotated(angle) * 690, "life": 1.3})
	if CampaignRuntime.active(self):
		var evolution: String = Campaign.evolution(run_weapon,overdrive,phase_engine,recovery)
		if evolution == "STARWEAVE":
			for i in range(8):
				bolts.append({"p":player,"v":Vector2.RIGHT.rotated(i*TAU/8+elapsed)*600,"life":0.7})
		elif evolution == "VOID LANCE":
			var end := player + direction * 700
			_ring(target,GOLD,45,0.25)
			for j in range(enemies.size()-1,-1,-1):
				var enemy: Dictionary = enemies[j]
				if enemy.warning <= 0 and Geometry2D.get_closest_point_to_segment(enemy.p,player,end).distance_to(enemy.p) < 24:
					enemy.hp -= _bolt_damage()*0.65
					enemy.flash = 1.0
					if enemy.hp <= 0: _destroy_enemy(j)
	_sound("shoot")

func _move_bolts(delta: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b := bolts[i]
		var previous: Vector2 = b.p
		b.p += b.v * delta
		b.life -= delta
		var used := false
		for j in range(enemies.size() - 1, -1, -1):
			var e := enemies[j]
			if e.warning > 0:
				continue
			var radius := 43.0 if e.kind == 3 else (18.0 if e.kind != 2 else 26.0)
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(e.p, previous, b.p)
			if closest.distance_to(e.p) < radius:
				e.hp -= _bolt_damage()
				e.flash = 1.0
				_burst(b.p, MINT, 4, 65)
				if e.hp <= 0:
					_destroy_enemy(j)
				used = true
				break
		if used or b.life <= 0 or not ARENA.grow(25).has_point(b.p):
			bolts.remove_at(i)

func _destroy_enemy(index: int, by_dash: bool = false) -> void:
	var e := enemies[index]
	var color := CORAL if e.kind != 1 else GOLD
	_burst(e.p, color, 12, 155)
	_ring(e.p, color, 34, 0.3)
	if e.kind == 3:
		boss_cinematic = 2.4
		boss_cinematic_pos = e.p
		boss_cinematic_color = MINT
		_burst(e.p, GOLD, 120, 390)
		_burst(e.p, BLUE, 100, 270)
		for blast in range(4):
			_ring(e.p, MINT if blast % 2 == 0 else GOLD, 110 + blast * 95, 0.6 + blast * 0.35)
		shake = 12.0
		boss_defeated = true
		profile.credits += 50
		earned_credits += 50
		toast = I18n.t("BOSS DEFEATED / COMPLETE YOUR OBJECTIVE" if CampaignRuntime.active(self) else "WARDEN DEFEATED  /  +50 PERMANENT CORES")
		toast_timer = 4.0
	if gems.size() >= 512:
		gems[0].value += 2 if e.kind == 2 else 1
	else:
		gems.append({"p": e.p, "phase": rng.randf() * TAU, "value": 2 if e.kind == 2 else 1})
	score += (30 if e.kind == 2 else 10) + (15 if by_dash else 0)
	kills += 1
	profile.total_kills += 1
	if profile.total_kills >= 1000: profile.award_achievement("veteran",35)
	if kills % 5 == 0:
		profile.credits += 1
		earned_credits += 1
	if profile.total_kills in [100, 300]:
		toast = I18n.t("PERMANENT WEAPON UNLOCKED  /  VISIT THE HANGAR")
		toast_timer = 4.0
	enemies.remove_at(index)
	if by_dash:
		_sound("hit")

func _collect_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var g := gems[i]
		var distance: float = g.p.distance_to(player)
		if distance < 112 + mini(level,20) * 7 + recovery * 34 + magnet_bonus:
			g.p = g.p.move_toward(player, (240 + (120 - minf(distance,120)) * 5) * delta)
		if distance < 23:
			energy += g.value
			score += g.value * 5
			_burst(g.p, MINT, 5, 70)
			gems.remove_at(i)
			_sound("gem")
			if energy >= next_level:
				energy -= next_level
				level += 1
				next_level = 5 + level * 2
				health = mini(max_health, health + 1)
				toast = I18n.f("LEVEL %02d  /  FIREPOWER UP + 1 HULL", level)
				toast_timer = 2.4
				_ring(player, MINT, 155, 0.7)
				_sound("upgrade")
				state = "upgrade"
				save_run()
				break

func _damage_player() -> void:
	health -= 1
	invulnerable = 1.3
	screen_flash = 0.45
	shake = 8
	_burst(player, CORAL, 20, 190)
	_sound("hit")
	if health <= 0:
		finish_game(false)

func finish_game(victory: bool) -> void:
	if state != "playing":
		return
	state = "won" if victory else "lost"
	if victory:
		score += 500 + health * 100
		_sound("finish")
		_burst(player, MINT, 70, 320)
	best_score = maxi(best_score, score)
	profile.best = best_score
	profile.run = {}
	if victory:
		profile.credits += 50
		earned_credits += 50
	save_notice = "" if profile.save_data() else "SAVE FAILED: progress is only in this session"
	# Maintain the original best-score format for old builds.
	var legacy := ConfigFile.new()
	legacy.set_value("record", "best", best_score)
	legacy.save("user://record.cfg")

func _bolt_damage() -> float:
	return (1.0 + floorf(level / 5.0) + overdrive * 0.25 + damage_bonus) * (2.0 if run_weapon == 2 else 1.0) * (Campaign.ship(campaign.ship).damage_mult if CampaignRuntime.active(self) else 1.0)

func _spawn_boss() -> void:
	boss_spawned = true
	var pos := Vector2(640,150)
	if pos.distance_to(player) < 200:
		pos = Vector2(640,595)
	enemies.append({"p":pos,"kind":3,"hp":480.0,"max_hp":480.0,"age":0.0,"warning":2.0,"phase":0.0,"flash":0.0,"dir":Vector2.ZERO,"attack_timer":5.0,"dash_hit":0.0})
	if CampaignRuntime.active(self):
		enemies[-1].hp = Campaign.sector(campaign.sector).boss_hp
		enemies[-1].max_hp = enemies[-1].hp
	boss_cinematic = 2.0
	boss_cinematic_pos = pos
	boss_cinematic_color = CORAL
	_ring(pos, CORAL, 230, 1.8)
	_ring(pos, GOLD, 150, 1.2)
	toast = I18n.f("%s / BREAK THE SIGNAL", I18n.t(Campaign.sector(campaign.sector).boss_name)) if CampaignRuntime.active(self) else I18n.t("THE SIGNAL WARDEN  /  DEFEAT IT TO EXTRACT")
	toast_timer = 4.0

func _particle(pos: Vector2, velocity: Vector2, color: Color, life: float, radius: float) -> void:
	if particles.size() >= (120 if reduced_motion else PARTICLE_LIMIT):
		return
	particles.append({"p": pos, "v": velocity, "c": color, "life": life, "max": life, "r": radius})

func _burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in range(count):
		var direction := Vector2.RIGHT.rotated(fx_rng.randf() * TAU)
		_particle(pos, direction * fx_rng.randf_range(speed * 0.25, speed), color, fx_rng.randf_range(0.2,0.6), fx_rng.randf_range(1.5,4))

func _ring(pos: Vector2, color: Color, radius: float, life: float) -> void:
	if rings.size() >= RING_LIMIT:
		rings.pop_front()
	rings.append({"p":pos, "c":color, "r":radius, "life":life, "max":life})

func _tick_effects(delta: float) -> void:
	boss_cinematic = maxf(0.0, boss_cinematic - delta)
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].p += particles[i].v * delta
		particles[i].v *= maxf(0.0, 1.0 - delta * 3.0)
		if particles[i].life <= 0:
			particles.remove_at(i)
	for i in range(rings.size() - 1,-1,-1):
		rings[i].life -= delta
		if rings[i].life <= 0:
			rings.remove_at(i)
	for i in range(trails.size() - 1,-1,-1):
		trails[i].life -= delta
		if trails[i].life <= 0:
			trails.remove_at(i)

func choose_upgrade(index: int) -> void:
	if state != "upgrade" or index < 0 or index > 2:
		return
	match index:
		0:
			overdrive += 1
			toast = I18n.t("OVERDRIVE  /  FASTER AUTO-FIRE")
		1:
			phase_engine += 1
			toast = I18n.t("PHASE ENGINE  /  FASTER MOVE + DASH")
		2:
			recovery += 1
			health = mini(max_health, health + 2)
			toast = I18n.t("RECOVERY  /  REPAIR + WIDER ENERGY MAGNET")
	invulnerable = maxf(invulnerable, 1.0)
	toast_timer = 2.2
	state = "playing"
	_sound("upgrade")
	_check_evolution()
	save_run()

func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("user://neon-drift.png")
	if result == OK:
		print("Screenshot: ", ProjectSettings.globalize_path("user://neon-drift.png"))

# ----- Drawing: deliberately lightweight, sharp vector art -----
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), BG)
	for star in stars:
		var alpha := 0.12 + 0.12 * sin(ambient_time * (0.4 + star.z) + star.x)
		draw_circle(Vector2(star.x,star.y), 0.7 + star.z, Color(0.45,0.65,0.9,alpha))
	if state == "menu":
		_draw_menu()
	elif state == "hangar":
		_draw_hangar()
	elif state == "sector_map":
		CampaignUI.draw_map(self)
	elif state == "journal":
		CampaignUI.draw_journal(self)
	else:
		_draw_game()
		if state == "intermission":
			CampaignUI.draw_intermission(self)
		elif state == "upgrade":
			_draw_upgrades()
		elif state in ["paused", "won", "lost", "confirm_new"]:
			_draw_overlay()


func _text(value: String, pos: Vector2, size: int, color: Color = INK, bold: bool = false) -> void:
	if I18n.recorder.is_valid(): I18n.recorder.call({"text": value, "pos": pos, "size": size, "bold": bold})
	draw_string(title_font if bold else ui_font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(value: String, y: float, size: int, color: Color = INK, bold: bool = false, x: float = 640) -> void:
	var font := title_font if bold else ui_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(x - width * 0.5,y), size,color,bold)

func _panel(rect: Rect2, fill: Color = PANEL, border: Color = Color("22344c"), radius: int = 12) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)

func _button(rect: Rect2, label: String, primary: bool = true) -> void:
	if I18n.recorder.is_valid(): I18n.recorder.call({"button": rect, "text": label})
	var hovered := rect.has_point(get_global_mouse_position())
	var fill := MINT if primary else PANEL
	if hovered:
		fill = fill.lightened(0.14)
	_panel(rect,fill, MINT if primary else Color("354860"),8)
	_center(label,rect.position.y + rect.size.y / 2 + 6, 18, BG if primary else INK,true,rect.get_center().x)

func _poly(pos: Vector2, radius: float, sides: int, angle: float, fill: Color, stroke: Color) -> void:
	var points := PackedVector2Array()
	for i in range(sides):
		points.append(pos + Vector2.RIGHT.rotated(angle + TAU * i / sides) * radius)
	draw_colored_polygon(points,fill)
	points.append(points[0])
	draw_polyline(points,stroke,2.0,true)

func _ship_tier() -> int:
	return clampi(int(level / 5), 0, 3)

func _glow(pos: Vector2, radius: float, color: Color, strength: float = 1.0) -> void:
	if reduced_motion or glow_texture == null:
		return
	draw_texture_rect(glow_texture,Rect2(pos-Vector2.ONE*radius*1.7,Vector2.ONE*radius*3.4),false,Color(color,strength))

func _ship(pos: Vector2, angle: float, color: Color = MINT, alpha: float = 1.0, scale_factor: float = 1.0) -> void:
	var tier := _ship_tier() if state != "menu" else 3
	_glow(pos,31 * scale_factor,color,alpha)
	var shapes := [PackedVector2Array([Vector2(23,0),Vector2(-15,-13),Vector2(-8,0),Vector2(-15,13)])]
	if tier >= 1:
		shapes.append(PackedVector2Array([Vector2(5,-8),Vector2(-10,-23),Vector2(-20,-22),Vector2(-11,-5)]))
		shapes.append(PackedVector2Array([Vector2(5,8),Vector2(-10,23),Vector2(-20,22),Vector2(-11,5)]))
	if tier >= 2:
		shapes.append(PackedVector2Array([Vector2(13,-9),Vector2(6,-25),Vector2(-9,-30),Vector2(-2,-10)]))
		shapes.append(PackedVector2Array([Vector2(13,9),Vector2(6,25),Vector2(-9,30),Vector2(-2,10)]))
	for shape in shapes:
		var points := PackedVector2Array()
		for point in shape:
			points.append(pos + point.rotated(angle) * scale_factor)
		draw_colored_polygon(points,Color("102d40") * Color(1,1,1,alpha))
		points.append(points[0])
		draw_polyline(points,Color(color,0.13 * alpha),7.0,true)
		draw_polyline(points,Color(color,alpha),1.6,true)
	var flame := 16.0 + (0.0 if reduced_motion else sin(ambient_time*37)*5)
	if dash_left > 0:
		flame = 50.0
	for engine in range(1 if tier == 0 else 2):
		var y := 0.0 if tier == 0 else (-16.0 if engine == 0 else 16.0)
		var nozzle := pos + Vector2(-14,y).rotated(angle)*scale_factor
		var tip := nozzle - Vector2.RIGHT.rotated(angle)*flame*scale_factor
		draw_line(nozzle,tip,Color(BLUE,0.15*alpha),10*scale_factor,true)
		draw_line(nozzle,tip,Color(color,0.75*alpha),3*scale_factor,true)
		draw_circle(nozzle,2.0*scale_factor,Color(INK,alpha))
	var cockpit := pos + Vector2(5,0).rotated(angle)*scale_factor
	_poly(cockpit,4*scale_factor,4,angle,Color(INK,alpha),Color(color,alpha))
	if tier == 3:
		for side in [-1,1]:
			var a := pos + Vector2(10,side*30).rotated(angle)*scale_factor
			var b := pos + Vector2(-5,side*30).rotated(angle)*scale_factor
			draw_line(a,b,Color(GOLD,alpha),2.0*scale_factor,true)

func _draw_atmosphere() -> void:
	if CampaignRuntime.active(self):
		var color := Color(Campaign.sector(campaign.sector).color)
		if campaign.sector == 1:
			for row in range(5):
				var y := 160.0+row*100
				draw_line(Vector2(80,y),Vector2(1200,y),Color(color,0.065),18,true)
				for column in range(8):
					_poly(Vector2(130+column*145,y),24,6,PI/6,Color(color,0.025),Color(color,0.12))
		elif campaign.sector == 2:
			for i in range(12):
				var angle := i*TAU/12+ambient_time*0.012
				var pos := ARENA.get_center()+Vector2.RIGHT.rotated(angle)*230
				_poly(pos,35,3,angle,Color(color,0.025),Color(color,0.12))
		else:
			for i in range(9):
				var pos := Vector2(100+i*128,270+sin(i*2.8)*100)
				_poly(pos,19,4,i*1.7,Color(color,0.02),Color(color,0.08))
	# Layered nebula glows, orbital debris and faint, parallax navigation lattice.
	for i in range(7):
		var pos := Vector2(160+i*170,310+sin(i*2.3)*160)
		pos += (player-ARENA.get_center()) * (-0.035 if i%2 == 0 else -0.015)
		_glow(pos,100,BLUE if i%2 == 0 else MINT,0.15)
	var center := ARENA.get_center() + (player-ARENA.get_center())*-0.035
	for radius in [100,180,255]:
		draw_arc(center,radius,0,TAU,96,Color(BLUE,0.065),1,true)
	for i in range(36):
		var a := i*TAU/36.0
		var p := center + Vector2.RIGHT.rotated(a)*255
		draw_line(p,p-Vector2.RIGHT.rotated(a)*(12 if i%3 == 0 else 5),Color(MINT,0.13),1,true)
	for star in stars:
		var p := Vector2(star.x,star.y) - (player-ARENA.get_center()) * star.z * 0.07
		if ARENA.grow(-15).has_point(p):
			draw_circle(p,0.5+star.z,Color(INK,0.08+star.z*0.14))
	for side in [0,1]:
		var x := 40.0 if side == 0 else 1240.0
		for i in range(12):
			draw_line(Vector2(x,155+i*36),Vector2(x,166+i*36),Color(MINT,0.24 if i%3 == 0 else 0.08),2)

func _draw_warden(e: Dictionary) -> void:
	var color := CORAL
	var pulse := 0.5 + 0.5*sin(e.age*3)
	_glow(e.p,64,color,2.0)
	for i in range(8):
		var angle: float = e.age*0.22 + i*TAU/8
		var p: Vector2 = e.p + Vector2.RIGHT.rotated(angle)*48
		_poly(p,11,4,angle,Color("27172f"),color)
		draw_line(e.p+Vector2.RIGHT.rotated(angle)*28,p,Color(color,0.5),2,true)
	_poly(e.p,35,8,-e.age*0.18,Color("201323").lerp(INK,e.flash*0.7),color)
	_poly(e.p,24,4,e.age*0.3,Color(color,0.2),GOLD)
	draw_circle(e.p,11+2*pulse,Color(color,0.4))
	_poly(e.p,9,4,-e.age,INK,GOLD)
	draw_arc(e.p,63,e.age*0.4,e.age*0.4+PI*1.5,48,Color(color,0.65),2,true)

func _draw_menu() -> void:
	_text(I18n.t("O R B I T A L   /   A R C A D E   0 1"),Vector2(80,78),13,MINT)
	_text("NEON",Vector2(76,224),100,Color(BLUE,0.25),true)
	_text("NEON",Vector2(74,222),100,INK,true)
	_text("DRIFT",Vector2(74,324),100,MINT,true)
	draw_line(Vector2(80,357),Vector2(140,357),MINT,3)
	_text(I18n.t("One pilot. An endless signal."),Vector2(80,398),21,INK)
	_text(I18n.t("Three sectors. Build a fleet. Break the Crown."),Vector2(80,432),16,MUTED)
	_button(MAIN_BUTTON,I18n.t("CONTINUE EXPEDITION" if not profile.run.is_empty() else "CAMPAIGN / ENTER"))
	_button(Rect2(78,536,332,44),I18n.f("HANGAR / %d CORES   [H]", profile.credits),false)
	_button(Rect2(78,586,332,36),I18n.t("SECTOR MAP / JOURNAL   [C]"),false)
	if best_score > 0:
		_text(I18n.f("PERSONAL BEST  /  %06d", best_score),Vector2(440,616),14,GOLD)
	# A schematic arena illustration, not a static screenshot.
	var center := Vector2(930,346)
	_glow(center,150,BLUE,2.0)
	_glow(center,95,MINT,1.5)
	for i in range(4):
		draw_circle(center,83.0 + i * 53,Color(0.19,0.33,0.44,0.3 - i * 0.04),false,1,true)
	draw_line(Vector2(666,346),Vector2(1198,346),Color("182a40"),1)
	draw_line(Vector2(930,87),Vector2(930,607),Color("182a40"),1)
	for i in range(24):
		var angle := TAU * i / 24.0
		var p := center + Vector2.RIGHT.rotated(angle) * 241
		draw_line(p,p + Vector2.RIGHT.rotated(angle) * (10 if i % 3 == 0 else 4),Color("314961"),1)
	for i in range(3):
		var pos := center - Vector2(28 + i * 23,-14 + i * 6)
		_ship(pos,-0.45,MINT,0.11 - i * 0.026,2)
	_ship(center,-0.45,MINT,1.0,3.2)
	_text(I18n.t("MK IV / ASCENDANT"),Vector2(835,520),13,MINT,true)
	for i in range(7):
		var angle := i * 1.6 + ambient_time * (0.075 if i % 2 == 0 else -0.06)
		var pos := center + Vector2.RIGHT.rotated(angle) * (150 + (i % 3) * 29)
		_poly(pos,14 if i % 3 == 0 else 10,4 if i % 3 == 0 else 3,angle,Color(CORAL,0.08),CORAL if i % 3 == 0 else GOLD)
	for i in range(3):
		var pos := center + Vector2(52 + i * 22,-25 - i * 10)
		draw_line(pos,pos + Vector2(10,-5),MINT,3,true)
	_panel(Rect2(738,581,388,54),Color("0c1727"),Color("203549"),6)
	_text("03",Vector2(760,617),22,MINT,true)
	_text(I18n.t("SECTORS"),Vector2(832,615),11,MUTED)
	_text("03",Vector2(926,617),22,INK,true)
	_text(I18n.t("SHIPS"),Vector2(969,615),11,MUTED)
	_text(I18n.t("Auto-save every 5s + on pause. Same browser/device only."),Vector2(79,644),11,MUTED)
	if not save_notice.is_empty():
		_text(I18n.notice(save_notice),Vector2(78,95),12,CORAL)
	_draw_footer()

func _draw_hangar() -> void:
	_glow(Vector2(640,126),220,BLUE,0.5)
	for side in [0,1]:
		var x := 100.0 if side == 0 else 1180.0
		draw_line(Vector2(x,260),Vector2(x,420),Color(MINT,0.2),1,true)
		for i in range(5):
			draw_line(Vector2(x-5,265+i*36),Vector2(x+5,265+i*36),Color(MINT,0.4),1,true)
	_center(I18n.t("PERMANENT HANGAR"),115,40,MINT,true)
	_center(I18n.f("%d CORES  /  %d LIFETIME ELIMINATIONS", [profile.credits,profile.total_kills]),161,17,GOLD)
	_center(I18n.t("Every 5 kills = 1 core. Upgrades survive defeat and apply to NEW expeditions."),198,15,MUTED)
	var keys := ["hull_rank", "damage_rank", "magnet_rank"]
	var titles := ["REINFORCED HULL", "REACTOR", "SALVAGE ARRAY"]
	var desc := ["+1 starting and maximum hull", "+0.2 damage per projectile", "+20 energy pickup range"]
	for i in range(3):
		var rect := Rect2(178+i*314,250,296,170)
		var color: Color = [MINT,BLUE,GOLD][i]
		_panel(rect,Color("0f1d31"),Color(color,0.28))
		draw_line(rect.position+Vector2(14,1),rect.position+Vector2(282,1),Color(color,0.7),2,true)
		for pip in range(5):
			draw_rect(Rect2(rect.position+Vector2(149+pip*23,95),Vector2(17,5)),color if pip < profile.get(keys[i]) else Color("263b53"))
		_glow(rect.position+Vector2(253,43),25,color,0.5)
		_text(I18n.t(titles[i]),rect.position+Vector2(20,35),18,MINT,true)
		_text(I18n.t(desc[i]),rect.position+Vector2(20,70),13,MUTED)
		_text(I18n.f("RANK %d / 5", profile.get(keys[i])),rect.position+Vector2(20,105),16,INK)
		_text(I18n.t("MAXED") if profile.get(keys[i]) >= 5 else I18n.f("[%d] BUY / %d CORES", [i+1,profile.upgrade_cost(keys[i])]),rect.position+Vector2(20,145),14,GOLD)
	_button(Rect2(390,447,500,48),I18n.f("LOADOUT: %s   [W]", I18n.t(["PULSE", "FAN (+2 BOLTS)", "LANCE (2x DAMAGE)"][profile.weapon])),false)
	_center(I18n.t("Fan unlocks at 100 kills / Lance at 300. Click loadout to cycle."),524,13,MUTED)
	_button(Rect2(468,551,344,48),I18n.t("BACK TO TITLE   /   ESC"))
	if not save_notice.is_empty():
		_center(I18n.notice(save_notice),225,13,CORAL)
	_center(I18n.t("Browser data can be cleared: this is a local save, not a cloud account."),630,12,MUTED)
	_draw_footer()

func _draw_footer() -> void:
	draw_line(Vector2(32,659),Vector2(1248,659),Color("203047"),1)
	_text(I18n.t("WASD / ↑ ↓ ← →   MOVE"),Vector2(48,695),13,MUTED)
	_text(I18n.t("SPACE   DASH + PHASE"),Vector2(353,695),13,MUTED)
	_text(I18n.t("AUTO-FIRE   ALWAYS ON"),Vector2(648,695),13,MUTED)
	_text(I18n.f("ESC PAUSE  M %s  V %s  L %s", [I18n.t("MUTED" if muted else "SOUND"), I18n.t("CALM" if reduced_motion else "FX"), I18n.switch_label()]),Vector2(963,695),11,MUTED)

func _draw_game() -> void:
	_panel(ARENA,Color("081020"),Color("29425a"),14)
	_draw_atmosphere()
	for x in range(64,1249,40):
		draw_line(Vector2(x,109),Vector2(x,639),Color(0.13,0.25,0.34,0.12),1)
	for y in range(120,641,40):
		draw_line(Vector2(33,y),Vector2(1247,y),Color(0.13,0.25,0.34,0.12),1)
	# Subtle central navigation marks.
	draw_circle(ARENA.get_center(),135,Color(0.15,0.31,0.40,0.15),false,1,true)
	draw_circle(ARENA.get_center(),139,Color(0.15,0.31,0.40,0.09),false,1,true)
	_text("N / 01",Vector2(604,131),10,Color("36506a"))
	for corner in [ARENA.position + Vector2(15,15),Vector2(1233,123),Vector2(47,625),Vector2(1233,625)]:
		draw_circle(corner,2,MINT)
	var offset := Vector2.ZERO
	if shake > 0 and state == "playing" and not reduced_motion:
		offset = Vector2(sin(ambient_time * 90),cos(ambient_time * 110)) * shake
	draw_set_transform(offset)
	if CampaignRuntime.active(self): CampaignRuntime.draw_world(self)
	for trail in trails:
		_ship(trail.p,trail.angle,MINT,trail.life / trail.max * 0.26)
		draw_line(trail.p-facing*26,trail.p,Color(MINT,trail.life/trail.max*0.18),9,true)
	for gem in gems:
		var bob := Vector2(0,sin(ambient_time * 4 + gem.phase) * 3)
		draw_circle(gem.p + bob,13,Color(MINT,0.07))
		_poly(gem.p + bob,6,4,0,Color(MINT,0.4),MINT)
	for e in enemies:
		var color := CORAL if e.kind == 0 else (GOLD if e.kind == 1 else BLUE)
		if e.warning > 0:
			var progress: float = 1.0 - e.warning / (2.0 if e.kind == 3 else 0.7)
			if e.kind == 3:
				_poly(e.p,64+30*(1.0-progress),8,ambient_time,Color(CORAL,0.04),Color(CORAL,0.6))
				draw_circle(e.p,110*(1.0-progress)+38,Color(CORAL,0.5),false,2,true)
			draw_arc(e.p,22,0,TAU * progress,30,Color(color,0.6),2,true)
			draw_line(e.p - Vector2(5,0),e.p + Vector2(5,0),color,1)
			draw_line(e.p - Vector2(0,5),e.p + Vector2(0,5),color,1)
			continue
		if e.get("attack_phase", "seek") == "windup":
			var lane_end: Vector2 = e.p + e.locked_dir * 165
			draw_line(e.p, lane_end, Color(GOLD, 0.1), 22, true)
			draw_line(e.p, lane_end, Color(GOLD, 0.75), 1.5, true)
			draw_circle(lane_end, 6, GOLD, false, 1.2, true)
		if e.kind == 3:
			_draw_warden(e)
			if CampaignRuntime.active(self):
				var boss_color := Color(Campaign.sector(campaign.sector).color)
				_poly(e.p,52+campaign.sector*9,4+campaign.sector*2,e.age*0.25,Color(boss_color,0.025),boss_color)
				for satellite in range(3+campaign.sector):
					_poly(e.p+Vector2.RIGHT.rotated(e.age*0.5+satellite*TAU/(3+campaign.sector))*65,5+campaign.sector,4,e.age,Color(boss_color,0.3),boss_color)
			continue
		var radius := 40.0 if e.kind == 3 else (14.0 if e.kind != 2 else 23.0)
		var angle: float = e.dir.angle() if e.kind != 2 else e.age * 0.6
		_glow(e.p,radius*1.25,color,0.8)
		draw_circle(e.p,radius * 1.8,Color(color,0.045))
		_poly(e.p,radius,3 if e.kind != 2 else 6,angle,Color(color,0.15 + e.flash * 0.5),color)
		if e.kind == 0:
			_poly(e.p,5,3,angle,Color(color,0.5),INK)
		if e.kind == 1:
			_poly(e.p,7,3,angle,Color(color,0.1),color)
		elif e.kind >= 2:
			draw_circle(e.p,7,color,false,2,true)
			if e.hp < e.max_hp:
				draw_line(e.p + Vector2(-18,32),e.p + Vector2(18,32),Color("20334e"),3)
				draw_line(e.p + Vector2(-18,32),e.p + Vector2(-18 + 36 * e.hp / e.max_hp,32),BLUE,3)
	for bolt in bolts:
		var color := GOLD if run_weapon == 2 else MINT
		var length := 28.0 if run_weapon == 2 else 17.0 + _ship_tier()*4
		var from: Vector2 = bolt.p - bolt.v.normalized() * length
		if not reduced_motion:
			draw_line(from,bolt.p,Color(color,0.06),15,true)
			draw_line(from,bolt.p,Color(color,0.22),7,true)
		draw_line(from,bolt.p,color,3.0,true)
		draw_line(from.lerp(bolt.p,0.5),bolt.p,INK,1.2,true)
	for ring in rings:
		var alpha: float = ring.life / ring.max
		var radius: float = ring.r * (1.0 - alpha) + 8
		if not reduced_motion:
			draw_circle(ring.p,radius,Color(ring.c,alpha * 0.07),false,9,true)
		draw_circle(ring.p,radius,Color(ring.c,alpha * 0.7),false,1.8,true)
		if ring.r > 100 and not reduced_motion:
			draw_arc(ring.p,radius*0.87,ambient_time,ambient_time+PI*1.7,48,Color(INK,alpha*0.25),1,true)
	for particle in particles:
		var alpha: float = particle.life / particle.max
		if not reduced_motion:
			draw_line(particle.p-particle.v*0.035,particle.p,Color(particle.c,alpha*0.24),particle.r*2,true)
			draw_line(particle.p-particle.v*0.025,particle.p,Color(particle.c,alpha),1.2,true)
		draw_circle(particle.p,particle.r * alpha,Color(particle.c,alpha))
	if state != "lost":
		var alpha := 0.5 if invulnerable > 0 and sin(ambient_time * 30) > 0 else 1.0
		if invulnerable > 0:
			draw_circle(player,29,Color(MINT,0.32),false,1.2,true)
		var ship_color: Color = Color(Campaign.ship(campaign.ship).color) if CampaignRuntime.active(self) else MINT
		_ship(player,facing.angle(),ship_color,alpha,1.0 + minf(level,20) * 0.014)
		if CampaignRuntime.active(self) and campaign.ship == 1:
			for side in [-1,1]:
				_poly(player+Vector2(-8,side*24).rotated(facing.angle()),9,3,facing.angle(),Color(ship_color,0.1),ship_color)
		elif CampaignRuntime.active(self) and campaign.ship == 2:
			_poly(player,29,6,facing.angle(),Color(ship_color,0.02),Color(ship_color,0.6))
		if level >= 8:
			for satellite in range(3):
				var orb := player + Vector2.RIGHT.rotated(ambient_time * 1.5 + satellite * TAU / 3) * 45
				_poly(orb,4,4,ambient_time,Color(BLUE,0.3),BLUE)
		if level >= 8:
			draw_arc(player,45,-PI/2,-PI/2+TAU*(1.0-clampf(pulse_timer/(maxf(2.5,6.0-recovery*0.25)),0,1)),48,Color(BLUE,0.3),1,true)
		if dash_cooldown <= 0:
			draw_arc(player,34,-0.25,0.25,8,Color(MINT,0.55),2,true)
	draw_set_transform(Vector2.ZERO)
	if boss_cinematic > 0 and not reduced_motion:
		var strength := minf(1.0,boss_cinematic)
		draw_line(Vector2(34,boss_cinematic_pos.y),Vector2(1246,boss_cinematic_pos.y),Color(boss_cinematic_color,strength*0.05),45,true)
		for side in [0,1]:
			var y := 113 if side == 0 else 632
			draw_line(Vector2(45,y),Vector2(1235,y),Color(boss_cinematic_color,strength*0.55),3,true)
	if screen_flash > 0:
		draw_rect(ARENA,Color(CORAL,screen_flash * 0.12))
	_draw_hud()
	if CampaignRuntime.active(self): CampaignUI.draw_campaign_hud(self)
	_draw_footer()
	if toast_timer > 0 and state == "playing":
		_panel(Rect2(385,126,510,38),Color(0.04,0.09,0.14,0.9),Color("233c4d"),6)
		_center(toast,151,13,MINT)

func _draw_hud() -> void:
	_panel(Rect2(22,14,1236,73),Color("0c1628"),Color("1b3047"),10)
	_text("NEON DRIFT",Vector2(34,48),24,INK,true)
	_text(I18n.f("CAMPAIGN / SECTOR %02d", campaign.sector+1) if CampaignRuntime.active(self) else I18n.f("SECTOR %02d / %s", [wave,I18n.t("ENDLESS") if endless else "10"]),Vector2(36,75),12,MUTED)
	_text(I18n.t("HULL"),Vector2(271,34),10,MUTED)
	for i in range(max_health):
		var fill := MINT if i < health else Color("263044")
		_panel(Rect2(270 + i * 18,44,13,19),fill,fill,3)
	_center("%02d:%02d" % [int(elapsed)/60,int(elapsed)%60],61,34,INK,true)
	_center(I18n.t(Campaign.sector(campaign.sector).name if CampaignRuntime.active(self) else "ENDLESS" if endless else ("DEFEAT THE WARDEN" if elapsed >= BOSS_TIME and not boss_defeated else "EXPEDITION / 10:00")),80,10,MUTED)
	_text(I18n.t("SCORE"),Vector2(873,34),10,MUTED)
	_text("%06d" % score,Vector2(870,64),26,INK,true)
	_panel(Rect2(1019,24,143,46),Color("111f30"),MINT if dash_cooldown <= 0 else Color("273750"),8)
	_center(I18n.t("DASH READY") if dash_cooldown <= 0 else I18n.f("DASH  %.1fs", dash_cooldown),53,12,MINT if dash_cooldown <= 0 else MUTED,true,1090)
	_panel(PAUSE_BUTTON,Color("111c2d"),Color("273750"),8)
	draw_line(Vector2(1208,39),Vector2(1208,56),INK,3)
	draw_line(Vector2(1219,39),Vector2(1219,56),INK,3)
	draw_rect(Rect2(32,94,1216,3),Color("1b2b40"))
	draw_rect(Rect2(32,94,1216 * (minf(1.0,campaign.sector_time/Campaign.sector(campaign.sector).boss_time) if CampaignRuntime.active(self) else minf(1.0, elapsed / SURVIVAL_TIME)),3),MINT)
	_panel(Rect2(46,591,233,34),Color(0.05,0.09,0.16,0.95),Color("2b4052"),6)
	_text(I18n.f("LV %02d", level),Vector2(58,613),12,MINT,true)
	draw_rect(Rect2(119,605,145,5),Color("23364b"))
	draw_rect(Rect2(119,605,145 * float(energy) / next_level,5),MINT)
	_text(I18n.f("+%d CORES / %d BOLTS / DMG %.1f", [earned_credits,mini(7,1+int(level/3)+int(overdrive/3)+(2 if run_weapon==1 else 0)),_bolt_damage()]),Vector2(830,618),12,MINT)
	if level >= 8:
		_text(I18n.f("NOVA %.1fs", maxf(0,pulse_timer)),Vector2(300,613),12,BLUE)
	for e in enemies:
		if e.kind == 3:
			_center(I18n.t(Campaign.sector(campaign.sector).boss_name if CampaignRuntime.active(self) else "SIGNAL WARDEN"),186,12,CORAL)
			draw_rect(Rect2(400,198,480,6),Color("283244"))
			draw_rect(Rect2(400,198,480 * maxf(0,e.hp/e.max_hp),6),CORAL)
	if not save_notice.is_empty():
		_center(I18n.notice(save_notice),645,12,CORAL)

func _draw_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0.015,0.027,0.055,0.82))
	_panel(Rect2(385,148,510,452),Color("0d192b"),Color("304960"),18)
	var color := MINT if state != "lost" else CORAL
	_center(I18n.t("/ /  SIGNAL HELD  / /" if state == "paused" else ("/ /  TRANSMISSION COMPLETE  / /" if state == "won" else "/ /  SIGNAL INTERRUPTED  / /")),200,12,color)
	var heading := "DRIFT LOST"
	if state == "paused": heading = "PAUSED"
	elif state == "won":
		heading = ("CROWN SILENCED" if campaign.get("claimed",[]).size() == 3 else "SECTOR CLEARED") if campaign.get("mode",false) else "YOU SURVIVED"
	_center(I18n.t(heading),263,36,INK,true)
	_center(I18n.t("Take a breath. The arena can wait." if state == "paused" else (("The convoy is free. Your fleet keeps growing." if campaign.get("mode",false) else "Warden defeated. Your pilot keeps growing.") if state == "won" else "Stay moving. Dash through the danger.")),301,14,MUTED)
	if state == "paused":
		_center(I18n.t("Saved. ESC / ENTER to resume" if save_notice.is_empty() else "ESC / ENTER to resume"),368,17,MINT)
	else:
		_center("%06d" % score,365,38,color,true)
		_center(I18n.f("%02ds survived   •   %d eliminated   •   level %d", [int(elapsed),kills,level]),398,13,MUTED)
	_button(RETRY_BUTTON,I18n.t("RESUME RUN" if state == "paused" else "TRY AGAIN   /   ENTER"))
	_button(MENU_BUTTON,I18n.t("SAVE & TITLE" if state == "paused" else "TITLE / HANGAR"),false)
	if not save_notice.is_empty():
		_center(I18n.notice(save_notice),632,12,CORAL)
	if state == "won":
		_button(Rect2(468,550,344,42),I18n.t("KEEP THIS BUILD / ENDLESS [E]"),false)
	elif state == "lost":
		_center(I18n.f("+%d cores saved. Permanent upgrades are waiting in the hangar.", earned_credits),566,11,GOLD)
	if state == "confirm_new":
		_panel(Rect2(400,165,480,248),Color("0d192b"))
		_center(I18n.t("REPLACE SAVED RUN?"),253,27,CORAL,true)
		_center(I18n.t("The current expedition build will be replaced."),308,14,INK)
		_center(I18n.t("Your cores, unlocks and hangar upgrades stay."),340,14,MUTED)
		_button(RETRY_BUTTON,I18n.t("START NEW / ENTER"))
		_button(MENU_BUTTON,I18n.t("CANCEL / ESC"),false)

func _draw_upgrades() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0.015,0.027,0.055,0.9))
	_center(I18n.f("LEVEL %02d  /  SIGNAL UPGRADE", level),194,13,MINT)
	_center(I18n.t("CHOOSE YOUR EDGE"),242,34,INK,true)
	_center(I18n.t("Time is paused. Pick one module. Every level also repairs 1 hull."),272,14,MUTED)
	var names := ["OVERDRIVE", "PHASE ENGINE", "RECOVERY"]
	var descriptions := [["Faster fire + stronger bolts.","Every 3 ranks: +1 projectile."], ["Move faster. Dash sooner.","Escape. Then strike back."], ["Repair 2 hull immediately.","Wider magnet + stronger nova."]]
	var colors := [MINT, BLUE, GOLD]
	for i in range(3):
		var rect := Rect2(178 + i * 314, 294, 296, 200)
		var hover := rect.has_point(get_global_mouse_position())
		_panel(rect,Color("14263a") if hover else PANEL, colors[i] if hover else Color("30455b"),12)
		draw_line(rect.position+Vector2(14,1),rect.position+Vector2(282,1),Color(colors[i],0.75),2,true)
		var emblem: Vector2 = rect.position+Vector2(248,38)
		_glow(emblem,28,colors[i],0.8)
		_poly(emblem,16,3+i,PI/2,Color(colors[i],0.08),colors[i])
		_poly(emblem,7,3+i,-PI/2,Color(colors[i],0.25),INK)
		_text("0%d" % (i+1),rect.position + Vector2(22,36),15,colors[i],true)
		_text(I18n.t(names[i]),rect.position + Vector2(22,81),20,INK,true)
		_text(I18n.t(descriptions[i][0]),rect.position + Vector2(22,118),12,MUTED)
		_text(I18n.t(descriptions[i][1]),rect.position + Vector2(22,139),12,MUTED)
		_text(I18n.f("SELECT  /  %d", i+1),rect.position + Vector2(22,178),12,colors[i],true)
	_center(I18n.t("Click or press 1, 2, 3  /  Level 8 unlocks an automatic nova pulse"),537,13,MUTED)


func _request_campaign() -> void:
	if profile.run.is_empty(): start_campaign(map_sector)
	else: state = "confirm_new"

func _retry_run() -> void:
	if campaign.get("mode",false): start_campaign(0)
	else: start_game()

func start_campaign(sector: int = 0) -> void:
	if sector < 0 or sector > profile.sector_unlocked: return
	start_game(false)
	campaign = CampaignRuntime.fresh(sector,profile.ship)
	var ship: Dictionary = Campaign.ship(profile.ship)
	max_health = maxi(2,max_health+ship.hull_bonus)
	health = max_health
	toast = I18n.f("%s / COMPLETE THE MISSION", I18n.t(Campaign.sector(sector).name))
	toast_timer = 4.0
	save_run()

func _cycle_ship() -> void:
	var previous: int = profile.ship
	for offset in range(1,4):
		var candidate: int = (profile.ship+offset)%3
		if profile.ship_unlocked(candidate):
			profile.ship = candidate
			if not profile.save_data(): profile.ship = previous
			save_notice = profile.last_error
			return

func _check_evolution() -> void:
	if not CampaignRuntime.active(self): return
	if not Campaign.evolution(run_weapon,overdrive,phase_engine,recovery).is_empty():
		if profile.award_achievement("evolved",20):
			toast = I18n.f("WEAPON EVOLVED / %s", I18n.t(Campaign.evolution(run_weapon,overdrive,phase_engine,recovery)))
			toast_timer = 4.0
	if phase_engine >= 5: profile.award_achievement("dash_50",30)
