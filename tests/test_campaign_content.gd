extends SceneTree
## Read-only content contract tests. No pilot save or game scene is instantiated,
## so NEON_DRIFT_TEST_SAVE is not required. A disposable data directory is still
## recommended for Godot's own logs:
## XDG_DATA_HOME=/tmp/neon-drift-content-tests \
## godot --headless --path . --script res://tests/test_campaign_content.gd

const Campaign = preload("res://campaign.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)


func _initialize() -> void:
	check(Campaign.SECTORS.size() == 3, "three sectors")
	check(Campaign.SHIPS.size() == 3, "three ships")
	var objectives: Array[String] = []
	var hazards: Array[String] = []
	var bosses: Array[String] = []
	for id in range(3):
		var sector: Dictionary = Campaign.sector(id)
		check(sector.id == id, "sector ID")
		check(sector.duration == 180.0 and sector.boss_time == 135.0, "three-minute sector timing")
		check(sector.objective_target > 0, "positive objective")
		check(sector.boss_time < sector.duration, "boss before extraction")
		check(sector.hazard_warning >= 1.4 and sector.hazard_duration > 0.0, "hazards telegraphed")
		check(sector.hazard_interval > sector.hazard_duration + sector.hazard_warning, "hazard breathing room")
		check(sector.reward > 0 and sector.boss_hp > 0.0, "positive sector values")
		check(Color.html_is_valid(sector.color) and Color.html_is_valid(sector.bg_color), "valid sector colors")
		check(not objectives.has(sector.objective), "distinct objective")
		check(not hazards.has(sector.hazard), "distinct hazard")
		check(not bosses.has(sector.boss_pattern), "distinct boss")
		objectives.append(sector.objective)
		hazards.append(sector.hazard)
		bosses.append(sector.boss_pattern)
		sector.name = "mutated"
		check(Campaign.sector(id).name != "mutated", "sector copy isolation")
		var ship: Dictionary = Campaign.ship(id)
		check(ship.id == id and ship.unlock_sector == id, "ship unlock order")
		check(Color.html_is_valid(ship.color), "valid ship color")
		check(ship.speed_mult > 0 and ship.damage_mult > 0 and ship.dash_mult > 0, "positive ship multipliers")
		ship.name = "mutated"
		check(Campaign.ship(id).name != "mutated", "ship copy isolation")
	check(Campaign.ship(0).hull_bonus == 0 and Campaign.ship(0).speed_mult == 1.0, "starter balanced")
	check(Campaign.ship(1).hull_bonus < 0 and Campaign.ship(1).speed_mult > 1.0 and Campaign.ship(1).dash_mult < 1.0, "interceptor fast fragile")
	check(Campaign.ship(2).hull_bonus > 0 and Campaign.ship(2).speed_mult < 1.0, "tank slow durable")
	check(Campaign.sector(-1).id == 0 and Campaign.sector(99).id == 2, "sector clamp")
	check(Campaign.ship(-1).id == 0 and Campaign.ship(99).id == 2, "ship clamp")
	for weapon in range(3):
		for overdrive in range(6):
			for phase in range(6):
				for recovery in range(6):
					var expected := ""
					if overdrive >= 3:
						if weapon == 0 and recovery >= 2: expected = "NOVA ARRAY"
						if weapon == 1 and phase >= 2: expected = "STARWEAVE"
						if weapon == 2 and recovery >= 2: expected = "VOID LANCE"
					check(Campaign.evolution(weapon, overdrive, phase, recovery) == expected, "evolution %s %s %s %s" % [weapon, overdrive, phase, recovery])
	check(Campaign.evolution(-1, 100, 100, 100) == "" and Campaign.evolution(3, 100, 100, 100) == "", "invalid weapon does not evolve")
	check(Campaign.evolution(0, -1, 100, 100) == "", "negative required rank does not evolve")
	var achievements: Array = Campaign.achievements()
	check(achievements.size() == 6, "six achievements")
	var ids: Array[String] = []
	for entry in achievements:
		check(not ids.has(entry.id), "unique achievement ID")
		check(entry.reward > 0 and not entry.description.is_empty(), "complete achievement")
		ids.append(entry.id)
	check(ids == ["first_sector", "second_sector", "campaign_clear", "evolved", "dash_50", "veteran"], "persistence-compatible IDs")
	achievements[0].name = "mutated"
	check(Campaign.achievements()[0].name != "mutated", "achievement deep copy isolation")
	print("Campaign content: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
