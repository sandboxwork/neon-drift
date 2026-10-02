extends RefCounted
## Draw-only campaign presentation. Input and all game state belong to main.gd.

const INK := Color("e9f3ff")
const MUTED := Color("8da1b8")
const MINT := Color("64ffda")
const BLUE := Color("7b9dff")
const CORAL := Color("ff687d")
const GOLD := Color("ffcc7a")
const PANEL := Color("101b2d")
const EDGE := Color("2b4058")


static func draw_map(g) -> void:
	g._text("E X P E D I T I O N   /   N A V I G A T I O N",Vector2(80,62),12,MINT)
	g._text("CHART YOUR SIGNAL",Vector2(77,116),42,INK,true)
	g._text("Three sectors. One evolving ship. Push through to the source.",Vector2(80,148),16,MUTED)
	g._text("%d CORES  /  %d CAMPAIGN CLEARS" % [g.profile.credits,g.profile.campaign_wins],Vector2(816,105),12,GOLD)
	for i in range(3):
		var sector: Dictionary = g.Campaign.sector(i)
		var rect := Rect2(80+i*400,190,360,210)
		var color := Color(sector.get("color","64ffda"))
		var unlocked: bool = i <= g.profile.sector_unlocked
		var selected: bool = i == g.map_sector
		var hover: bool = rect.has_point(g.get_global_mouse_position())
		var border: Color = color if selected else (Color(color,0.65) if hover and unlocked else EDGE)
		g._panel(rect,Color("14283b") if selected else PANEL,border,12)
		g.draw_line(rect.position+Vector2(16,1),rect.position+Vector2(344,1),color if unlocked else MUTED,2.0,true)
		g._text("0%d / %s" % [i+1,"SELECTED" if selected and unlocked else ("AVAILABLE" if unlocked else "LOCKED")],rect.position+Vector2(21,31),12,color if unlocked else MUTED,true)
		g._poly(rect.position+Vector2(323,32),11,4+i,PI*0.25,Color(color,0.08),color if unlocked else MUTED)
		_fit_text(g,str(sector.get("name","SECTOR %d" % (i+1))),rect.position+Vector2(20,73),28,317,INK if unlocked else MUTED,true)
		_fit_text(g,str(sector.get("subtitle","")),rect.position+Vector2(21,97),13,317,color if unlocked else MUTED)
		_wrapped(g,str(sector.get("briefing","")),rect.position+Vector2(21,121),12,318,15,4,MUTED)
		var objective := str(sector.get("objective_label","OBJECTIVE"))
		var target := int(sector.get("objective_target",0))
		_fit_text(g,"%s / %d" % [objective,target] if unlocked else "Clear sector %02d to unlock" % i,rect.position+Vector2(21,179),12,317,color if unlocked else MUTED)
		_fit_text(g,"GUARDIAN / " + str(sector.get("boss_name","UNKNOWN")),rect.position+Vector2(21,198),10,317,MUTED)
		if i < 2:
			g.draw_line(Vector2(rect.end.x+9,294),Vector2(rect.end.x+30,294),Color(MINT,0.65) if i < g.profile.sector_unlocked else EDGE,2,true)
			g.draw_line(Vector2(rect.end.x+24,289),Vector2(rect.end.x+30,294),Color(MINT,0.65) if i < g.profile.sector_unlocked else EDGE,2,true)
			g.draw_line(Vector2(rect.end.x+24,299),Vector2(rect.end.x+30,294),Color(MINT,0.65) if i < g.profile.sector_unlocked else EDGE,2,true)
	var ship: Dictionary = g.Campaign.ship(int(g.profile.ship))
	var ship_color := Color(ship.get("color","64ffda"))
	var ship_rect := Rect2(80,430,720,58)
	g._panel(ship_rect,Color("172a3c") if ship_rect.has_point(g.get_global_mouse_position()) else PANEL,ship_color,8)
	g._ship(Vector2(112,459),-0.25,ship_color,1.0,0.7)
	g._text(str(ship.get("name","SHIP")) + " / " + str(ship.get("role","")),Vector2(148,454),15,ship_color,true)
	_fit_text(g,str(ship.get("description","")),Vector2(148,475),12,536,MUTED)
	g._text("[S]",Vector2(750,465),17,INK,true)
	var can_launch: bool = int(g.map_sector) <= int(g.profile.sector_unlocked)
	if can_launch:
		g._button(Rect2(850,430,350,58),"LAUNCH SECTOR %02d / ENTER" % (int(g.map_sector)+1))
	else:
		g._panel(Rect2(850,430,350,58),PANEL,EDGE,8)
		g._center("SECTOR LOCKED",465,17,MUTED,true,1025)
	g._text("FLEET UNLOCKS / Sector 01: KESTREL  |  Sector 02: BASTION",Vector2(80,509),11,MUTED)
	g._button(Rect2(80,520,340,48),"PILOT JOURNAL / J",false)
	g._button(Rect2(860,520,340,48),"BACK TO TITLE / ESC",false)
	if int(g.map_sector) > 0:
		g._center("PRACTICE START: earlier sectors, their build and relic rewards are skipped.",608,13,GOLD)
		g._center("For a full campaign clear, launch sector 01 and claim all three sectors in one run.",630,13,MUTED)
	else:
		g._center("Your build travels with you. Choose a relic after each of the first two guardians.",608,13,MUTED)
		g._center("Claim all three sectors in one expedition to complete the campaign.",630,13,MINT)
	_footer(g,"1 / 2 / 3  SELECT SECTOR", "S  CYCLE SHIP", "ENTER  LAUNCH", "J  JOURNAL    ESC  BACK")
	if not g.save_notice.is_empty():
		g._center(g.save_notice,177,12,CORAL)


static func draw_intermission(g) -> void:
	g.draw_rect(Rect2(0,0,1280,720),Color(0.015,0.027,0.055,0.94))
	var sector: Dictionary = g.Campaign.sector(int(g.campaign.get("sector",0)))
	var color := Color(sector.get("color","64ffda"))
	g._center("S E C T O R   S I G N A L   S E C U R E D",146,12,color)
	_fit_center(g,str(sector.get("name","SECTOR")) + " CLEARED",199,38,1080,INK,true)
	g._center("CHOOSE A RELIC",242,21,color,true)
	g._center("Your build carries forward. Choosing a relic launches the next sector.",266,13,MUTED)
	var names := ["HELIX REACTOR", "PHASE CAPACITOR", "REPAIR MATRIX"]
	var bonuses := ["+0.5 projectile damage", "+1 phase rank", "+1 maximum hull"]
	var descriptions := ["A permanent boost for this expedition.", "More speed. Faster dash recovery.", "Fully repairs your hull immediately."]
	var colors := [MINT,BLUE,GOLD]
	for i in range(3):
		var rect := Rect2(178+i*314,285,296,190)
		var hover: bool = rect.has_point(g.get_global_mouse_position())
		g._panel(rect,Color("172d43") if hover else PANEL,colors[i] if hover else EDGE,12)
		g.draw_line(rect.position+Vector2(15,1),rect.position+Vector2(281,1),colors[i],2,true)
		g._text("0%d / RELIC" % (i+1),rect.position+Vector2(20,31),12,colors[i],true)
		g._poly(rect.position+Vector2(256,34),15,4+i,PI*0.25,Color(colors[i],0.08),colors[i])
		g._poly(rect.position+Vector2(256,34),6,4+i,-PI*0.25,Color(colors[i],0.25),INK)
		_fit_text(g,names[i],rect.position+Vector2(20,79),21,256,INK,true)
		g._text(bonuses[i],rect.position+Vector2(20,111),16,colors[i])
		_wrapped(g,descriptions[i],rect.position+Vector2(20,136),12,255,17,2,MUTED)
		g._text("SELECT / %d" % (i+1),rect.position+Vector2(20,173),12,colors[i],true)
	g._center("Click a relic or press 1, 2, 3. The arena stays paused until you choose.",516,13,MUTED)
	g._button(Rect2(468,550,344,44),"SAVE & TITLE / ESC",false)
	g._center("Resume this expedition later to choose your relic and continue.",622,12,MUTED)
	if not g.save_notice.is_empty():
		g._center(g.save_notice,652,12,CORAL)


static func draw_journal(g) -> void:
	g._text("P I L O T   A R C H I V E   /   P R O G R E S S I O N",Vector2(80,62),12,MINT)
	g._text("THE SIGNAL JOURNAL",Vector2(77,116),42,INK,true)
	var achievements: Array = g.Campaign.achievements()
	g._text("%d / %d ACHIEVEMENTS  /  %d CAMPAIGN CLEARS" % [g.profile.achievements.size(),achievements.size(),g.profile.campaign_wins],Vector2(80,150),14,GOLD)
	g._text("PILOT MILESTONES",Vector2(80,189),13,MINT,true)
	g._text("WEAPON EVOLUTION RECIPES",Vector2(685,189),13,BLUE,true)
	for i in range(mini(6,achievements.size())):
		var achievement: Dictionary = achievements[i]
		var earned: bool = g.profile.achievements.has(achievement.get("id",""))
		var rect := Rect2(80,203+i*59,550,52)
		g._panel(rect,Color("122737") if earned else PANEL,Color(MINT,0.45) if earned else EDGE,7)
		g._poly(rect.position+Vector2(23,26),9,4,PI*0.25,Color(MINT,0.2) if earned else Color(MUTED,0.05),MINT if earned else MUTED)
		_fit_text(g,str(achievement.get("name",achievement.get("title","MILESTONE"))),rect.position+Vector2(45,22),14,409,INK if earned else MUTED,true)
		_fit_text(g,str(achievement.get("description",achievement.get("desc",""))),rect.position+Vector2(45,41),11,478,MUTED)
		g._text("EARNED" if earned else "LOCKED",rect.position+Vector2(465,22),10,MINT if earned else MUTED)
	_draw_recipes(g)
	g._button(Rect2(468,589,344,48),"BACK TO MAP / ESC",false)
	_footer(g,"ACHIEVEMENTS PERSIST", "RECIPES APPLY PER RUN", "BUILD RANKS TO EVOLVE", "ESC  BACK TO MAP")


static func draw_campaign_hud(g) -> void:
	if g.campaign.is_empty() or not g.campaign.get("mode",false) or g.endless:
		return
	var sector: Dictionary = g.Campaign.sector(int(g.campaign.get("sector",0)))
	var color := Color(sector.get("color","64ffda"))
	var target := int(sector.get("objective_target",1))
	var value := mini(int(g.campaign.get("objective",0)),target)
	var objective := "%s %d/%d" % [str(sector.get("objective_label","OBJECTIVE")),value,target]
	g._panel(Rect2(320,211,640,31),Color(0.035,0.07,0.12,0.93),Color(color,0.3),5)
	g.draw_circle(Vector2(332,226),3.0,color)
	_fit_text(g,objective,Vector2(343,231),11,295,color)
	g.draw_line(Vector2(649,218),Vector2(649,235),EDGE,1,true)
	_fit_text(g,_evolution_label(g),Vector2(663,231),11,283,BLUE)


static func _evolution_label(g) -> String:
	var evolution: String = g.Campaign.evolution(g.run_weapon,g.overdrive,g.phase_engine,g.recovery)
	if not evolution.is_empty():
		return "EVOLVED / " + evolution
	if int(g.run_weapon) == 1:
		return "EVO / OVERDRIVE %d/3 + PHASE %d/2" % [mini(g.overdrive,3),mini(g.phase_engine,2)]
	return "EVO / OVERDRIVE %d/3 + RECOVERY %d/2" % [mini(g.overdrive,3),mini(g.recovery,2)]


static func _draw_recipes(g) -> void:
	var names := ["PULSE > NOVA ARRAY", "FAN > STARWEAVE", "LANCE > VOID LANCE"]
	var details := ["Overdrive rank 3 + Recovery rank 2", "Overdrive rank 3 + Phase Engine rank 2", "Overdrive rank 3 + Recovery rank 2"]
	var notes := ["A wide nova pulses every 2.5 seconds.", "Eight radial stars join every volley.", "Heavy plasma pierces successive enemies."]
	for i in range(3):
		var rect := Rect2(685,203+i*108,515,98)
		var color: Color = [MINT,BLUE,GOLD][i]
		g._panel(rect,PANEL,Color(color,0.38),9)
		g._text("0%d" % (i+1),rect.position+Vector2(17,28),12,color,true)
		g._text(names[i],rect.position+Vector2(50,28),17,INK,true)
		g._text(details[i],rect.position+Vector2(20,57),13,color)
		g._text(notes[i],rect.position+Vector2(20,79),12,MUTED)
	g._text("Evolves automatically with the matching weapon equipped.",Vector2(685,547),12,MUTED)


static func _footer(g, first: String, second: String, third: String, fourth: String) -> void:
	g.draw_line(Vector2(32,659),Vector2(1248,659),Color("203047"),1)
	g._text(first,Vector2(48,695),12,MUTED)
	g._text(second,Vector2(367,695),12,MUTED)
	g._text(third,Vector2(648,695),12,MUTED)
	g._text(fourth,Vector2(971,695),11,MUTED)


static func _fit_text(g, value: String, pos: Vector2, size: int, width: float, color: Color, bold: bool = false) -> void:
	var font: Font = g.title_font if bold else g.ui_font
	var actual_size := size
	while actual_size > 10 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x > width:
		actual_size -= 1
	if font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x > width:
		while value.length() > 0 and font.get_string_size(value+"...",HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x > width:
			value = value.left(value.length()-1)
		value += "..."
	g._text(value,pos,actual_size,color,bold)


static func _fit_center(g, value: String, y: float, size: int, width: float, color: Color, bold: bool = false) -> void:
	var font: Font = g.title_font if bold else g.ui_font
	while size > 12 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > width:
		size -= 1
	g._center(value,y,size,color,bold)


static func _wrapped(g, value: String, pos: Vector2, size: int, width: float, line_height: float, max_lines: int, color: Color) -> void:
	var words := value.split(" ",false)
	var line := ""
	var row := 0
	for word in words:
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and g.ui_font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > width:
			g._text(line,pos+Vector2(0,row*line_height),size,color)
			row += 1
			if row >= max_lines:
				return
			line = word
		else:
			line = candidate
	if not line.is_empty() and row < max_lines:
		_fit_text(g,line,pos+Vector2(0,row*line_height),size,width,color)
