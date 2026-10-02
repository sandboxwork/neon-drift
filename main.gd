extends Node2D
## NEON DRIFT. All art is drawn procedurally; no network or external dependencies.

const SIZE := Vector2(1280, 720)
const ARENA := Rect2(32, 108, 1216, 532)
const SURVIVAL_TIME := 75.0
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
var rng := RandomNumberGenerator.new()
var sounds: Dictionary = {}
var audio_pool: Array[AudioStreamPlayer] = []
var audio_index := 0

func _ready() -> void:
	rng.randomize()
	for i in range(75):
		stars.append(Vector3(rng.randf_range(0,1280), rng.randf_range(0,720), rng.randf()))
	_setup_inputs()
	_setup_audio()
	var save := ConfigFile.new()
	if save.load("user://record.cfg") == OK:
		best_score = int(save.get_value("record", "best", 0))
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

func start_game() -> void:
	state = "playing"
	elapsed = 0.0
	player = ARENA.get_center()
	previous_player = player
	facing = Vector2.RIGHT
	health = 5
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
	rings.clear()
	trails.clear()
	toast = "STAY MOVING.  COLLECT ENERGY."
	toast_timer = 3.0
	_ring(player, MINT, 120, 0.65)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V:
			reduced_motion = not reduced_motion
		if state == "upgrade" and event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
			choose_upgrade(event.physical_keycode - KEY_1)
		if event.physical_keycode == KEY_F12:
			_save_screenshot()
		if event.physical_keycode == KEY_M:
			muted = not muted
		if event.physical_keycode == KEY_ENTER:
			if state == "menu" or state == "lost" or state == "won":
				start_game()
			elif state == "paused":
				state = "playing"
		if event.physical_keycode == KEY_R and state in ["lost", "won"]:
			start_game()
		if event.is_action_pressed("pause_game"):
			if state == "playing":
				state = "paused"
			elif state == "paused":
				state = "playing"
			elif state not in ["menu", "upgrade"]:
				state = "menu"
		if event.is_action_pressed("dash") and state == "playing":
			try_dash()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cursor := get_global_mouse_position()
		if state == "upgrade":
			for i in range(3):
				if Rect2(178 + i * 314, 294, 296, 200).has_point(cursor):
					choose_upgrade(i)
		elif state == "menu" and MAIN_BUTTON.has_point(cursor):
			start_game()
		elif state in ["paused", "lost", "won"]:
			if RETRY_BUTTON.has_point(cursor):
				if state == "paused":
					state = "playing"
				else:
					start_game()
			elif MENU_BUTTON.has_point(cursor):
				state = "menu"
		elif state == "playing" and PAUSE_BUTTON.has_point(cursor):
			state = "paused"

func try_dash() -> bool:
	if dash_cooldown > 0.0 or state != "playing":
		return false
	dash_left = 0.17
	dash_cooldown = maxf(0.85, 1.55 - (level - 1) * 0.05 - phase_engine * 0.16)
	invulnerable = maxf(invulnerable, 0.24)
	_ring(player, MINT, 50, 0.3)
	_sound("dash")
	return true

func _process(delta: float) -> void:
	ambient_time += delta
	if state == "playing":
		_tick(minf(delta, 0.05))
	if state not in ["paused", "upgrade"]:
		_tick_effects(delta)
	queue_redraw()

func _tick(delta: float) -> void:
	elapsed += delta
	if elapsed >= SURVIVAL_TIME:
		finish_game(true)
		return
	var new_wave := mini(5, int(elapsed / 15.0) + 1)
	if new_wave != wave:
		wave = new_wave
		toast = "WAVE %02d  /  SIGNAL INTENSIFYING" % wave
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
	var speed := 235.0 + level * 4.0 + phase_engine * 15.0
	if dash_left > 0:
		player += facing * 860.0 * delta
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
		spawn_timer = maxf(0.23, 0.95 - elapsed * 0.009)
	fire_timer -= delta
	if fire_timer <= 0 and not enemies.is_empty():
		_fire()
		fire_timer = maxf(0.15, 0.48 - level * 0.037 - overdrive * 0.04)
	_move_enemies(delta)
	if state != "playing":
		return
	_move_bolts(delta)
	_collect_gems(delta)

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
	if elapsed > 16 and rng.randf() < 0.28:
		kind = 1
	if elapsed > 35 and rng.randf() < 0.24:
		kind = 2
	var hp := 1.0 if kind == 0 else (2.0 if kind == 1 else 4.0)
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
		var speed := 78.0 + elapsed * 0.55
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
			speed = 57.0 + elapsed * 0.25
		e.dir = direction
		e.p += direction * speed * delta
		var radius := 13.0 if e.kind != 2 else 21.0
		var collision_point: Vector2 = Geometry2D.get_closest_point_to_segment(e.p, previous_player, player) if dash_left > 0 else player
		if e.p.distance_to(collision_point) < radius + 12:
			if dash_left > 0:
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
	var count := 1 if level < 3 else (2 if level < 6 else 3)
	for i in range(count):
		var angle := (float(i) - (count - 1) * 0.5) * 0.16
		bolts.append({"p": player + direction * 18, "v": direction.rotated(angle) * 690, "life": 1.3})
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
			var radius := 18.0 if e.kind != 2 else 26.0
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(e.p, previous, b.p)
			if closest.distance_to(e.p) < radius:
				e.hp -= 1.0 if level < 5 else 2.0
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
	gems.append({"p": e.p, "phase": rng.randf() * TAU, "value": 2 if e.kind == 2 else 1})
	score += (30 if e.kind == 2 else 10) + (15 if by_dash else 0)
	kills += 1
	enemies.remove_at(index)
	if by_dash:
		_sound("hit")

func _collect_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var g := gems[i]
		var distance: float = g.p.distance_to(player)
		if distance < 112 + level * 7 + recovery * 34:
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
				health = mini(5, health + 1)
				toast = "LEVEL %02d  /  FIREPOWER UP + 1 HULL" % level
				toast_timer = 2.4
				_ring(player, MINT, 155, 0.7)
				_sound("upgrade")
				state = "upgrade"
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
		elapsed = SURVIVAL_TIME
		score += 500 + health * 100
		_sound("finish")
		_burst(player, MINT, 70, 320)
	best_score = maxi(best_score, score)
	var save := ConfigFile.new()
	save.set_value("record", "best", best_score)
	save.save("user://record.cfg")

func _particle(pos: Vector2, velocity: Vector2, color: Color, life: float, radius: float) -> void:
	particles.append({"p": pos, "v": velocity, "c": color, "life": life, "max": life, "r": radius})

func _burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in range(count):
		var direction := Vector2.RIGHT.rotated(rng.randf() * TAU)
		_particle(pos, direction * rng.randf_range(speed * 0.25, speed), color, rng.randf_range(0.2,0.6), rng.randf_range(1.5,4))

func _ring(pos: Vector2, color: Color, radius: float, life: float) -> void:
	rings.append({"p":pos, "c":color, "r":radius, "life":life, "max":life})

func _tick_effects(delta: float) -> void:
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
			toast = "OVERDRIVE  /  FASTER AUTO-FIRE"
		1:
			phase_engine += 1
			toast = "PHASE ENGINE  /  FASTER MOVE + DASH"
		2:
			recovery += 1
			health = mini(5, health + 2)
			toast = "RECOVERY  /  REPAIR + WIDER ENERGY MAGNET"
	invulnerable = maxf(invulnerable, 1.0)
	toast_timer = 2.2
	state = "playing"
	_sound("upgrade")

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
	else:
		_draw_game()
		if state == "upgrade":
			_draw_upgrades()
		elif state in ["paused", "won", "lost"]:
			_draw_overlay()


func _text(value: String, pos: Vector2, size: int, color: Color = INK, bold: bool = false) -> void:
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

func _ship(pos: Vector2, angle: float, color: Color = MINT, alpha: float = 1.0, scale_factor: float = 1.0) -> void:
	var points := PackedVector2Array()
	for point in [Vector2(20,0), Vector2(-13,-12), Vector2(-7,0), Vector2(-13,12)]:
		points.append(pos + point.rotated(angle) * scale_factor)
	draw_circle(pos,26 * scale_factor,Color(color,0.055 * alpha))
	draw_colored_polygon(points, Color(color,0.16 * alpha))
	points.append(points[0])
	draw_polyline(points,Color(color,alpha),2.4,true)
	draw_circle(pos + Vector2(2,0).rotated(angle) * scale_factor,3.4 * scale_factor, Color(INK,alpha))

func _draw_menu() -> void:
	_text("O R B I T A L   /   A R C A D E   0 1",Vector2(80,78),13,MINT)
	_text("NEON",Vector2(74,222),100,INK,true)
	_text("DRIFT",Vector2(74,324),100,MINT,true)
	draw_line(Vector2(80,357),Vector2(140,357),MINT,3)
	_text("One pilot. An endless signal.",Vector2(80,398),21,INK)
	_text("Survive 75 seconds inside the neon storm.",Vector2(80,432),16,MUTED)
	_button(MAIN_BUTTON,"ENTER THE ARENA   →")
	_text("AUTO-FIRE  •  GEMS = UPGRADES  •  DASH = SAFE",Vector2(82,552),12,MUTED)
	_text("Press ENTER to launch  /  Choose upgrades with 1, 2, 3",Vector2(82,576),12,MUTED)
	if best_score > 0:
		_text("PERSONAL BEST  /  %06d" % best_score,Vector2(80,602),14,GOLD)
	# A schematic arena illustration, not a static screenshot.
	var center := Vector2(930,346)
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
	_ship(center,-0.45,MINT,1.0,2.4)
	for i in range(7):
		var angle := i * 1.6 + ambient_time * (0.075 if i % 2 == 0 else -0.06)
		var pos := center + Vector2.RIGHT.rotated(angle) * (150 + (i % 3) * 29)
		_poly(pos,14 if i % 3 == 0 else 10,4 if i % 3 == 0 else 3,angle,Color(CORAL,0.08),CORAL if i % 3 == 0 else GOLD)
	for i in range(3):
		var pos := center + Vector2(52 + i * 22,-25 - i * 10)
		draw_line(pos,pos + Vector2(10,-5),MINT,3,true)
	_panel(Rect2(738,581,388,54),Color("0c1727"),Color("203549"),6)
	_text("75s",Vector2(760,617),22,MINT,true)
	_text("SURVIVE",Vector2(815,615),11,MUTED)
	_text("05",Vector2(926,617),22,INK,true)
	_text("WAVES",Vector2(969,615),11,MUTED)
	_draw_footer()

func _draw_footer() -> void:
	draw_line(Vector2(32,659),Vector2(1248,659),Color("203047"),1)
	_text("WASD / ↑ ↓ ← →   MOVE",Vector2(48,695),13,MUTED)
	_text("SPACE   DASH + PHASE",Vector2(353,695),13,MUTED)
	_text("AUTO-FIRE   ALWAYS ON",Vector2(648,695),13,MUTED)
	_text("ESC PAUSE  M " + ("MUTED" if muted else "SOUND") + "  V " + ("CALM" if reduced_motion else "FX"),Vector2(963,695),11,MUTED)

func _draw_game() -> void:
	_panel(ARENA,Color("0a1424"),Color("29425a"),14)
	for x in range(64,1249,40):
		draw_line(Vector2(x,109),Vector2(x,639),Color(0.13,0.25,0.34,0.23),1)
	for y in range(120,641,40):
		draw_line(Vector2(33,y),Vector2(1247,y),Color(0.13,0.25,0.34,0.23),1)
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
	for trail in trails:
		_ship(trail.p,trail.angle,MINT,trail.life / trail.max * 0.32)
	for gem in gems:
		var bob := Vector2(0,sin(ambient_time * 4 + gem.phase) * 3)
		draw_circle(gem.p + bob,13,Color(MINT,0.07))
		_poly(gem.p + bob,6,4,0,Color(MINT,0.4),MINT)
	for e in enemies:
		var color := CORAL if e.kind == 0 else (GOLD if e.kind == 1 else BLUE)
		if e.warning > 0:
			var progress: float = 1.0 - e.warning / 0.7
			draw_arc(e.p,22,0,TAU * progress,30,Color(color,0.6),2,true)
			draw_line(e.p - Vector2(5,0),e.p + Vector2(5,0),color,1)
			draw_line(e.p - Vector2(0,5),e.p + Vector2(0,5),color,1)
			continue
		if e.get("attack_phase", "seek") == "windup":
			var lane_end: Vector2 = e.p + e.locked_dir * 165
			draw_line(e.p, lane_end, Color(GOLD, 0.1), 22, true)
			draw_line(e.p, lane_end, Color(GOLD, 0.75), 1.5, true)
			draw_circle(lane_end, 6, GOLD, false, 1.2, true)
		var radius := 14.0 if e.kind != 2 else 23.0
		var angle: float = e.dir.angle() if e.kind != 2 else e.age * 0.6
		draw_circle(e.p,radius * 1.8,Color(color,0.045))
		_poly(e.p,radius,3 if e.kind != 2 else 6,angle,Color(color,0.15 + e.flash * 0.5),color)
		if e.kind == 1:
			_poly(e.p,7,3,angle,Color(color,0.1),color)
		elif e.kind == 2:
			draw_circle(e.p,7,color,false,2,true)
			if e.hp < e.max_hp:
				draw_line(e.p + Vector2(-18,32),e.p + Vector2(18,32),Color("20334e"),3)
				draw_line(e.p + Vector2(-18,32),e.p + Vector2(-18 + 36 * e.hp / e.max_hp,32),BLUE,3)
	for bolt in bolts:
		var from: Vector2 = bolt.p - bolt.v.normalized() * 13
		draw_line(from,bolt.p,Color(MINT,0.13),8,true)
		draw_line(from,bolt.p,MINT,2.5,true)
	for ring in rings:
		var alpha: float = ring.life / ring.max
		draw_circle(ring.p,ring.r * (1.0 - alpha) + 8,Color(ring.c,alpha * 0.7),false,1.8,true)
	for particle in particles:
		draw_circle(particle.p,particle.r * particle.life / particle.max,Color(particle.c,particle.life / particle.max))
	if state != "lost":
		var alpha := 0.5 if invulnerable > 0 and sin(ambient_time * 30) > 0 else 1.0
		if invulnerable > 0:
			draw_circle(player,29,Color(MINT,0.32),false,1.2,true)
		_ship(player,facing.angle(),MINT,alpha)
		if dash_cooldown <= 0:
			draw_arc(player,34,-0.25,0.25,8,Color(MINT,0.55),2,true)
	draw_set_transform(Vector2.ZERO)
	if screen_flash > 0:
		draw_rect(ARENA,Color(CORAL,screen_flash * 0.12))
	_draw_hud()
	_draw_footer()
	if toast_timer > 0 and state == "playing":
		_panel(Rect2(385,126,510,38),Color(0.04,0.09,0.14,0.9),Color("233c4d"),6)
		_center(toast,151,13,MINT)

func _draw_hud() -> void:
	_text("NEON DRIFT",Vector2(34,48),24,INK,true)
	_text("WAVE %02d / 05" % wave,Vector2(36,75),12,MUTED)
	_text("HULL",Vector2(271,34),10,MUTED)
	for i in range(5):
		var fill := MINT if i < health else Color("263044")
		_panel(Rect2(270 + i * 26,44,19,19),fill,fill,3)
	_center("%02d" % ceili(maxf(0,SURVIVAL_TIME - elapsed)),61,40,INK,true)
	_center("SECONDS LEFT",80,10,MUTED)
	_text("SCORE",Vector2(873,34),10,MUTED)
	_text("%06d" % score,Vector2(870,64),26,INK,true)
	_panel(Rect2(1019,24,143,46),Color("111f30"),MINT if dash_cooldown <= 0 else Color("273750"),8)
	_center("DASH READY" if dash_cooldown <= 0 else "DASH  %.1fs" % dash_cooldown,53,12,MINT if dash_cooldown <= 0 else MUTED,true,1090)
	_panel(PAUSE_BUTTON,Color("111c2d"),Color("273750"),8)
	draw_line(Vector2(1208,39),Vector2(1208,56),INK,3)
	draw_line(Vector2(1219,39),Vector2(1219,56),INK,3)
	draw_rect(Rect2(32,94,1216,3),Color("1b2b40"))
	draw_rect(Rect2(32,94,1216 * elapsed / SURVIVAL_TIME,3),MINT)
	_panel(Rect2(46,591,233,34),Color(0.05,0.09,0.16,0.95),Color("2b4052"),6)
	_text("LV %02d" % level,Vector2(58,613),12,MINT,true)
	draw_rect(Rect2(119,605,145,5),Color("23364b"))
	draw_rect(Rect2(119,605,145 * float(energy) / next_level,5),MINT)
	_text("SIGNAL  /  %02d%%" % int(elapsed / SURVIVAL_TIME * 100),Vector2(1100,618),10,MUTED)

func _draw_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0.015,0.027,0.055,0.82))
	_panel(Rect2(385,148,510,424),Color("0d192b"),Color("304960"),18)
	var color := MINT if state != "lost" else CORAL
	_center("/ /  SIGNAL HELD  / /" if state == "paused" else ("/ /  TRANSMISSION COMPLETE  / /" if state == "won" else "/ /  SIGNAL INTERRUPTED  / /"),200,12,color)
	_center("PAUSED" if state == "paused" else ("YOU SURVIVED" if state == "won" else "DRIFT LOST"),263,36,INK,true)
	_center("Take a breath. The arena can wait." if state == "paused" else ("75 seconds. One unforgettable escape." if state == "won" else "Stay moving. Dash through the danger."),301,14,MUTED)
	if state == "paused":
		_center("ESC / ENTER to resume",368,17,MINT)
	else:
		_center("%06d" % score,365,38,color,true)
		_center("%02ds survived   •   %d eliminated   •   level %d" % [int(elapsed),kills,level],398,13,MUTED)
	_button(RETRY_BUTTON,"RESUME RUN" if state == "paused" else "TRY AGAIN   /   ENTER")
	_button(MENU_BUTTON,"BACK TO TITLE",false)

func _draw_upgrades() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0.015,0.027,0.055,0.9))
	_center("LEVEL %02d  /  SIGNAL UPGRADE" % level,194,13,MINT)
	_center("CHOOSE YOUR EDGE",242,34,INK,true)
	_center("Time is paused. Pick one module. Every level also repairs 1 hull.",272,14,MUTED)
	var names := ["OVERDRIVE", "PHASE ENGINE", "RECOVERY"]
	var descriptions := [["Increase auto-fire rate.","Clear the storm faster."], ["Move faster. Dash sooner.","Escape. Then strike back."], ["Repair 2 hull immediately.","Collect energy from farther away."]]
	var colors := [MINT, BLUE, GOLD]
	for i in range(3):
		var rect := Rect2(178 + i * 314, 294, 296, 200)
		var hover := rect.has_point(get_global_mouse_position())
		_panel(rect,Color("14263a") if hover else PANEL, colors[i] if hover else Color("30455b"),12)
		_text("0%d" % (i+1),rect.position + Vector2(22,36),15,colors[i],true)
		_text(names[i],rect.position + Vector2(22,81),20,INK,true)
		_text(descriptions[i][0],rect.position + Vector2(22,118),12,MUTED)
		_text(descriptions[i][1],rect.position + Vector2(22,139),12,MUTED)
		_text("SELECT  /  %d" % (i+1),rect.position + Vector2(22,178),12,colors[i],true)
	_center("Click a module or press 1, 2, 3",537,13,MUTED)
