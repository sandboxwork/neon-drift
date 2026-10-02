class_name DriftCampaign
extends RefCounted
## Read-only campaign content. No scene, RNG, save file, or autoload dependency.
## Sector and ship IDs are zero-based. unlock_sector is the number of completed
## sectors required (0 means available immediately), not a sector ID.
## Colors remain HTML hex strings so callers choose how to render them.

const SECTORS := [
	{
		"id": 0,
		"name": "SIGNAL GRAVEYARD",
		"subtitle": "01 / THE LAST TRANSMISSION",
		"briefing": "A broken distress signal leads into the wreck field. Recover five beacon fragments and silence the Warden to open the route to the Foundry.",
		"debrief": "The fragments resolve into a convoy's final coordinates. The signal is coming from the heart of the Foundry.",
		"objective": "beacons",
		"objective_label": "RECOVER BEACONS",
		"objective_hint": "Fly through the glowing beacons. Move out of marked mine fields before they detonate.",
		"objective_target": 5,
		"objective_unit": "beacons",
		"duration": 180.0,
		"boss_time": 135.0,
		"color": "64ffda",
		"bg_color": "081720",
		"hazard": "crossfire",
		"hazard_label": "CROSSFIRE MINES",
		"hazard_interval": 12.0,
		"hazard_warning": 1.4,
		"hazard_duration": 1.4,
		"hazard_radius": 28.0,
		"boss_name": "THE WARDEN",
		"boss_pattern": "fan",
		"boss_hint": "Fan-shaped impact zones. Circle wide, then dash through the gaps.",
		"boss_hp": 180.0,
		"boss_speed": 42.0,
		"boss_fire_interval": 2.2,
		"reward": 35,
		"enemy_health_scale": 1.0,
		"enemy_speed_scale": 1.0,
		"spawn_scale": 1.0,
	},
	{
		"id": 1,
		"name": "ION FOUNDRY",
		"subtitle": "02 / THE MACHINES REMEMBER",
		"briefing": "The convoy's route is locked behind a dead relay. Hold inside its signal field to restore power while ion storms tear through the factory.",
		"debrief": "The relay wakes. Beyond the shattered assembly rings, one surviving ship is still transmitting from the Hollow Crown.",
		"objective": "relay",
		"objective_label": "CHARGE THE RELAY",
		"objective_hint": "Stay inside the relay field to charge it. Progress is kept when you leave to evade danger.",
		"objective_target": 36,
		"objective_unit": "seconds",
		"duration": 180.0,
		"boss_time": 135.0,
		"color": "ffb66e",
		"bg_color": "21131b",
		"hazard": "ion_storm",
		"hazard_label": "ION STORMS",
		"hazard_interval": 9.0,
		"hazard_warning": 1.5,
		"hazard_duration": 2.2,
		"hazard_radius": 70.0,
		"boss_name": "THE CRUCIBLE",
		"boss_pattern": "radial",
		"boss_hint": "Radial blast fields. Choose a gap before the marked zones erupt.",
		"boss_hp": 260.0,
		"boss_speed": 32.0,
		"boss_fire_interval": 2.6,
		"reward": 50,
		"enemy_health_scale": 1.18,
		"enemy_speed_scale": 1.07,
		"spawn_scale": 1.12,
	},
	{
		"id": 2,
		"name": "THE HOLLOW CROWN",
		"subtitle": "03 / BRING THEM HOME",
		"briefing": "The missing convoy is trapped in the Crown's gravity wake. Recover twelve salvage cores to power extraction, then destroy the intelligence holding the fleet.",
		"debrief": "The Crown falls silent. Rescue engines flare across the wreck field. For the first time, the transmission is a reply.",
		"objective": "salvage",
		"objective_label": "RECOVER SALVAGE",
		"objective_hint": "Collect salvage cores from the wreck field. Gravity wells pull you off course; dash to escape.",
		"objective_target": 12,
		"objective_unit": "cores",
		"duration": 180.0,
		"boss_time": 135.0,
		"color": "bd9aff",
		"bg_color": "160f29",
		"hazard": "gravity_well",
		"hazard_label": "GRAVITY WELLS",
		"hazard_interval": 10.0,
		"hazard_warning": 1.6,
		"hazard_duration": 4.0,
		"hazard_radius": 98.0,
		"boss_name": "THE CROWN",
		"boss_pattern": "spiral",
		"boss_hint": "Spiraling blast fields. Follow the opening and save your dash for a gravity trap.",
		"boss_hp": 340.0,
		"boss_speed": 48.0,
		"boss_fire_interval": 1.8,
		"reward": 75,
		"enemy_health_scale": 1.38,
		"enemy_speed_scale": 1.13,
		"spawn_scale": 1.25,
	},
]

const SHIPS := [
	{
		"id": 0,
		"name": "VECTOR",
		"role": "BALANCED EXPLORER",
		"description": "A dependable rescue craft. Balanced hull, handling, and firepower.",
		"color": "64ffda",
		"hull_bonus": 0,
		"speed_mult": 1.0,
		"damage_mult": 1.0,
		"dash_mult": 1.0,
		"unlock_sector": 0,
		"unlock_label": "AVAILABLE",
	},
	{
		"id": 1,
		"name": "KESTREL",
		"role": "FAST INTERCEPTOR",
		"description": "One less hull point, faster engines, and a shorter dash cooldown. Built for pilots who never stop moving.",
		"color": "8cbcff",
		"hull_bonus": -1,
		"speed_mult": 1.22,
		"damage_mult": 1.0,
		"dash_mult": 0.82,
		"unlock_sector": 1,
		"unlock_label": "CLEAR SIGNAL GRAVEYARD",
	},
	{
		"id": 2,
		"name": "BASTION",
		"role": "ARMORED SALVAGER",
		"description": "Two extra hull points and heavier shots, traded for slower engines and a longer dash cooldown.",
		"color": "ffcb80",
		"hull_bonus": 2,
		"speed_mult": 0.84,
		"damage_mult": 1.15,
		"dash_mult": 1.15,
		"unlock_sector": 2,
		"unlock_label": "CLEAR ION FOUNDRY",
	},
]

## Required ranks are inclusive. Zero means the path is not required.
## IDs match the existing Pulse / Fan / Lance weapon loadouts.
const EVOLUTION_REQUIREMENTS := {
	0: {
		"name": "NOVA ARRAY",
		"overdrive": 3,
		"phase_engine": 0,
		"recovery": 2,
		"description": "Pulse evolves: a wide nova pulses around your ship every 2.5 seconds.",
		"color": "64ffda",
	},
	1: {
		"name": "STARWEAVE",
		"overdrive": 3,
		"phase_engine": 2,
		"recovery": 0,
		"description": "Fan evolves: eight radial stars join every volley.",
		"color": "8cbcff",
	},
	2: {
		"name": "VOID LANCE",
		"overdrive": 3,
		"phase_engine": 0,
		"recovery": 2,
		"description": "Lance evolves: heavy plasma pierces successive enemies.",
		"color": "bd9aff",
	},
}

## sector_clear targets are zero-based sector IDs. Rewards are one-time cores.
const ACHIEVEMENTS := [
	{
		"id": "first_sector", "name": "FIRST SIGNAL",
		"description": "Complete Signal Graveyard.",
		"trigger": "sector_clear", "target": 0, "reward": 15,
	},
	{
		"id": "second_sector", "name": "FOUNDRY BREAKER",
		"description": "Complete Ion Foundry.",
		"trigger": "sector_clear", "target": 1, "reward": 25,
	},
	{
		"id": "campaign_clear", "name": "CROWNLESS",
		"description": "Clear all three sectors in one expedition.",
		"trigger": "sector_clear", "target": 2, "reward": 50,
	},
	{
		"id": "evolved", "name": "STAR ARCHITECT",
		"description": "Evolve any weapon during a run.",
		"trigger": "evolution", "target": 1, "reward": 20,
	},
	{
		"id": "dash_50", "name": "PHASE MASTER",
		"description": "Reach Phase Engine rank 5 during a run.",
		"trigger": "phase_rank", "target": 5, "reward": 30,
	},
	{
		"id": "veteran", "name": "DRIFT VETERAN",
		"description": "Defeat 1,000 enemies across all runs.",
		"trigger": "total_kills", "target": 1000, "reward": 35,
	},
]


static func sector(id: int) -> Dictionary:
	return SECTORS[clampi(id, 0, SECTORS.size() - 1)].duplicate(true)


static func ship(id: int) -> Dictionary:
	return SHIPS[clampi(id, 0, SHIPS.size() - 1)].duplicate(true)


static func evolution(weapon: int, overdrive: int, phase_engine: int, recovery: int) -> String:
	if not EVOLUTION_REQUIREMENTS.has(weapon):
		return ""
	var requirement: Dictionary = EVOLUTION_REQUIREMENTS[weapon]
	if overdrive >= requirement.overdrive and phase_engine >= requirement.phase_engine and recovery >= requirement.recovery:
		return requirement.name
	return ""


static func achievements() -> Array:
	return ACHIEVEMENTS.duplicate(true)
