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
# Optional SECOND weapon carried into a run. Costs equipment points like any other slot, and is
# the only thing that can be fused with the primary at the shop (see ItemRegistry.COMBINATIONS).
# A run played without fusing gives it back intact — see world.gd's _resolve_hedge_loss.
var equipped_weapon_secondary: Dictionary = {}
# Secondary weapons are brought in as a POOL, not a single pick: the player loads
# SECONDARY_POOL_SIZE fusable weapons before the run and the shop's fusion draws one of them at
# random. The pool only counts as "brought" when it is completely full — a partial pool is
# ignored, so there's no way to stack the odds by loading just one.
const SECONDARY_POOL_SIZE := 5
var secondary_pool: Array = []
# Elemental boosts. `boost_inventory` is everything owned (won from elemental crates);
# `boost_catalog` is the subset loaded for the next run — the shop draws at random from it rather
# than letting the player pick, so which boost you get is a gamble you stack the odds on.
# A boost spent in a run is consumed there and then, and follows the normal run-loss rule.
var boost_inventory: Array = []
var boost_catalog: Array = []
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

const EQUIP_SLOTS := ["equipped_weapon", "equipped_weapon_secondary", "equipped_equipment", "equipped_defensive", "equipped_artifact"]

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
# `keep_slots` names slots that survive regardless — used for a secondary weapon that was carried
# but never fused. Bringing one is meant to be a free option: you only lose it by spending it.
func resolve_run_loss(keep_slots: Array = []) -> void:
	for key in EQUIP_SLOTS:
		var item: Dictionary = get_slot(key)
		if item.is_empty():
			continue
		if key in keep_slots:
			continue # carried but never spent — comes home intact
		if hedged_slots.has(key):
			hedged_slots.erase(key) # token consumed protecting this item
		else:
			_remove_one_owned(item.get("name", ""), key == "equipped_artifact")
			set_slot(key, {})
	_save()

# Both weapons that went into a fusion are destroyed by it — one owned copy of each leaves the
# inventory immediately, so the fused weapon genuinely replaces them rather than duplicating.
func consume_for_fusion(component_names: Array) -> void:
	for n in component_names:
		if str(n) != "":
			_remove_one_owned(str(n), false)
	_save()

# Loads/unloads a boost for the next run. The catalog can only hold boosts actually owned.
func set_boost_in_catalog(boost_name: String, loaded: bool) -> void:
	if loaded:
		# Duplicates are allowed and meaningful: owning two Fire Boosts and loading both doubles
		# the chance a shop draw comes up fire. _owns_boost caps it at how many are actually owned.
		if _owns_boost(boost_name):
			boost_catalog.append(boost_name)
	else:
		boost_catalog.erase(boost_name)
	_save()

func _owns_boost(boost_name: String) -> bool:
	var loaded_count := 0
	for n in boost_catalog:
		if str(n) == boost_name:
			loaded_count += 1
	var owned := 0
	for b in boost_inventory:
		if str(b.get("name", "")) == boost_name:
			owned += 1
	return owned > loaded_count

func add_boost(boost: Dictionary) -> void:
	boost_inventory.append(boost.duplicate(true))
	_save()

# A boost applied to a weapon mid-run is spent: it leaves the inventory and the catalog.
func consume_boost(boost_name: String) -> void:
	for i in range(boost_inventory.size()):
		if str(boost_inventory[i].get("name", "")) == boost_name:
			boost_inventory.remove_at(i)
			break
	boost_catalog.erase(boost_name)
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
		"equipped_weapon_secondary": return equipped_weapon_secondary
		"equipped_equipment": return equipped_equipment
		"equipped_defensive": return equipped_defensive
		"equipped_artifact":  return equipped_artifact
	return {}

func set_slot(key: String, value: Dictionary) -> void:
	# Swapping the primary between melee and ranged invalidates the whole secondary pool, since a
	# fusion only ever pairs like with like. Swapping within the same kind leaves it alone — those
	# entries are all still usable. Handled here rather than in the character screen so it holds
	# for every path that sets the primary. An empty primary purges nothing: with no weapon
	# equipped there is nothing for the pool to be incompatible with.
	if key == "equipped_weapon" and not secondary_pool.is_empty():
		var was: String = ItemRegistry.weapon_kind_label(equipped_weapon)
		var now: String = ItemRegistry.weapon_kind_label(value)
		if was != "" and now != "" and was != now:
			secondary_pool.clear()
	match key:
		"equipped_weapon":    equipped_weapon = value
		"equipped_weapon_secondary": equipped_weapon_secondary = value
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
		"equipped_weapon_secondary": equipped_weapon_secondary,
		"secondary_pool": secondary_pool,
		"boost_inventory": boost_inventory,
		"boost_catalog": boost_catalog,
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
	equipped_weapon_secondary = parsed.get("equipped_weapon_secondary", {})
	secondary_pool = parsed.get("secondary_pool", [])
	boost_inventory    = parsed.get("boost_inventory", [])
	boost_catalog      = parsed.get("boost_catalog", [])
	equipped_equipment = parsed.get("equipped_equipment", {})
	equipped_defensive = parsed.get("equipped_defensive", {})
	artifact_inventory = parsed.get("artifact_inventory", [])
	equipped_artifact  = parsed.get("equipped_artifact", {})
	hedge_tokens       = int(parsed.get("hedge_tokens", 0))
	hedged_slots       = parsed.get("hedged_slots", {})
	run_history        = parsed.get("run_history", [])
	_purge_retired_items()

# Drops anything from a save that no longer exists in the registry (e.g. the grapple weapons,
# removed after some players had already earned them). Without this a retired weapon stays
# equipped or sits in the secondary pool forever, and any lookup by name comes back empty —
# which reads in-game as a weapon that simply does nothing.
func _purge_retired_items() -> void:
	var known := {}
	for it in ItemRegistry.ITEMS:
		known[str(it.get("name", ""))] = true
	for it in ItemRegistry.COMBINED_WEAPONS:
		known[str(it.get("name", ""))] = true
	var dropped := 0
	var keep: Array = []
	for it in inventory:
		if known.has(str(it.get("name", ""))):
			keep.append(it)
		else:
			dropped += 1
	inventory = keep
	keep = []
	for it in secondary_pool:
		if known.has(str(it.get("name", ""))):
			keep.append(it)
		else:
			dropped += 1
	secondary_pool = keep
	for slot in ["equipped_weapon", "equipped_weapon_secondary"]:
		var cur: Dictionary = get_slot(slot)
		if not cur.is_empty() and not known.has(str(cur.get("name", ""))):
			match slot:
				"equipped_weapon":           equipped_weapon = {}
				"equipped_weapon_secondary": equipped_weapon_secondary = {}
			dropped += 1
	if dropped > 0:
		print("SaveManager: dropped %d retired item(s) from the save" % dropped)
		_save()


# ── Secondary weapon pool ────────────────────────────────────────────────────────────────────
func secondary_pool_full() -> bool:
	return secondary_pool.size() >= SECONDARY_POOL_SIZE

func set_secondary_pool(pool: Array) -> void:
	secondary_pool = pool.duplicate(true)
	save()

# One entry drawn at random — a flat 1-in-N, which is the whole point of the pool.
func draw_from_secondary_pool() -> Dictionary:
	if not secondary_pool_full():
		return {}
	return secondary_pool[randi() % secondary_pool.size()]

func remove_from_secondary_pool(item_name: String) -> void:
	for i in range(secondary_pool.size()):
		if str(secondary_pool[i].get("name", "")) == item_name:
			secondary_pool.remove_at(i)
			save()
			return
