class_name DriftProgression
extends RefCounted
## Versioned, local pilot progression and an optional suspended run.
## ConfigFile preserves Vector2 values, unlike a JSON conversion of the snapshot.

const VERSION := 2
const OLDEST_VERSION := 1
const SAVE_PATH := "user://progression.cfg"
const BACKUP_PATH := "user://progression.cfg.bak"
const TEMP_PATH := "user://progression.cfg.tmp"
const LEGACY_PATH := "user://record.cfg"
const MAX_RANK := 5
const MAX_COUNTER := 2147483647
const MAX_FILE_BYTES := 4 * 1024 * 1024
const ACHIEVEMENT_IDS := ["first_sector", "second_sector", "campaign_clear", "evolved", "dash_50", "veteran"]

var credits: int = 0
var hull_rank: int = 0
var damage_rank: int = 0
var magnet_rank: int = 0
var total_kills: int = 0
var best: int = 0
var weapon: int = 0
var ship: int = 0
var sector_unlocked: int = 0
var campaign_wins: int = 0
var achievements: Array[String] = []
var run: Dictionary = {}
var last_error: String = ""

var _write_blocked := false


func load_data() -> void:
	_reset()
	var config := ConfigFile.new()
	var result := _load_config(config, SAVE_PATH)
	var used_backup := false
	if result == OK and not _supported(config):
		_block_unknown_version()
		_migrate_record()
		return
	if result != OK:
		var primary_missing := result == ERR_FILE_NOT_FOUND
		config = ConfigFile.new()
		result = _load_config(config, BACKUP_PATH)
		if result == OK and not _supported(config):
			_block_unknown_version()
			_migrate_record()
			return
		used_backup = result == OK
		if not primary_missing and not used_backup:
			last_error = "The pilot save could not be read. Starting with a new pilot."
	if result == OK:
		credits = _safe_int(config.get_value("pilot", "credits", 0), 0, MAX_COUNTER)
		hull_rank = _safe_int(config.get_value("pilot", "hull_rank", 0), 0, MAX_RANK)
		damage_rank = _safe_int(config.get_value("pilot", "damage_rank", 0), 0, MAX_RANK)
		magnet_rank = _safe_int(config.get_value("pilot", "magnet_rank", 0), 0, MAX_RANK)
		total_kills = _safe_int(config.get_value("pilot", "total_kills", 0), 0, MAX_COUNTER)
		best = _safe_int(config.get_value("pilot", "best", 0), 0, MAX_COUNTER)
		weapon = _safe_int(config.get_value("pilot", "weapon", 0), 0, 2)
		if not weapon_unlocked(weapon):
			weapon = 0
		sector_unlocked = _safe_int(config.get_value("pilot", "sector_unlocked", 0), 0, 2)
		ship = _safe_int(config.get_value("pilot", "ship", 0), 0, sector_unlocked)
		campaign_wins = _safe_int(config.get_value("pilot", "campaign_wins", 0), 0, MAX_COUNTER)
		achievements = _safe_achievements(config.get_value("pilot", "achievements", []))
		var snapshot: Variant = config.get_value("run", "snapshot", {})
		if valid_game_run(snapshot):
			run = snapshot.duplicate(true)
		else:
			last_error = "The suspended run was invalid. Your pilot upgrades were kept."
		if used_backup:
			last_error = "Recovered your pilot from the backup save."
	_migrate_record()


func save_data() -> bool:
	if _write_blocked:
		_block_unknown_version()
		return false
	# Check again even when the caller has not loaded first. Never overwrite a
	# newer format left by another build, or replace it with an older backup.
	var current := ConfigFile.new()
	var current_result := _load_config(current, SAVE_PATH)
	if current_result == OK and not _supported(current):
		_block_unknown_version()
		return false
	if current_result == ERR_FILE_NOT_FOUND:
		var backup := ConfigFile.new()
		if _load_config(backup, BACKUP_PATH) == OK and not _supported(backup):
			_block_unknown_version()
			return false
	if not valid_game_run(run):
		last_error = "The suspended run could not be saved because it is invalid."
		return false

	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value("pilot", "credits", clampi(credits, 0, MAX_COUNTER))
	config.set_value("pilot", "hull_rank", clampi(hull_rank, 0, MAX_RANK))
	config.set_value("pilot", "damage_rank", clampi(damage_rank, 0, MAX_RANK))
	config.set_value("pilot", "magnet_rank", clampi(magnet_rank, 0, MAX_RANK))
	config.set_value("pilot", "total_kills", clampi(total_kills, 0, MAX_COUNTER))
	config.set_value("pilot", "best", clampi(best, 0, MAX_COUNTER))
	config.set_value("pilot", "weapon", weapon if weapon_unlocked(weapon) else 0)
	config.set_value("pilot", "ship", clampi(ship, 0, clampi(sector_unlocked, 0, 2)))
	config.set_value("pilot", "sector_unlocked", clampi(sector_unlocked, 0, 2))
	config.set_value("pilot", "campaign_wins", clampi(campaign_wins, 0, MAX_COUNTER))
	config.set_value("pilot", "achievements", _safe_achievements(achievements))
	config.set_value("run", "snapshot", run)
	var result := config.save(TEMP_PATH)
	if result != OK:
		last_error = "Could not write the pilot save (%s)." % error_string(result)
		return false
	# Verify the temporary file before replacing the last usable save.
	var verified := ConfigFile.new()
	if _load_config(verified, TEMP_PATH) != OK or not _supported(verified):
		last_error = "Could not verify the pilot save. Your previous save was kept."
		return false
	var rotated := false
	if current_result == OK:
		result = DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)
		if result != OK:
			last_error = "Could not back up the pilot save (%s)." % error_string(result)
			return false
		rotated = true
	result = DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH)
	if result != OK:
		if rotated:
			# Keep the backup even if restoring the primary also fails.
			DirAccess.copy_absolute(BACKUP_PATH, SAVE_PATH)
		last_error = "Could not finish the pilot save (%s)." % error_string(result)
		return false
	last_error = ""
	return true


func upgrade_cost(key: String) -> int:
	var rank := _rank(key)
	if rank < 0 or rank >= MAX_RANK:
		return 0
	return 15 + 20 * rank


func buy_upgrade(key: String) -> bool:
	var rank := _rank(key)
	var cost := upgrade_cost(key)
	if rank < 0:
		last_error = "Unknown pilot upgrade."
		return false
	if rank >= MAX_RANK:
		last_error = "This upgrade is already at maximum rank."
		return false
	if credits < cost:
		last_error = "Not enough credits for this upgrade."
		return false
	var previous_credits := credits
	credits -= cost
	_set_rank(key, rank + 1)
	if not save_data():
		credits = previous_credits
		_set_rank(key, rank)
		return false
	return true


func weapon_unlocked(id: int) -> bool:
	match id:
		0: return true
		1: return total_kills >= 100
		2: return total_kills >= 300
	return false


func ship_unlocked(id: int) -> bool:
	return id >= 0 and id <= 2 and sector_unlocked >= id


func award_achievement(id: String, reward: int) -> bool:
	if id not in ACHIEVEMENT_IDS or id in achievements or reward < 0:
		return false
	achievements.append(id)
	# Rewards and the corresponding run checkpoint must be written together by
	# the caller. A standalone save here could pay out before a sector is claimed.
	credits = clampi(credits, 0, MAX_COUNTER)
	credits += mini(reward, MAX_COUNTER - credits)
	return true


func _reset() -> void:
	credits = 0
	hull_rank = 0
	damage_rank = 0
	magnet_rank = 0
	total_kills = 0
	best = 0
	weapon = 0
	ship = 0
	sector_unlocked = 0
	campaign_wins = 0
	achievements = []
	run = {}
	last_error = ""
	_write_blocked = false


func _migrate_record() -> void:
	var legacy := ConfigFile.new()
	if _load_config(legacy, LEGACY_PATH) == OK:
		best = maxi(best, _safe_int(legacy.get_value("record", "best", 0), 0, MAX_COUNTER))


func _load_config(config: ConfigFile, path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var length := file.get_length()
	file.close()
	if length > MAX_FILE_BYTES:
		return ERR_FILE_CORRUPT
	return config.load(path)


func _supported(config: ConfigFile) -> bool:
	var version: Variant = config.get_value("meta", "version", -1)
	return typeof(version) == TYPE_INT and version >= OLDEST_VERSION and version <= VERSION


func _block_unknown_version() -> void:
	_write_blocked = true
	last_error = "This pilot save uses an unsupported version. It has not been changed."


func _safe_int(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		return clampi(value, minimum, maximum)
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return int(clampf(value, float(minimum), float(maximum)))
	return minimum


func _safe_achievements(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for id in value:
		if typeof(id) == TYPE_STRING and id in ACHIEVEMENT_IDS and id not in result:
			result.append(id)
	return result


func _rank(key: String) -> int:
	match key:
		"hull", "hull_rank": return hull_rank
		"damage", "damage_rank": return damage_rank
		"magnet", "magnet_rank": return magnet_rank
	return -1


func _set_rank(key: String, rank: int) -> void:
	match key:
		"hull", "hull_rank": hull_rank = rank
		"damage", "damage_rank": damage_rank = rank
		"magnet", "magnet_rank": magnet_rank = rank


func _valid_run(snapshot: Variant) -> bool:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return false
	if snapshot.is_empty():
		return true
	if not snapshot.has_all(["player", "elapsed", "health"]):
		return false
	if typeof(snapshot.player) != TYPE_VECTOR2 or not snapshot.player.is_finite():
		return false
	if typeof(snapshot.elapsed) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	if not is_finite(float(snapshot.elapsed)) or snapshot.elapsed < 0 or snapshot.elapsed > 864000:
		return false
	if typeof(snapshot.health) != TYPE_INT or snapshot.health <= 0 or snapshot.health > 1000:
		return false
	# Main validates gameplay-specific fields and entity shapes. Bound the whole
	# tree here and exclude Objects/Resources from all nested snapshot data.
	return _plain_value(snapshot, 0, [0])


func valid_game_run(snapshot: Variant) -> bool:
	if not _valid_run(snapshot):
		return false
	if snapshot.is_empty():
		return true
	if snapshot.get("state", "") not in ["paused", "upgrade"]:
		return false
	if not _vector_field(snapshot, "player") or not _vector_field(snapshot, "facing"):
		return false
	for key in ["health", "max_health", "level", "next_level", "wave"]:
		if not _int_field(snapshot, key, 1, MAX_COUNTER):
			return false
	if snapshot.max_health > 1000 or snapshot.health > snapshot.max_health:
		return false
	for key in ["score", "kills", "energy", "overdrive", "phase_engine", "recovery", "earned_credits"]:
		if not _int_field(snapshot, key, 0, MAX_COUNTER):
			return false
	if not _int_field(snapshot, "run_weapon", 0, 2):
		return false
	for key in ["dash_left", "dash_cooldown", "invulnerable", "spawn_timer", "damage_bonus", "magnet_bonus", "pulse_timer"]:
		if not _number_field(snapshot, key, 0, 864000):
			return false
	# The fire clock may go negative while there are no available targets.
	if not _number_field(snapshot, "fire_timer", -864000, 864000):
		return false
	for key in ["boss_spawned", "boss_defeated", "endless"]:
		if typeof(snapshot.get(key)) != TYPE_BOOL:
			return false
	for key in ["enemies", "bolts", "gems"]:
		if typeof(snapshot.get(key)) != TYPE_ARRAY:
			return false
		for entity in snapshot[key]:
			if typeof(entity) != TYPE_DICTIONARY or not _vector_field(entity, "p"):
				return false
	for enemy in snapshot.enemies:
		if not _int_field(enemy, "kind", 0, 3) or not _vector_field(enemy, "dir"):
			return false
		if not _number_field(enemy, "hp", 0.000001, MAX_COUNTER) or not _number_field(enemy, "max_hp", 0.000001, MAX_COUNTER):
			return false
		for key in ["age", "phase", "flash"]:
			if not _number_field(enemy, key, 0, 864000):
				return false
		if not _number_field(enemy, "warning", -1, 864000):
			return false
		if enemy.has("attack_phase"):
			if enemy.attack_phase not in ["seek", "windup", "burst"]:
				return false
			if not _number_field(enemy, "attack_timer", -1, 864000) or not _vector_field(enemy, "locked_dir"):
				return false
		if enemy.kind == 3:
			if not _number_field(enemy, "attack_timer", -1, 864000) or not _number_field(enemy, "dash_hit", 0, 864000):
				return false
	for bolt in snapshot.bolts:
		if not _vector_field(bolt, "v") or not _number_field(bolt, "life", 0, 864000):
			return false
	for gem in snapshot.gems:
		if not _number_field(gem, "phase", 0, 864000) or not _int_field(gem, "value", 1, MAX_COUNTER):
			return false
	# Pre-campaign snapshots stay valid; a present campaign is a complete,
	# independently checked checkpoint, including pending intermissions.
	if snapshot.has("campaign"):
		if not _valid_campaign(snapshot.campaign):
			return false
		if snapshot.campaign.intermission and snapshot.state != "paused":
			return false
	return true


func _valid_campaign(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for key in ["mode", "intermission"]:
		if typeof(data.get(key)) != TYPE_BOOL:
			return false
	for key in ["sector", "ship"]:
		if not _int_field(data, key, 0, 2):
			return false
	if not _int_field(data, "objective", 0, 10000):
		return false
	for key in ["sector_time", "objective_clock", "total_time"]:
		if not _number_field(data, key, 0, 864000):
			return false
	if typeof(data.get("claimed")) != TYPE_ARRAY or data.claimed.size() > 3:
		return false
	var seen: Array[int] = []
	for sector_id in data.claimed:
		if typeof(sector_id) != TYPE_INT or sector_id < 0 or sector_id > 2 or sector_id in seen:
			return false
		seen.append(sector_id)
	if typeof(data.get("relics")) != TYPE_ARRAY or data.relics.size() > 3:
		return false
	for relic in data.relics:
		if typeof(relic) != TYPE_INT or relic < 0 or relic > 2:
			return false
	if typeof(data.get("hazards")) != TYPE_ARRAY:
		return false
	for hazard in data.hazards:
		if typeof(hazard) != TYPE_DICTIONARY or not _vector_field(hazard, "p"):
			return false
		for key in ["r", "life"]:
			if not _number_field(hazard, key, 0, 864000):
				return false
		if not _number_field(hazard, "warning", -1, 864000):
			return false
	return true


func _int_field(data: Dictionary, key: String, minimum: int, maximum: int) -> bool:
	var value: Variant = data.get(key)
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


func _number_field(data: Dictionary, key: String, minimum: float, maximum: float) -> bool:
	var value: Variant = data.get(key)
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum


func _vector_field(data: Dictionary, key: String) -> bool:
	var value: Variant = data.get(key)
	return typeof(value) == TYPE_VECTOR2 and value.is_finite() and absf(value.x) <= 1000000 and absf(value.y) <= 1000000


func _plain_value(value: Variant, depth: int, count: Array) -> bool:
	count[0] += 1
	if depth > 8 or count[0] > 50000:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= 4096
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			return value.is_finite()
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size() > 4096:
				return false
			for item in value:
				if not _plain_value(item, depth + 1, count):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 128:
				return false
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 128:
					return false
				if not _plain_value(value[key], depth + 1, count):
					return false
			return true
	return false
