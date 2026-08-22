extends Node

const SAVE_PATH := "user://save_data.json"

var step_bank: int = 0
var last_sync_date: String = ""
var swift_request: String = ""
# Polled by the iOS host (ContentView.swift) every 0.5s to lock the device orientation:
# "portrait" for menus, "landscape" for the game/sandbox. Runtime-only (never persisted) —
# set by SceneManager during game↔menu transitions. See SceneManager._change_scene_covered.
var target_orientation: String = "portrait"
var synced_steps_by_day: Dictionary = {}  # { "YYYY-MM-DD": steps_already_credited }
var inventory: Array = []
var shirt_color: String = "blue"
var music_volume: float = 0.8
var sfx_volume: float = 0.7
var equipped_weapon: Dictionary = {}
var equipped_equipment: Dictionary = {}
var equipped_defensive: Dictionary = {}
# Artifacts are passive items with their own slot + crate, kept separate from `inventory` so they
# never enter the trade-up pool (artifacts can't be traded up).
var artifact_inventory: Array = []
var equipped_artifact: Dictionary = {}
# Hedge tokens: earned by beating the final boss. A run that ISN'T won destroys the equipped loadout
# (removed from inventory + unequipped). Applying a token to an equipped slot protects that item —
# on a losing run the item survives and the token is spent. hedge_tokens is the unspent pool;
# hedged_slots holds the equip-slot keys currently protected. See resolve_run_loss / grant_hedge_token.
var hedge_tokens: int = 0
var hedged_slots: Dictionary = {}

# Persistent per-run history for the Statistics screen (Info → Statistics). One dict per finished run
# (recorded on death — see world.gd's _record_run): floor died at, weapon/loadout used, damage dealt/
# taken, gold earned/spent, kills, accuracy, outcome. Capped so the save file can't grow unbounded.
var run_history: Array = []
const RUN_HISTORY_CAP := 500

func record_run(rec: Dictionary) -> void:
	run_history.append(rec)
	if run_history.size() > RUN_HISTORY_CAP:
		run_history = run_history.slice(run_history.size() - RUN_HISTORY_CAP)
	save()

func clear_run_history() -> void:
	run_history = []
	save()

const EQUIP_SLOTS := ["equipped_weapon", "equipped_equipment", "equipped_defensive", "equipped_artifact"]

func _ready() -> void:
	_load()

func is_slot_hedged(key: String) -> bool:
	return hedged_slots.has(key)

# Move a token from the pool onto an equipped slot (protecting whatever's in it).
func apply_hedge(key: String) -> void:
	if hedge_tokens <= 0 or hedged_slots.has(key) or get_slot(key).is_empty():
		return
	hedge_tokens -= 1
	hedged_slots[key] = true
	_save()

# Take a token back off a slot and return it to the pool (e.g. to move it to a different item).
func remove_hedge(key: String) -> void:
	if not hedged_slots.has(key):
		return
	hedged_slots.erase(key)
	hedge_tokens += 1
	_save()

func grant_hedge_token() -> void:
	hedge_tokens += 1
	_save()

# End-of-run loss (called when a run ends WITHOUT beating the final boss). Each equipped item is
# destroyed — removed from its inventory and unequipped — UNLESS its slot is hedged, in which case
# the item is kept and the token is spent (consumed, not returned to the pool).
func resolve_run_loss() -> void:
	for key in EQUIP_SLOTS:
		var item: Dictionary = get_slot(key)
		if item.is_empty():
			continue
		if hedged_slots.has(key):
			hedged_slots.erase(key) # token consumed protecting this item
		else:
			_remove_one_owned(item.get("name", ""), key == "equipped_artifact")
			set_slot(key, {})
	_save()

# Removes one owned copy (by name) of a lost item from the matching inventory.
func _remove_one_owned(item_name: String, is_artifact: bool) -> void:
	var inv: Array = artifact_inventory if is_artifact else inventory
	for i in range(inv.size()):
		if inv[i].get("name", "") == item_name:
			inv.remove_at(i)
			return

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
		var delta: int = max(0, hk_total - already)
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

func add_artifact(artifact: Dictionary) -> void:
	artifact_inventory.append(artifact)
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
		"equipped_artifact":  return equipped_artifact
	return {}

func set_slot(key: String, value: Dictionary) -> void:
	match key:
		"equipped_weapon":    equipped_weapon = value
		"equipped_equipment": equipped_equipment = value
		"equipped_defensive": equipped_defensive = value
		"equipped_artifact":  equipped_artifact = value
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
		"sfx_volume": sfx_volume,
		"equipped_weapon": equipped_weapon,
		"equipped_equipment": equipped_equipment,
		"equipped_defensive": equipped_defensive,
		"artifact_inventory": artifact_inventory,
		"equipped_artifact": equipped_artifact,
		"hedge_tokens": hedge_tokens,
		"hedged_slots": hedged_slots,
		"run_history": run_history,
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
	sfx_volume         = parsed.get("sfx_volume", 0.7)
	equipped_weapon    = parsed.get("equipped_weapon", {})
	equipped_equipment = parsed.get("equipped_equipment", {})
	equipped_defensive = parsed.get("equipped_defensive", {})
	artifact_inventory = parsed.get("artifact_inventory", [])
	equipped_artifact  = parsed.get("equipped_artifact", {})
	hedge_tokens       = int(parsed.get("hedge_tokens", 0))
	hedged_slots       = parsed.get("hedged_slots", {})
	run_history        = parsed.get("run_history", [])
