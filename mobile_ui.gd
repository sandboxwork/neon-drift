extends CanvasLayer
## Mobile presentation and indexed touch input. Gameplay and save schema remain
## in main.gd. All touch positions are converted from viewport to safe UI space.

const I18n = preload("res://i18n.gd")
const INK := Color("e9f3ff")
const MINT := Color("64ffda")
const MUTED := Color("9baec4")
const BG := Color("080e1c")
const PANEL := Color("14243a")
const CORAL := Color("ff687d")
const STICK_RADIUS := 64.0
const DEADZONE := 0.14

var game: Node2D
var movement := Vector2.ZERO
var stick_index := -1
var stick_origin := Vector2.ZERO
var touches: Dictionary = {}
var buttons: Dictionary = {}
var screen: Control
var controls: Control
var hud: Label
var mission: Label
var status: Label
var boss: ProgressBar
var energy_bar: ProgressBar
var safe_rect := Rect2()
var ui_scale := 1.0
var dimensions := Vector2(1280, 720)
var dirty := true
var settings_open := false
var fleet_open := false
var journal_page := 0
var legal_open := false
var legal_page := 0
var last_locale := ""
var web_opener: Callable = OS.shell_open
var link_error := false
var portrait := false
var old_emulation := true
var old_aspect: int
var old_fps: int

func _ready() -> void:
	layer = 10
	old_emulation = Input.emulate_mouse_from_touch
	old_aspect = get_window().content_scale_aspect
	old_fps = Engine.max_fps
	Input.emulate_mouse_from_touch = false
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	Engine.max_fps = 60
	_refresh_geometry()
	refresh()

func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = old_emulation
	Engine.max_fps = old_fps
	if is_instance_valid(game) and game.is_inside_tree():
		game.position = Vector2.ZERO
		game.scale = Vector2.ONE
		get_window().content_scale_aspect = old_aspect

func invalidate() -> void:
	reset_input()
	dirty = true

func reset_input() -> void:
	movement = Vector2.ZERO
	stick_index = -1
	for entry in touches.values():
		var button = entry.get("button")
		if is_instance_valid(button):
			button.modulate = Color.WHITE
	touches.clear()

static func fit_arena(area: Rect2, arena: Rect2) -> Transform2D:
	var factor := minf(area.size.x / arena.size.x, area.size.y / arena.size.y)
	return Transform2D(0.0, Vector2.ONE * factor, 0.0, area.get_center() - arena.get_center() * factor)

func _refresh_geometry() -> void:
	var view := get_viewport().get_visible_rect()
	var usable := view
	if OS.has_feature("ios") or OS.has_feature("android"):
		var physical := Rect2(DisplayServer.get_display_safe_area())
		if physical.has_area():
			usable = (get_viewport().get_screen_transform().affine_inverse() * physical).intersection(view)
	if not usable.has_area():
		usable = view
	if usable == safe_rect:
		return
	if safe_rect.has_area():
		game._on_focus_lost()
	safe_rect = usable
	portrait = usable.size.y > usable.size.x
	ui_scale = minf(usable.size.y / 720.0, usable.size.x / 1180.0)
	dimensions = usable.size / ui_scale
	var arena_area := Rect2(usable.position + Vector2(16, 100) * ui_scale,
		usable.size - Vector2(32, 260) * ui_scale)
	game.transform = fit_arena(arena_area, game.ARENA)
	invalidate()

func _process(_delta: float) -> void:
	_refresh_geometry()
	if last_locale != I18n.locale:
		dirty = true
	if dirty:
		refresh()
	if is_instance_valid(controls):
		controls.queue_redraw()
	if is_instance_valid(hud):
		hud.text = "%s %d/%d   ·   %s %02d   ·   %02d:%02d   ·   %06d" % [I18n.t("HULL"), game.health, game.max_health, I18n.t("LEVEL"), game.level, int(game.elapsed) / 60, int(game.elapsed) % 60, game.score]
		mission.text = I18n.t("Move with the left stick. Fire is automatic.")
		if game.CampaignRuntime.active(game):
			var sector: Dictionary = game.Campaign.sector(game.campaign.sector)
			mission.text = "%s   %d / %d" % [I18n.t(sector.objective_label), mini(int(game.campaign.objective), sector.objective_target), sector.objective_target]
		var build_hint: String = game.CampaignUI._evolution_label(game) if game.CampaignRuntime.active(game) else I18n.t("Move with the left stick. Fire is automatic.")
		status.text = I18n.notice(game.save_notice) if not game.save_notice.is_empty() else (game.toast if game.toast_timer > 0 else build_hint + "\n" + I18n.f("%d CORES", game.earned_credits))
		energy_bar.value = 100.0 * game.energy / maxi(1, game.next_level)
		boss.visible = false
		for enemy in game.enemies:
			if enemy.kind == 3:
				boss.visible = true
				boss.value = 100.0 * maxf(0, enemy.hp / enemy.max_hp)
				mission.text += "  ·  " + I18n.t(game.Campaign.sector(game.campaign.sector).boss_name if game.CampaignRuntime.active(game) else "SIGNAL WARDEN")
				break

func _box(color: Color, border: Color = Color("304860")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _label(text: String, rect: Rect2, font_size: int = 30, color: Color = INK, parent: Control = null) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", game.ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.position = rect.position
	label.size = rect.size
	(parent if parent != null else screen).add_child(label)
	return label

func _button(id: String, text: String, rect: Rect2, action: Callable, primary := false, enabled := true) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	button.add_theme_font_override("font", game.title_font)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", BG if primary else INK)
	button.add_theme_color_override("font_hover_color", BG if primary else INK)
	button.add_theme_color_override("font_pressed_color", BG if primary else INK)
	button.add_theme_stylebox_override("normal", _box(MINT if primary else PANEL, MINT if primary else Color("304860")))
	button.add_theme_stylebox_override("hover", _box(Color("9affea") if primary else Color("223951")))
	button.add_theme_stylebox_override("pressed", _box(Color("4ebfa6") if primary else Color("284761")))
	button.add_theme_stylebox_override("disabled", _box(Color("101b2d")))
	button.pressed.connect(func():
		if not button.disabled and not dirty:
			action.call()
			invalidate())
	screen.add_child(button)
	buttons[id] = button
	return button

func _heading(title: String, detail := "") -> void:
	_label(title, Rect2(24, 16, dimensions.x - 48, 66), 44, MINT)
	if not detail.is_empty():
		_label(detail, Rect2(24, 90, dimensions.x - 48, 100), 28, MUTED)

func _back(action: Callable) -> void:
	_button("back", I18n.t("BACK"), Rect2(24, dimensions.y - 110, 240, 88), action)

func _set_state(value: String) -> void:
	game.state = value

func refresh() -> void:
	reset_input()
	if last_locale != I18n.locale:
		# Transient notices were formatted in the previous language.
		game.toast_timer = 0.0
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	buttons.clear()
	hud = null
	mission = null
	status = null
	boss = null
	energy_bar = null
	controls = null
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.position = safe_rect.position
	screen.scale = Vector2.ONE * ui_scale
	screen.size = dimensions
	add_child(screen)
	last_locale = I18n.locale
	var background := ColorRect.new()
	background.color = Color(BG, 0.96 if game.state != "playing" else 0.0)
	background.size = dimensions
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(background)
	if portrait:
		_heading(I18n.t("Rotate your device"), I18n.t("Play in landscape orientation."))
	elif legal_open:
		_draw_legal()
	elif settings_open:
		_draw_settings()
	elif fleet_open:
		_draw_fleet()
	else:
		match game.state:
			"menu": _draw_menu()
			"sector_map": _draw_map()
			"hangar": _draw_hangar()
			"journal": _draw_journal()
			"playing": _draw_playing()
			"upgrade", "intermission": _draw_choices()
			_: _draw_result()
	if game.state != "playing" and not game.save_notice.is_empty():
		_label(I18n.notice(game.save_notice), Rect2(290, dimensions.y - 110, dimensions.x - 320, 95), 24, CORAL)
	dirty = false

func _draw_menu() -> void:
	_heading("NEON DRIFT", I18n.t("Three sectors. One evolving ship. Push through to the source."))
	var width := (dimensions.x - 72) / 2
	_button("play", I18n.t("CONTINUE" if not game.profile.run.is_empty() else "NEW CAMPAIGN"), Rect2(24, 220, width, 104), game._launch, true)
	_button("map", I18n.t("SECTOR MAP"), Rect2(48 + width, 220, width, 104), _set_state.bind("sector_map"))
	_button("hangar", I18n.t("HANGAR"), Rect2(24, 350, width, 104), _set_state.bind("hangar"))
	_button("settings", I18n.t("SETTINGS"), Rect2(48 + width, 350, width, 104), func(): settings_open = true)
	_label(I18n.t("Move with the left stick. Fire is automatic."), Rect2(24, 496, dimensions.x - 48, 65), 30, MUTED)
	_label(I18n.t("Progress is saved on this device."), Rect2(24, 566, dimensions.x - 48, 65), 28, MUTED)

func _draw_map() -> void:
	_heading(I18n.t("SECTOR MAP"))
	var width := (dimensions.x - 80) / 3
	for i in range(3):
		var sector: Dictionary = game.Campaign.sector(i)
		var x := 24 + i * (width + 16)
		_button("sector_%d" % i, "%02d  %s" % [i + 1, I18n.t("SELECTED" if game.map_sector == i else "AVAILABLE" if i <= game.profile.sector_unlocked else "LOCKED")], Rect2(x, 110, width, 88), func(): game.map_sector = i, game.map_sector == i, i <= game.profile.sector_unlocked)
		_label(I18n.t(sector.name), Rect2(x, 220, width, 82), 30)
		_label(I18n.t(sector.objective_hint), Rect2(x, 310, width, 160), 26, MUTED)
	var ship: Dictionary = game.Campaign.ship(game.profile.ship)
	_button("ship", I18n.t(ship.name) + "  /  " + I18n.t("CHANGE SHIP"), Rect2(24, 480, dimensions.x * 0.52 - 36, 88), func(): fleet_open = true)
	_button("launch", I18n.t("LAUNCH"), Rect2(dimensions.x * 0.52, 480, dimensions.x * 0.48 - 24, 88), game._request_campaign, true)
	_back(_set_state.bind("menu"))
	_button("journal", I18n.t("JOURNAL"), Rect2(dimensions.x - 284, dimensions.y - 110, 260, 88), _set_state.bind("journal"))
	if game.map_sector > 0:
		_label(I18n.t("Practice start: earlier sectors are skipped."), Rect2(290, dimensions.y - 106, dimensions.x - 600, 86), 24, MUTED)

func _select_ship(index: int) -> void:
	if not game.profile.ship_unlocked(index):
		return
	var previous: int = game.profile.ship
	game.profile.ship = index
	if not game.profile.save_data():
		game.profile.ship = previous
	game.save_notice = game.profile.last_error

func _draw_fleet() -> void:
	_heading(I18n.t("CHANGE SHIP"))
	for i in range(3):
		var ship: Dictionary = game.Campaign.ship(i)
		var unlocked: bool = game.profile.ship_unlocked(i)
		_button("ship_%d" % i, I18n.t(ship.name), Rect2(24, 118 + i * 154, 320, 96), _select_ship.bind(i), game.profile.ship == i, unlocked)
		var detail: String = I18n.t(ship.description)
		if not unlocked:
			detail = I18n.t(ship.unlock_label) + "\n" + detail
		_label(detail, Rect2(370, 112 + i * 154, dimensions.x - 394, 140), 27, INK if unlocked else MUTED)
	_back(func(): fleet_open = false)

func _draw_hangar() -> void:
	_heading(I18n.t("HANGAR"), I18n.f("%d CORES", game.profile.credits))
	var width := (dimensions.x - 80) / 3
	var keys := ["hull_rank", "damage_rank", "magnet_rank"]
	var names := ["HULL", "REACTOR", "SALVAGE ARRAY"]
	var descriptions := ["+1 starting and maximum hull", "+0.2 damage per projectile", "+20 energy pickup range"]
	for i in range(3):
		var x := 24 + i * (width + 16)
		var rank: int = game.profile.get(keys[i])
		_label(I18n.t(names[i]), Rect2(x, 175, width, 68), 32, MINT)
		_label(I18n.t(descriptions[i]) + "\n" + I18n.f("RANK %d / 5", rank), Rect2(x, 250, width, 122), 28, MUTED)
		_button("buy_%d" % i, I18n.t("MAXED") if rank == 5 else I18n.f("BUY / %d CORES", game.profile.upgrade_cost(keys[i])), Rect2(x, 390, width, 88), game._buy.bind(i), false, rank < 5)
	_button("weapon", I18n.t("WEAPON") + ": " + I18n.t(["PULSE", "FAN", "LANCE"][game.profile.weapon]), Rect2(24, 502, dimensions.x - 48, 88), game._cycle_weapon)
	_back(_set_state.bind("menu"))

func _draw_journal() -> void:
	_heading(I18n.t("JOURNAL"), I18n.t("PILOT MILESTONES" if journal_page < 2 else "WEAPON EVOLUTION RECIPES"))
	if journal_page < 2:
		var achievements: Array = game.Campaign.achievements()
		for row in range(3):
			var item: Dictionary = achievements[journal_page * 3 + row]
			var earned: bool = game.profile.achievements.has(item.id)
			_label(I18n.t(item.name) + "  ·  " + I18n.t("EARNED" if earned else "LOCKED"), Rect2(24, 185 + row * 130, dimensions.x - 48, 50), 30, MINT if earned else INK)
			_label(I18n.t(item.description), Rect2(24, 239 + row * 130, dimensions.x - 48, 72), 27, MUTED)
	else:
		var names := ["PULSE > NOVA ARRAY", "FAN > STARWEAVE", "LANCE > VOID LANCE"]
		for row in range(3):
			_label(I18n.t(names[row]), Rect2(24, 185 + row * 130, dimensions.x - 48, 50), 30, MINT)
			_label(I18n.t("Overdrive rank 3 + Phase Engine rank 2" if row == 1 else "Overdrive rank 3 + Recovery rank 2"), Rect2(24, 239 + row * 130, dimensions.x - 48, 72), 27, MUTED)
	_back(_set_state.bind("sector_map"))
	_button("next", "%s  %d / 3" % [I18n.t("NEXT"), journal_page + 1], Rect2(dimensions.x - 344, dimensions.y - 110, 320, 88), func(): journal_page = (journal_page + 1) % 3)

func _draw_choices() -> void:
	var relic: bool = game.state == "intermission"
	_heading(I18n.t("CHOOSE A RELIC" if relic else "CHOOSE YOUR EDGE"), I18n.t("Your build carries forward. Choosing a relic launches the next sector." if relic else "Time is paused. Pick one module. Every level also repairs 1 hull."))
	var names := ["HELIX REACTOR", "PHASE CAPACITOR", "REPAIR MATRIX"] if relic else ["OVERDRIVE", "PHASE ENGINE", "RECOVERY"]
	var descriptions := ["+0.5 projectile damage", "+1 phase rank", "+1 maximum hull"] if relic else ["Faster fire + stronger bolts.", "Move faster. Dash sooner.", "Repair 2 hull immediately."]
	var width := (dimensions.x - 80) / 3
	for i in range(3):
		var x := 24 + i * (width + 16)
		_label(I18n.t(names[i]), Rect2(x, 216, width, 86), 32, MINT)
		var detail: String = I18n.t(descriptions[i])
		if not relic:
			detail += "\n" + I18n.t(["Every 3 ranks: +1 projectile.", "Escape. Then strike back.", "Wider magnet + stronger nova."][i])
		_label(detail, Rect2(x, 310, width, 148), 26)
		_button("choice_%d" % i, I18n.t("SELECT"), Rect2(x, 468, width, 96), func():
			if relic: game.CampaignRuntime.choose_relic(game, i)
			else: game.choose_upgrade(i), true)
	_button("home", I18n.t("SAVE & TITLE"), Rect2(24, dimensions.y - 110, 280, 88), game._go_home)

func _draw_result() -> void:
	var titles := {"paused": "PAUSED", "lost": "DRIFT LOST", "won": "TRANSMISSION COMPLETE", "confirm_new": "REPLACE SAVED RUN?"}
	_heading(I18n.t(titles.get(game.state, "PAUSED")))
	if game.state == "confirm_new":
		_label(I18n.t("The current expedition build will be replaced.") + "\n" + I18n.t("Your cores, unlocks and hangar upgrades stay."), Rect2(24, 160, dimensions.x - 48, 160), 30)
		_button("confirm", I18n.t("START NEW"), Rect2(24, 368, dimensions.x - 48, 96), game.start_campaign.bind(game.map_sector), true)
		_back(_set_state.bind("sector_map"))
		return
	_label(I18n.f("%02ds survived   •   %d eliminated   •   level %d", [int(game.elapsed), game.kills, game.level]), Rect2(24, 130, dimensions.x - 48, 90), 30, MUTED)
	var width := (dimensions.x - 72) / 2
	_button("resume", I18n.t("RESUME RUN" if game.state == "paused" else "TRY AGAIN"), Rect2(24, 268, width, 96), _set_state.bind("playing") if game.state == "paused" else game._retry_run, true)
	_button("home", I18n.t("SAVE & TITLE" if game.state == "paused" else "TITLE / HANGAR"), Rect2(48 + width, 268, width, 96), game._go_home)
	_button("settings", I18n.t("SETTINGS"), Rect2(24, 394, width, 96), func(): settings_open = true)
	if game.state == "won":
		_button("endless", I18n.t("ENDLESS"), Rect2(48 + width, 394, width, 96), func():
			game.endless = true
			game.health = game.max_health
			game.state = "playing"
			game.save_run())

func _draw_settings() -> void:
	_heading(I18n.t("SETTINGS"))
	var width := (dimensions.x - 72) / 2
	_button("language", I18n.switch_label(), Rect2(24, 160, width, 96), func():
		if not I18n.toggle(): game.save_notice = "Settings could not be saved.")
	_button("sound", I18n.t("SOUND OFF" if game.muted else "SOUND ON"), Rect2(48 + width, 160, width, 96), game.toggle_sound)
	_button("motion", I18n.t("REDUCED EFFECTS" if game.reduced_motion else "FULL EFFECTS"), Rect2(24, 290, width, 96), game.toggle_motion)
	_button("licenses", I18n.t("LICENSES"), Rect2(48 + width, 290, width, 96), func(): legal_open = true)
	_button("privacy", I18n.t("PRIVACY POLICY"), Rect2(24, 420, width, 88), _open_store_page.bind("privacy"))
	_button("support", I18n.t("SUPPORT"), Rect2(48 + width, 420, width, 88), _open_store_page.bind("support"))
	_label(I18n.t("Could not open the browser." if link_error else "Progress is saved on this device."), Rect2(24, 525, dimensions.x - 48, 65), 24, MUTED)
	_back(func(): settings_open = false)

func store_url(page: String) -> String:
	if page not in ["privacy", "support"]:
		return ""
	return "https://sandboxwork.github.io/neon-drift/store/%s.html#%s" % [page, "ko" if I18n.locale == "ko" else "en"]

func _open_store_page(page: String) -> void:
	var url := store_url(page)
	if not url.is_empty():
		link_error = web_opener.call(url) != OK

func _draw_legal() -> void:
	_heading(I18n.t("LICENSES"))
	var text := ""
	for path in ["res://LICENSE", "res://GODOT-LICENSE.txt", "res://assets/FONT-LICENSE.txt", "res://assets/NOTO-SANS-KR-LICENSE.txt", "res://GODOT-COPYRIGHT.txt"]:
		text += path.get_file() + "\n" + FileAccess.get_file_as_string(path) + "\n\n"
	# Paginated text is reachable with touch without relying on mouse emulation.
	var lines := PackedStringArray()
	for line in text.split("\n"):
		while line.length() > 76:
			lines.append(line.left(76))
			line = line.substr(76)
		lines.append(line)
	var page_count := ceili(lines.size() / 12.0)
	legal_page = clampi(legal_page, 0, page_count - 1)
	_label("\n".join(lines.slice(legal_page * 12, (legal_page + 1) * 12)), Rect2(24, 100, dimensions.x - 48, 470), 24)
	_back(func(): legal_open = false)
	_button("previous", I18n.t("PREVIOUS"), Rect2(dimensions.x - 560, dimensions.y - 110, 250, 88), func(): legal_page = maxi(0, legal_page - 1))
	_button("next", "%s %d/%d" % [I18n.t("NEXT"), legal_page + 1, page_count], Rect2(dimensions.x - 290, dimensions.y - 110, 266, 88), func(): legal_page = mini(page_count - 1, legal_page + 1))

func _draw_playing() -> void:
	hud = _label("", Rect2(24, 4, dimensions.x - 250, 48), 30, MINT)
	mission = _label("", Rect2(24, 53, dimensions.x - 250, 45), 27)
	_button("pause", I18n.t("PAUSE"), Rect2(dimensions.x - 214, 4, 190, 88), game._on_focus_lost)
	boss = ProgressBar.new()
	boss.position = Vector2(dimensions.x * 0.3, 100)
	boss.size = Vector2(dimensions.x * 0.4, 14)
	boss.show_percentage = false
	boss.add_theme_stylebox_override("fill", _box(CORAL, CORAL))
	screen.add_child(boss)
	energy_bar = ProgressBar.new()
	energy_bar.position = Vector2(235, dimensions.y - 132)
	energy_bar.size = Vector2(dimensions.x - 470, 10)
	energy_bar.show_percentage = false
	energy_bar.add_theme_stylebox_override("fill", _box(MINT, MINT))
	screen.add_child(energy_bar)
	status = _label("", Rect2(235, dimensions.y - 106, dimensions.x - 470, 94), 25, MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls = Control.new()
	controls.size = dimensions
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.draw.connect(_draw_controls)
	screen.add_child(controls)

func joystick_center() -> Vector2:
	return Vector2(112, dimensions.y - 88)

func dash_center() -> Vector2:
	return Vector2(dimensions.x - 112, dimensions.y - 88)

func _draw_controls() -> void:
	var origin := stick_origin if stick_index >= 0 else joystick_center()
	controls.draw_circle(origin, STICK_RADIUS, Color("172f42"))
	controls.draw_arc(origin, STICK_RADIUS, 0, TAU, 48, MINT, 3, true)
	controls.draw_circle(origin + movement * 44, 23, MINT)
	var center := dash_center()
	controls.draw_circle(center, 64, MINT if game.dash_cooldown <= 0 else PANEL)
	controls.draw_arc(center, 64, 0, TAU, 48, MINT, 3, true)
	var text: String = I18n.t("DASH") if game.dash_cooldown <= 0 else "%.1f" % game.dash_cooldown
	var width: float = game.title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	controls.draw_string(game.title_font, center + Vector2(-width / 2, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, BG if game.dash_cooldown <= 0 else INK)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		handle_touch(event)
		get_viewport().set_input_as_handled()

func handle_touch(event: InputEvent) -> void:
	if dirty or portrait:
		return
	var point: Vector2 = (event.position - safe_rect.position) / ui_scale
	if event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			if event.index == stick_index:
				stick_index = -1
				movement = Vector2.ZERO
			var entry: Dictionary = touches.get(event.index, {})
			touches.erase(event.index)
			var button = entry.get("button")
			if is_instance_valid(button):
				button.modulate = Color.WHITE
				if not event.canceled and not entry.get("dragged", false) and Rect2(button.position, button.size).has_point(point):
					button.pressed.emit()
			return
		for button in buttons.values():
			if not button.disabled and Rect2(button.position, button.size).has_point(point):
				touches[event.index] = {"button": button, "start": point, "dragged": false}
				button.modulate = Color(0.75, 0.9, 1)
				return
		if game.state != "playing" or settings_open or legal_open or fleet_open:
			return
		if point.distance_to(dash_center()) <= 76:
			if movement.length_squared() > 0:
				game.facing = movement.normalized()
			game.try_dash()
		elif stick_index < 0 and Rect2(16, dimensions.y - 180, dimensions.x * 0.45 - 16, 180).has_point(point):
			stick_index = event.index
			stick_origin = point.clamp(Vector2(80, dimensions.y - 100), Vector2(dimensions.x * 0.45 - 80, dimensions.y - 80))
			_update_stick(point)
	elif event is InputEventScreenDrag:
		if event.index == stick_index:
			_update_stick(point)
		elif touches.has(event.index) and point.distance_to(touches[event.index].start) > 20:
			touches[event.index].dragged = true

func _update_stick(point: Vector2) -> void:
	var vector := (point - stick_origin) / STICK_RADIUS
	var length := vector.length()
	movement = Vector2.ZERO if length <= DEADZONE else vector.normalized() * minf(1.0, (length - DEADZONE) / (1.0 - DEADZONE))
