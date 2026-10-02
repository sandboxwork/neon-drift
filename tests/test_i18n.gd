extends SceneTree
## Korean localization regression suite. Run only in a disposable save directory:
## NEON_DRIFT_TEST_SAVE=1 XDG_DATA_HOME=$(mktemp -d /tmp/neon-drift-i18n.XXXXXX) \
## godot --headless --path . --script res://tests/test_i18n.gd
## Draws every screen through the real main.gd renderer and checks that Korean
## mode leaves no untranslated English, all text fits, and every glyph exists.

const I18n = preload("res://i18n.gd")
const Campaign = preload("res://campaign.gd")
const SOURCES := ["res://main.gd", "res://campaign_ui.gd", "res://campaign_runtime.gd"]
## Latin words that intentionally stay in Korean mode: logo, key caps, and the
## language-switch label. Single letters (key hints) are always allowed.
const ALLOWED_LATIN := ["NEON", "DRIFT", "WASD", "ESC", "ENTER", "SPACE", "MK", "IV", "ENGLISH"]
const SPEC := "%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[a-zA-Z%]"

var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var ui_font: Font = load("res://assets/ui.ttf")
var title_font: Font = load("res://assets/title.ttf")
var game


func _initialize() -> void:
	var directory := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("NEON_DRIFT_TEST_SAVE") != "1" or not directory.begins_with("/tmp/"):
		printerr("Set NEON_DRIFT_TEST_SAVE=1 and a disposable /tmp XDG_DATA_HOME to run localization tests.")
		quit(2)
		return
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func _run() -> void:
	check(not ui_font.has_char("한".unicode_at(0)), "DejaVu alone has no Hangul (fallback is required)")
	I18n.install_fonts(ui_font, title_font)
	I18n.install_fonts(ui_font, title_font)
	check(ui_font.fallbacks.size() == 1 and title_font.fallbacks.size() == 1, "Korean fallback installs once")
	_check_table()
	_check_glyphs()
	_check_source_keys()
	_check_content_keys()
	await _check_screens()
	await _check_toggle()
	I18n.recorder = Callable()
	print("Localization: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _specs(text: String) -> Array:
	var regex := RegEx.create_from_string(SPEC)
	var found := []
	for match in regex.search_all(text):
		found.append(match.get_string())
	return found


func _check_table() -> void:
	var hangul := RegEx.create_from_string("[가-힣]")
	for key in I18n.KO:
		var value: String = I18n.KO[key]
		check(_specs(key) == _specs(value), "format specifiers match: " + key)
		check(hangul.search(value) != null, "translation contains Hangul: " + key)
	I18n.locale = "en"
	for key in I18n.KO:
		check(I18n.t(key) == key, "English mode returns source text: " + key)
	check(I18n.notice("Could not write the pilot save (File not found).") == "Could not write the pilot save (File not found).", "English notice is unchanged")
	I18n.locale = "ko"
	check(I18n.notice("Could not write the pilot save (File not found).") == "파일럿 저장을 기록하지 못했습니다 (File not found).", "Korean notice keeps engine error detail")
	check(I18n.notice("") == "", "empty notice stays empty")
	check(I18n.f("RANK %d / 5", 3) == "등급 3 / 5", "Korean template formats arguments")


func _check_glyphs() -> void:
	check(ui_font.has_char("한".unicode_at(0)) and title_font.has_char("한".unicode_at(0)), "shipped fonts carry Korean fallback")
	var missing := {}
	var texts: Array = I18n.KO.values() + I18n.SWITCH_LABEL.values()
	for text in texts:
		for i in range(text.length()):
			var code: int = text.unicode_at(i)
			if code == 32: continue
			for font in [ui_font, title_font]:
				if not font.has_char(code): missing[text[i]] = true
	check(missing.is_empty(), "every translated character has a glyph: missing %s" % [missing.keys()])


## Every literal passed to I18n.t / f / notice must have a Korean entry.
func _check_source_keys() -> void:
	var literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var identifier := RegEx.create_from_string("^[a-z_]+$")
	var letters := RegEx.create_from_string("[A-Za-z]{2,}")
	for path in SOURCES:
		var source := FileAccess.get_file_as_string(path)
		var start := source.find("I18n.")
		while start >= 0:
			var open := source.find("(", start)
			var name := source.substr(start + 5, open - start - 5)
			if name in ["t", "f", "notice"]:
				var close := _matching_paren(source, open)
				for match in literal.search_all(source.substr(open, close - open)):
					var value := match.get_string(1)
					if letters.search(value) != null and identifier.search(value) == null:
						check(I18n.KO.has(value), "%s: translation key exists: %s" % [path.get_file(), value])
			start = source.find("I18n.", start + 5)
	# Notices are stored in English and translated on display.
	for path in ["res://progression.gd", "res://main.gd"]:
		var notices := RegEx.create_from_string("(?:last_error|save_notice) = (?:\"\" if [^\"]+ else )?\"([^\"]+)\"")
		for match in notices.search_all(FileAccess.get_file_as_string(path)):
			check(I18n.KO.has(match.get_string(1)), "%s: notice has translation: %s" % [path.get_file(), match.get_string(1)])


func _matching_paren(source: String, open: int) -> int:
	var depth := 0
	var quoted := false
	for i in range(open, source.length()):
		var character := source[i]
		if character == "\"" and source[i - 1] != "\\":
			quoted = not quoted
		elif not quoted and character == "(":
			depth += 1
		elif not quoted and character == ")":
			depth -= 1
			if depth == 0:
				return i
	return source.length()


func _check_content_keys() -> void:
	for sector in Campaign.SECTORS:
		for field in ["name", "subtitle", "briefing", "objective_label", "boss_name"]:
			check(I18n.KO.has(sector[field]), "sector %d %s translated" % [sector.id, field])
	for ship in Campaign.SHIPS:
		for field in ["name", "role", "description"]:
			check(I18n.KO.has(ship[field]), "ship %d %s translated" % [ship.id, field])
	for achievement in Campaign.ACHIEVEMENTS:
		for field in ["name", "description"]:
			check(I18n.KO.has(achievement[field]), "achievement %s %s translated" % [achievement.id, field])
	for weapon in Campaign.EVOLUTION_REQUIREMENTS:
		check(I18n.KO.has(Campaign.EVOLUTION_REQUIREMENTS[weapon].name), "evolution %d name translated" % weapon)


func _record(event: Dictionary) -> void:
	events.append(event)


func _frame() -> void:
	events.clear()
	await process_frame
	await process_frame


func _verify(context: String) -> void:
	check(not events.is_empty(), context + ": screen drew text")
	var latin := RegEx.create_from_string("[A-Za-z]{2,}")
	for event in events:
		var text: String = event.text
		if event.has("button"):
			var rect: Rect2 = event.button
			var width := title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			check(width <= rect.size.x - 12, "%s: button text fits: %s (%.1f in %.1f)" % [context, text, width, rect.size.x])
			continue
		var font: Font = title_font if event.bold else ui_font
		var pos: Vector2 = event.pos
		var right: float = pos.x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, event.size).x
		check(pos.x >= 0 and right <= 1270 and pos.y >= 10 and pos.y <= 715, "%s: on screen: %s (x %.0f..%.0f, y %.0f)" % [context, text, pos.x, right, pos.y])
		check(not text.ends_with("..."), "%s: text is not truncated: %s" % [context, text])
		if I18n.locale == "ko":
			var stripped := text
			for word in ALLOWED_LATIN:
				stripped = stripped.replace(word, "")
			check(latin.search(stripped) == null, "%s: no untranslated English: %s" % [context, text])


func _screen(context: String) -> void:
	await _frame()
	_verify("%s [%s]" % [context, I18n.locale])


func _check_screens() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	I18n.recorder = _record
	for locale in ["ko", "en"]:
		I18n.locale = locale
		await _drive_screens()
	I18n.locale = "ko"


func _drive_screens() -> void:
	var g = game
	g.profile.run = {}
	g.profile.credits = 240
	g.profile.total_kills = 320
	g.best_score = 12345
	g.save_notice = ""
	g.state = "menu"
	await _screen("title")
	g.save_notice = "Recovered your pilot from the backup save."
	await _screen("title with save notice")
	g.save_notice = ""
	g.start_game()
	g.state = "paused"
	g.save_run()
	g.state = "menu"
	await _screen("title with suspended run")
	g.state = "hangar"
	for weapon in range(3):
		g.profile.weapon = weapon
		await _screen("hangar weapon %d" % weapon)
	g.profile.hull_rank = 5
	await _screen("hangar maxed rank")
	g.profile.hull_rank = 0
	g.state = "sector_map"
	for unlocked in range(3):
		g.profile.sector_unlocked = unlocked
		for sector in range(3):
			g.map_sector = sector
			g.profile.ship = mini(sector, unlocked)
			await _screen("map unlocked %d selected %d" % [unlocked, sector])
	g.state = "journal"
	g.profile.achievements.clear()
	await _screen("journal empty")
	for achievement in Campaign.ACHIEVEMENTS:
		g.profile.achievements.append(achievement.id)
	await _screen("journal complete")
	# Legacy survival HUD, Endless, Warden and level-8 nova.
	g.start_game()
	g.level = 8
	await _screen("survival HUD")
	g._spawn_boss()
	g.invulnerable = 99.0
	await _screen("survival Warden")
	g.endless = true
	await _screen("survival Endless")
	g.dash_cooldown = 1.2
	g.state = "paused"
	await _screen("paused")
	g.save_notice = "Saved run cannot be read. Start a new expedition."
	await _screen("paused with notice")
	g.save_notice = ""
	g.state = "upgrade"
	await _screen("level-up choice")
	for i in range(3):
		g.state = "upgrade"
		g.choose_upgrade(i)
		g.state = "paused"
		g.toast_timer = 3.0
		g.state = "playing"
		g.invulnerable = 99.0
		await _screen("upgrade toast %d" % i)
	g.state = "lost"
	await _screen("defeat")
	g.state = "won"
	await _screen("survival victory")
	g.state = "confirm_new"
	await _screen("replace run confirmation")
	# Campaign: every sector, ship and weapon with objective, boss and evolution text.
	g.profile.sector_unlocked = 2
	for sector in range(3):
		g.profile.ship = sector
		g.start_campaign(sector)
		g.invulnerable = 99.0
		for weapon in range(3):
			g.run_weapon = weapon
			g.overdrive = 3 if weapon == sector else 1
			g.recovery = 2
			g.phase_engine = 2
			await _screen("campaign sector %d weapon %d" % [sector, weapon])
		g._spawn_boss()
		g.invulnerable = 99.0
		await _screen("campaign sector %d guardian" % sector)
		g._check_evolution()
		g.toast_timer = 3.0
		await _screen("campaign sector %d evolution toast" % sector)
	for sector in range(2):
		g.campaign.sector = sector
		g.state = "intermission"
		await _screen("relic choice after sector %d" % sector)
	g.state = "intermission"
	g.campaign.sector = 0
	g.CampaignRuntime.choose_relic(g, 0)
	g.invulnerable = 99.0
	await _screen("jump toast")
	g.campaign.claimed = [0, 1, 2]
	g.state = "won"
	await _screen("campaign victory")
	g.campaign.claimed = [0]
	await _screen("sector victory")
	g.state = "menu"


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._unhandled_input(event)


func _check_toggle() -> void:
	game.state = "menu"
	I18n.locale = "ko"
	var save_before := FileAccess.get_file_as_string("user://progression.cfg")
	_key(KEY_L)
	check(I18n.locale == "en", "L switches Korean to English")
	await _frame()
	var footer := ""
	for event in events:
		if str(event.text).begins_with("ESC PAUSE"): footer = event.text
	check(footer.ends_with("L 한국어"), "English footer offers Korean: " + footer)
	I18n.locale = "ko"
	I18n.load_settings()
	check(I18n.locale == "en", "language choice persists")
	_key(KEY_L)
	check(I18n.locale == "ko", "L switches back to Korean")
	I18n.locale = "en"
	I18n.load_settings()
	check(I18n.locale == "ko", "Korean choice persists")
	check(FileAccess.get_file_as_string("user://progression.cfg") == save_before, "language switch does not touch the pilot save")
	var config := ConfigFile.new()
	config.set_value("display", "locale", "xx")
	config.save(I18n.SETTINGS_PATH)
	I18n.load_settings()
	check(I18n.locale == "ko", "unknown stored language is ignored")
	game.queue_free()
