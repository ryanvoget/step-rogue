extends Node

# damage/heal/block are null when not applicable to that item (sourced from Asset_List.xlsx).
# fire_rate (seconds between attacks) is only set for weapons tuned for actual gameplay so far;
# null means "not wired up yet, falls back to default weapon behavior". Used for both ranged
# fire rate and melee swing rate.
# barrel_offset (pixels) is set for multi-barrel weapons (e.g. dual-wielded pistols) to fire
# a bullet from each side of the aim point instead of one from dead center; null/0 = single shot.
# melee_range (pixels) marks a weapon as melee instead of ranged when set: on attack it swings
# in a cone in front of the player instead of firing a bullet_scene projectile.
# knockback (px/sec impulse) is only meaningful for melee weapons; null/0 = no knockback.
# melee_hits (int) is only meaningful for melee weapons; null/1 = single strike per swing,
# 2+ = that many staggered strikes per swing (e.g. dual daggers), each landing melee_hits
# apart in time. Not part of every row's dictionary — omitted rows fall back to 1 via .get().
# melee_arc_degrees (float) overrides the default 100° swipe cone width for melee weapons
# (e.g. Metallic Whip's narrower 66.67°); null = default width. Not part of every row.
# stun (seconds) is only meaningful for melee weapons; null/0 = no stun. On hit, stuns the
# enemy (freezes its AI) for that long with a white flash pulsing every 0.05s. Independent
# of knockback — a weapon can have one, the other, both, or neither. Not part of every row.
# melee_joystick (bool) is only meaningful for melee weapons; null/false = mobile_controls
# shows a press-button like Staff/Warhammer/Daggers. true = mobile_controls shows the
# continuous aim joystick like ranged guns instead (e.g. Metallic Whip), while the hit
# itself still uses melee cone/range logic. Not part of every row.
# placeable marks equipment that can be deployed as a stationary auto-turret via the HUD
# deploy button (see scenes/turret/turret.gd); false for everything else.
# bullet_speed (px/sec) overrides the default bullet speed for placeable turrets; null = default.
# throwable marks equipment that's thrown via the same green deploy button as placeables
# (see scenes/grenade/grenade.gd); false for everything else. Uses damage as its AOE damage.
# throw_distance (pixels) is how far in front of the player it lands; only set on throwables.
# explode_delay (seconds) is how long it sits after landing before exploding; only set on throwables.
# aoe_radius (pixels) is the radius of the damage circle on explosion; only set on throwables.
const ITEMS := [
	{ "name": "Staff",                             "rarity": "common",    "file": "Staff_Asset.png",                            "type": "weapon",    "damage": 2,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	{ "name": "Laser Blaster",                     "rarity": "common",    "file": "Laser_Blaster_Asset.png",                    "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": 0.25 , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Punching Robot Gloves",             "rarity": "common",    "file": "Punching_Robot_Gloves_Asset.png",            "type": "weapon",    "damage": 2,   "heal": null, "block": null, "fire_rate": 0.40, "barrel_offset": null, "melee_range": 96.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_hits": 2, "melee_joystick": true },
	{ "name": "Sticky Grenade",                    "rarity": "common",    "file": "Sticky_Grenade_Asset.png",                   "type": "equipment", "damage": 10,  "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Smoke Grenade",                     "rarity": "common",    "file": "Smoke_Grenade_Asset.png",                    "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Blast Grenade",                     "rarity": "common",    "file": "Blast_Grenade_Asset.png",                    "type": "equipment", "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "throw_distance": 250.0, "explode_delay": 0.25, "aoe_radius": 100.0 },
	{ "name": "Small Heal Vial",                   "rarity": "common",    "file": "Small_Heal_Vial_Asset.png",                  "type": "heal",      "damage": null, "heal": 10,  "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Speed Boost Battery",               "rarity": "common",    "file": "Speed_Boost_Battery_Asset.png",              "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Electric Baton",                    "rarity": "common",    "file": "Electric_Baton_Asset.png",                   "type": "weapon",    "damage": 4,   "heal": null, "block": null, "fire_rate": 0.67, "barrel_offset": null, "melee_range": 128.0, "knockback": null, "placeable": false, "bullet_speed": null, "stun": 0.1, "melee_joystick": true },
	{ "name": "Detonator Mine",                    "rarity": "common",    "file": "Detonator_Mine_Asset.png",                   "type": "equipment", "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Metallic Whip",                     "rarity": "common",    "file": "Metallic_Whip_Asset.png",                    "type": "weapon",    "damage": 3,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 256.0, "knockback": null, "placeable": false, "bullet_speed": null, "melee_arc_degrees": 33.3333, "stun": 0.2, "melee_joystick": true },
	{ "name": "Daggers",                           "rarity": "common",    "file": "Daggers_Asset.png",                          "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": 0.25, "barrel_offset": null, "melee_range": 96.0, "knockback": null, "placeable": false, "bullet_speed": null, "melee_hits": 2, "melee_joystick": true },
	{ "name": "Passive Health Regen Vial",         "rarity": "common",    "file": "Passive_Health_Regen_Vial_Asset.png",        "type": "defensive", "damage": null, "heal": 1,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Force Push Bracelet",               "rarity": "common",    "file": "Force_Push_Bracelet_Asset.png",              "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Light Shield Barrier",              "rarity": "common",    "file": "Light_Shield_Barrier_Asset.png",             "type": "defensive", "damage": null, "heal": null, "block": 10 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Warhammer",                         "rarity": "common",    "file": "Warhammer_Asset.png",                        "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": 1.0 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	{ "name": "Molitov Grenade",                   "rarity": "common",    "file": "Molitov_Grenade_Asset.png",                  "type": "equipment", "damage": 1,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Magnetic Grenade",                  "rarity": "common",    "file": "Magnetic_Grenade_Asset.png",                 "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Deployable Barrier Wall",           "rarity": "common",    "file": "Deployable_Barrier_Wall_Asset.png",          "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Grapple Hook",                      "rarity": "common",    "file": "Grapple_Hook_Asset.png",                     "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Beam Sword",                        "rarity": "uncommon",  "file": "Beam_Sword_Asset.png",                       "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Mesh Grenade",                      "rarity": "uncommon",  "file": "Mesh_Grenade_Asset.png",                     "type": "equipment", "damage": 2,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Flash Grenade",                     "rarity": "uncommon",  "file": "Flash_Grenade_Asset.png",                    "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Medium Shield Barrier",             "rarity": "uncommon",  "file": "Medium_Shield_Barrier_Asset.png",            "type": "defensive", "damage": null, "heal": null, "block": 25 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Medium Passive Health Regen Vial",  "rarity": "uncommon",  "file": "Medium_Passive_Health_Regen_Vial_Asset.png", "type": "defensive", "damage": null, "heal": 1,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Double Pistol Blasters",            "rarity": "uncommon",  "file": "Double_Pistol_Blasters_Asset.png",           "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": 0.25 , "barrel_offset": 6.0, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Ice Grenade",                       "rarity": "uncommon",  "file": "Ice_Grenade_Asset.png",                      "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Distraction Grenade",               "rarity": "uncommon",  "file": "Distraction_Grenade_Asset.png",              "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Turret",                            "rarity": "uncommon",  "file": "Turret_Asset.png",                           "type": "equipment", "damage": 2,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": true, "bullet_speed": 1040.0 },
	{ "name": "Wave Ray Gun",                      "rarity": "uncommon",  "file": "Wave_Ray_Gun_Asset.png",                     "type": "weapon",    "damage": 4,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Freeze Gun",                        "rarity": "uncommon",  "file": "Freeze_Gun_Asset.png",                       "type": "weapon",    "damage": 4,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Flamethrower",                      "rarity": "uncommon",  "file": "Flamethrower_Asset.png",                     "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Heal Dispenser Farm",                "rarity": "uncommon",  "file": "Heal_Dispenser_Farm_Asset.png",              "type": "defensive", "damage": null, "heal": 10,  "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Hand Cannon Gun",                   "rarity": "uncommon",  "file": "Hand_Cannon_Gun_Asset.png",                  "type": "weapon",    "damage": 10,  "heal": null, "block": null, "fire_rate": 1.5 , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Bigger Speed Boost Battery",        "rarity": "uncommon",  "file": "Bigger_Speed_Boost_Battery_Asset.png",       "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Heavy Shield Barrier",              "rarity": "rare",      "file": "Heavy_Shield_Barrier_Asset.png",             "type": "defensive", "damage": null, "heal": null, "block": 50 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Large Warhammer",                   "rarity": "rare",      "file": "Large_Warhammer_Asset.png",                  "type": "weapon",    "damage": 8,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Throwable Beam Sword",              "rarity": "rare",      "file": "Throwable_Beam_Sword_Asset.png",             "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Hoverboard",                        "rarity": "rare",      "file": "Hoverboard_Asset.png",                       "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Assault Rifle Blaster",             "rarity": "rare",      "file": "Assault_Rifle_Blaster_Asset.png",            "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Sniper Rifle Blaster",              "rarity": "rare",      "file": "Sniper_Rifle_Blaster_Asset.png",             "type": "weapon",    "damage": 20,  "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Large Passive Health Regen Vial",   "rarity": "rare",      "file": "Large_Passive_Health_Regen_Vial_Asset.png",  "type": "defensive", "damage": null, "heal": 2,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Temporary Invincible Battery",      "rarity": "rare",      "file": "Temporary_Invincible_Battery_Asset.png",     "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Teleportation Bracelet",            "rarity": "rare",      "file": "Teleportation_Bracelet_Asset.png",           "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Advanced Turret",                   "rarity": "rare",      "file": "Advanced_Turret_Asset.png",                  "type": "equipment", "damage": 4,   "heal": null, "block": null, "fire_rate": 0.35, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": true, "bullet_speed": 1040.0 },
	{ "name": "Sidekick Robot",                    "rarity": "epic",      "file": "Sidekick_Robot_Asset.png",                   "type": "equipment", "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Double Beam Swords",                "rarity": "epic",      "file": "Double_Beam_Swords_Asset.png",               "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Void Grenade Launcher",             "rarity": "epic",      "file": "Void_Grenade_Launcher_Asset.png",            "type": "weapon",    "damage": 4,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Reflect Shield",                    "rarity": "epic",      "file": "Reflect_Shield_Asset.png",                   "type": "defensive", "damage": null, "heal": null, "block": 50 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Stim Shot",                         "rarity": "epic",      "file": "Stim_Shot_Asset.png",                        "type": "defensive", "damage": null, "heal": 100, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Dennis",                            "rarity": "legendary", "file": "Dennis_Asset.png",                           "type": "equipment", "damage": 100, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
]

# Applies an item's look and (if tuned) gameplay stats to the player. Safe to call with
# items that aren't weapons or don't have fire_rate set yet — only the texture changes then.
func equip_on_player(player: Node, item: Dictionary) -> void:
	if item.is_empty():
		return
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	player.set_weapon_texture(tex)
	if item["type"] != "weapon" or item.get("fire_rate") == null or item.get("damage") == null:
		return
	if item.get("melee_range") != null:
		var knockback: float = item["knockback"] if item.get("knockback") != null else 0.0
		var hits: int = item.get("melee_hits") if item.get("melee_hits") != null else 1
		var arc: float = item["melee_arc_degrees"] if item.get("melee_arc_degrees") != null else -1.0
		var stun: float = item["stun"] if item.get("stun") != null else 0.0
		var use_joystick: bool = item.get("melee_joystick") if item.get("melee_joystick") != null else false
		player.set_melee_stats(item["damage"], item["fire_rate"], item["melee_range"], knockback, hits, arc, stun, use_joystick)
	else:
		var offset: float = item["barrel_offset"] if item.get("barrel_offset") != null else 0.0
		player.set_ranged_stats(item["damage"], item["fire_rate"], offset)

func roll_item() -> Dictionary:
	var r := randf() * 100.0
	var rarity: String
	if   r < 1.0:  rarity = "legendary"
	elif r < 5.0:  rarity = "epic"
	elif r < 15.0: rarity = "rare"
	elif r < 45.0: rarity = "uncommon"
	else:          rarity = "common"
	return _random_from_rarity(rarity)

func random_item() -> Dictionary:
	return ITEMS[randi() % ITEMS.size()]

func items_of_rarity(rarity: String) -> Array:
	return ITEMS.filter(func(i): return i.rarity == rarity)

func _random_from_rarity(rarity: String) -> Dictionary:
	var pool := items_of_rarity(rarity)
	return pool[randi() % pool.size()]
