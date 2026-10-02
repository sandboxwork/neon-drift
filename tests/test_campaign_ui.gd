extends SceneTree
## Headless campaign UI contract and text-bounds regression probe.
## Uses the actual shipped fonts and campaign content without loading main.gd,
## creating a game, or reading/writing pilot saves. This is not a raster/layout
## screenshot test: it catches runtime contracts, screen bounds and button fits.
## Run from the project directory with disposable engine-log storage:
## DATA=$(mktemp -d /tmp/neon-drift-campaign-ui.XXXXXX)
## XDG_DATA_HOME="$DATA" godot --headless --path . --script res://tests/test_campaign_ui.gd

const UI = preload("res://campaign_ui.gd")
class DrawProbe:
	extends RefCounted
	const Campaign = preload("res://campaign.gd")
	var ui_font: Font = load("res://assets/ui.ttf")
	var title_font: Font = load("res://assets/title.ttf")
	var profile = {"credits":120,"campaign_wins":2,"sector_unlocked":0,"ship":0,"achievements":[]}
	var campaign = {"mode":true,"sector":0,"objective":3}
	var map_sector = 0
	var save_notice = ""
	var run_weapon = 0
	var overdrive = 2
	var phase_engine = 1
	var recovery = 1
	var endless = false
	var text_count = 0
	var checks = 0
	var context = ""
	var failures: Array[String] = []
	func get_global_mouse_position() -> Vector2:
		return Vector2(-100,-100)
	func _text(s: String,p: Vector2,size: int,c: Color = Color.WHITE,bold: bool = false) -> void:
		text_count += 1
		checks += 1
		var font: Font = title_font if bold else ui_font
		var w = font.get_string_size(s,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		if p.x < 0 or p.x+w > 1260 or p.y > 710 or p.y < 10:
			failures.append("%s: offscreen %s at %s width %.2f size %d" % [context,s,p,w,size])
	func _center(s: String,y: float,size: int,c: Color = Color.WHITE,bold: bool = false,x: float = 640) -> void:
		var font: Font = title_font if bold else ui_font
		_text(s,Vector2(x-font.get_string_size(s,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x*0.5,y),size,c,bold)
	func _panel(r: Rect2,f: Color = Color.BLACK,b: Color = Color.WHITE,rad: int = 12) -> void:
		checks += 1
		if r.position.x < 0 or r.end.x > 1280 or r.position.y < 0 or r.end.y > 720: failures.append(context + ": panel out of bounds")
	func _button(r: Rect2,s: String,p: bool = true) -> void:
		checks += 1
		var width = title_font.get_string_size(s,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		if width > r.size.x-12: failures.append("%s: button text overflow: %s is %.2f in %.2f" % [context,s,width,r.size.x])
		_center(s,r.position.y+r.size.y/2+6,18,Color.WHITE,true,r.get_center().x)
	func _poly(p: Vector2,r: float,s: int,a: float,f: Color,b: Color) -> void: pass
	func _ship(p: Vector2,a: float,c: Color,alpha: float,scale: float) -> void: pass
	func draw_line(a: Vector2,b: Vector2,c: Color,w: float = 1.0,aa: bool = false) -> void: pass
	func draw_circle(p: Vector2,r: float,c: Color) -> void: pass
	func draw_rect(r: Rect2,c: Color) -> void: pass

func _initialize() -> void:
	var g = DrawProbe.new()
	for unlock in range(3):
		g.profile.sector_unlocked = unlock
		for ship in range(3):
			g.profile.ship = ship
			for sector in range(3):
				g.map_sector = sector
				g.context = "map / unlocked %d / ship %d / selected %d" % [unlock,ship,sector]
				UI.draw_map(g)
	for sector in range(2):
		g.campaign.sector = sector
		g.context = "intermission / completed sector %d" % sector
		UI.draw_intermission(g)
	g.context = "journal / no achievements"
	UI.draw_journal(g)
	for achievement in g.Campaign.achievements():
		g.profile.achievements.append(achievement.id)
	g.context = "journal / all achievements"
	UI.draw_journal(g)
	for sector in range(3):
		g.campaign.sector = sector
		for weapon in range(3):
			g.run_weapon = weapon
			g.context = "HUD / sector %d / weapon %d / unevolved" % [sector,weapon]
			g.overdrive = 2
			g.recovery = 1
			g.phase_engine = 1
			UI.draw_campaign_hud(g)
			g.context = "HUD / sector %d / weapon %d / evolved" % [sector,weapon]
			g.overdrive = 3
			g.recovery = 2
			g.phase_engine = 2
			UI.draw_campaign_hud(g)
	# The campaign HUD must not leak into old survival or endless runs.
	var before: int = g.text_count
	g.endless = true
	UI.draw_campaign_hud(g)
	g.checks += 1
	if g.text_count != before: g.failures.append("HUD appears in endless mode")
	g.endless = false
	g.campaign.mode = false
	UI.draw_campaign_hud(g)
	g.checks += 1
	if g.text_count != before: g.failures.append("HUD appears with campaign mode disabled")
	g.campaign = {}
	UI.draw_campaign_hud(g)
	g.checks += 1
	if g.text_count != before: g.failures.append("HUD appears without a campaign")
	print("Validated %d text draw calls across map, intermission, journal, HUD." % g.text_count)
	print("Campaign UI: %d bounds/contract checks, %d failures" % [g.checks,g.failures.size()])
	for failure in g.failures: printerr(failure)
	print("FAILURES: ",g.failures.size())
	quit(0 if g.failures.is_empty() else 1)
