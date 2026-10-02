extends RefCounted
## Campaign rules are separate from the legacy survival expedition.

static func fresh(sector: int, ship: int) -> Dictionary:
	return {"mode":true,"sector":sector,"sector_time":0.0,"objective":0,"objective_clock":0.0,"ship":ship,"claimed":[],"intermission":false,"hazards":[],"relics":[],"total_time":0.0}

static func active(g) -> bool:
	return not g.campaign.is_empty() and g.campaign.get("mode",false) and not g.endless

static func objective_position(g) -> Vector2:
	var points := [Vector2(230,260),Vector2(1030,480),Vector2(260,500),Vector2(1020,250),Vector2(640,380)]
	return points[g.campaign.objective % points.size()]

static func tick(g, delta: float) -> void:
	var c: Dictionary = g.campaign
	var sector: Dictionary = g.Campaign.sector(c.sector)
	c.sector_time += delta
	c.total_time += delta
	# Missions require navigating across the arena, rather than waiting out a clock.
	var target: Vector2 = relay_position(g) if c.sector == 1 else objective_position(g)
	if c.objective < sector.objective_target:
		var radius := 66.0 if c.sector == 1 else 30.0
		if g.player.distance_to(target) < radius:
			c.objective_clock += delta
			var needed := 1.0 if c.sector == 1 else 0.35
			if c.objective_clock >= needed:
				c.objective_clock = 0.0
				c.objective += 1
				g.score += 25
				g._ring(target,Color(sector.color),75,0.5)
				g._sound("gem")
		else:
			c.objective_clock = maxf(0.0,c.objective_clock-delta*0.5)
	# Bounded, readable hazards. All damage circles telegraph before activating.
	for i in range(c.hazards.size()-1,-1,-1):
		var h: Dictionary = c.hazards[i]
		h.warning = maxf(-0.5,h.warning-delta)
		h.life -= delta
		if h.life <= 0:
			c.hazards.remove_at(i)
			continue
		if h.warning <= 0:
			if c.sector == 2 and g.dash_left <= 0:
				var distance: float = g.player.distance_to(h.p)
				if distance < h.r*2.2 and distance > 8:
					g.player = g.player.move_toward(h.p,28*delta)
			if g.player.distance_to(h.p) < h.r+10 and g.invulnerable <= 0 and g.dash_left <= 0:
				g._damage_player()
				if g.state != "playing": return
	if int(c.sector_time / sector.hazard_interval) > int((c.sector_time-delta) / sector.hazard_interval):
		add_hazard(g,g.player,sector.hazard_radius,sector.hazard_warning,sector.hazard_duration)
	if c.sector_time >= sector.boss_time and not g.boss_spawned:
		g._spawn_boss()
	if g.boss_defeated and c.objective >= sector.objective_target:
		complete(g)

static func relay_position(g) -> Vector2:
	var points := [Vector2(230,260),Vector2(1030,480),Vector2(260,500),Vector2(1020,250),Vector2(640,380)]
	return points[(g.campaign.objective / 6) % points.size()]

static func add_hazard(g, pos: Vector2, radius: float, warning: float, duration: float) -> void:
	if g.campaign.hazards.size() >= 36: return
	g.campaign.hazards.append({"p":pos.clamp(Vector2(65,145),Vector2(1210,600)),"r":radius,"warning":warning,"life":warning+duration})

static func boss_attack(g, e: Dictionary) -> void:
	var sector: int = g.campaign.sector
	var angle: float = (g.player-e.p).angle()
	if sector == 0:
		for i in range(3): add_hazard(g,e.p+Vector2.RIGHT.rotated(angle+(i-1)*0.36)*180,42,1.2,0.65)
	elif sector == 1:
		for i in range(6): add_hazard(g,e.p+Vector2.RIGHT.rotated(i*TAU/6+e.age*0.08)*160,38,1.1,0.8)
	else:
		for i in range(5): add_hazard(g,g.player+Vector2.RIGHT.rotated(e.age*0.5+i*TAU/5)*115,32,1.35,0.75)

static func complete(g) -> void:
	var c: Dictionary = g.campaign
	if c.sector in c.claimed: return
	c.claimed.append(c.sector)
	var sector: Dictionary = g.Campaign.sector(c.sector)
	g.profile.credits += sector.reward
	g.earned_credits += sector.reward
	g.profile.sector_unlocked = maxi(g.profile.sector_unlocked,mini(2,c.sector+1))
	if c.sector < 2:
		g.profile.award_achievement("first_sector" if c.sector == 0 else "second_sector",15 if c.sector == 0 else 25)
		c.intermission = true
		c.hazards.clear()
		g.state = "intermission"
		g.save_run()
	else:
		if c.claimed.size() == 3:
			g.profile.campaign_wins += 1
			g.profile.award_achievement("campaign_clear",50)
		g.finish_game(true)

static func choose_relic(g, choice: int) -> void:
	if g.state != "intermission" or choice < 0 or choice > 2: return
	g.campaign.relics.append(choice)
	match choice:
		0: g.damage_bonus += 0.5
		1: g.phase_engine += 1
		2: g.max_health += 1
	g._check_evolution()
	g.health = g.max_health
	g.campaign.sector += 1
	g.campaign.sector_time = 0.0
	g.campaign.objective = 0
	g.campaign.objective_clock = 0.0
	g.campaign.intermission = false
	g.campaign.hazards.clear()
	g.boss_spawned = false
	g.boss_defeated = false
	g.enemies.clear()
	g.bolts.clear()
	g.gems.clear()
	g.player = g.ARENA.get_center()
	g.previous_player = g.player
	g.invulnerable = 2.0
	g.state = "playing"
	g.toast = "JUMP COMPLETE / " + g.Campaign.sector(g.campaign.sector).name
	g.toast_timer = 3.0
	g.save_run()

static func draw_world(g) -> void:
	var c: Dictionary = g.campaign
	var sector: Dictionary = g.Campaign.sector(c.sector)
	var color := Color(sector.color)
	g.draw_rect(g.ARENA,Color(color,0.025))
	if c.objective < sector.objective_target:
		var pos: Vector2 = relay_position(g) if c.sector == 1 else objective_position(g)
		var radius := 66.0 if c.sector == 1 else 30.0
		g.draw_circle(pos,radius,Color(color,0.09))
		g.draw_arc(pos,radius,0,TAU,48,color,2,true)
		g._poly(pos,13,6,g.ambient_time*0.3,Color(color,0.15),color)
		g._center("CHARGE RELAY" if c.sector == 1 else "SALVAGE" if c.sector == 2 else "LINK BEACON",pos.y+radius+18,11,color,false,pos.x)
		g.draw_arc(pos,radius+5,-PI/2,-PI/2+TAU*clampf(c.objective_clock/(1.0 if c.sector==1 else 0.35),0,1),32,g.INK,3,true)
	for h in c.hazards:
		var warning: bool = h.warning > 0
		g.draw_circle(h.p,h.r,Color(g.CORAL,0.07 if warning else 0.26))
		g.draw_arc(h.p,h.r,0,TAU,32,g.GOLD if warning else g.CORAL,1.5 if warning else 3.0,true)
		g.draw_line(h.p-Vector2(6,6),h.p+Vector2(6,6),g.GOLD if warning else g.CORAL,2,true)
		g.draw_line(h.p-Vector2(6,-6),h.p+Vector2(6,-6),g.GOLD if warning else g.CORAL,2,true)
