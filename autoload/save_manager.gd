extends Node

const SAVE_PATH := "user://save_data.json"

var step_bank: int = 0
var last_sync_date: String = ""
var swift_request: String = ""
var synced_steps_by_day: Dictionary = {}  # { "YYYY-MM-DD": steps_already_credited }
var inventory: Array = []
var shirt_color: String = "blue"
var music_volume: float = 0.8
var equipped_weapon: Dictionary = {}
var equipped_equipment: Dictionary = {}
var equipped_defensive: Dictionary = {}

func _ready() -> void:
	_load()

func add_steps(amount: int) -> void:
	step_bank += amount
	last_sync_date = Time.get_datetime_string_from_system()
	_save()

# Called by sync_steps.gd after HealthKit reply. steps_by_day is { "YYYY-MM-DD": total_steps }.
# Returns how many new steps were actually credited (0 if nothing new).
func process_synced_steps(steps_by_day: Dictionary) -> int:
	var total_new := 0
	for day in steps_by_day:
		var hk_total := int(steps_by_day[day])
		var already := int(synced_steps_by_day.get(day, 0))
		var delta := max(0, hk_total - already)
		if delta > 0:
			synced_steps_by_day[day] = hk_total
			total_new += delta
	if total_new > 0:
		step_bank += total_new
		last_sync_date = Time.get_datetime_string_from_system()
		_save()
	return total_new

func spend_steps(amount: int) -> bool:
	if step_bank < amount:
		return false
	step_bank -= amount
	_save()
	return true

func add_to_inventory(item: Dictionary) -> void:
	inventory.append(item)
	_save()

func remove_items_by_indices(indices: Array) -> void:
	indices = indices.duplicate()
	indices.sort()
	indices.reverse()
	for idx in indices:
		inventory.remove_at(idx)
	_save()

func clear_inventory() -> void:
	inventory.clear()
	_save()

func get_slot(key: String) -> Dictionary:
	match key:
		"equipped_weapon":    return equipped_weapon
		"equipped_equipment": return equipped_equipment
		"equipped_defensive": return equipped_defensive
	return {}

func set_slot(key: String, value: Dictionary) -> void:
	match key:
		"equipped_weapon":    equipped_weapon = value
		"equipped_equipment": equipped_equipment = value
		"equipped_defensive": equipped_defensive = value
	_save()

func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"step_bank": step_bank,
		"last_sync_date": last_sync_date,
		"synced_steps_by_day": synced_steps_by_day,
		"inventory": inventory,
		"shirt_color": shirt_color,
		"music_volume": music_volume,
		"equipped_weapon": equipped_weapon,
		"equipped_equipment": equipped_equipment,
		"equipped_defensive": equipped_defensive,
	}))
	file.close()

func _save() -> void:
	save()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		return
	step_bank            = parsed.get("step_bank", 0)
	last_sync_date       = parsed.get("last_sync_date", "")
	synced_steps_by_day  = parsed.get("synced_steps_by_day", {})
	inventory            = parsed.get("inventory", [])
	shirt_color    = parsed.get("shirt_color", "blue")
	music_volume       = parsed.get("music_volume", 0.8)
	equipped_weapon    = parsed.get("equipped_weapon", {})
	equipped_equipment = parsed.get("equipped_equipment", {})
	equipped_defensive = parsed.get("equipped_defensive", {})
