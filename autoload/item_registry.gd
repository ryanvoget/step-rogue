extends Node

const ITEMS := [
	{ "name": "Staff",                             "rarity": "common",    "file": "Staff_Asset.png",                            "type": "weapon"    },
	{ "name": "Laser Blaster",                     "rarity": "common",    "file": "Laser_Blaster_Asset.png",                    "type": "weapon"    },
	{ "name": "Punching Robot Gloves",             "rarity": "common",    "file": "Punching_Robot_Gloves_Asset.png",            "type": "weapon"    },
	{ "name": "Sticky Grenade",                    "rarity": "common",    "file": "Sticky_Grenade_Asset.png",                   "type": "equipment" },
	{ "name": "Smoke Grenade",                     "rarity": "common",    "file": "Smoke_Grenade_Asset.png",                    "type": "equipment" },
	{ "name": "Blast Grenade",                     "rarity": "common",    "file": "Blast_Grenade_Asset.png",                    "type": "equipment" },
	{ "name": "Small Heal Vial",                   "rarity": "common",    "file": "Small_Heal_Vial_Asset.png",                  "type": "heal"      },
	{ "name": "Speed Boost Battery",               "rarity": "common",    "file": "Speed_Boost_Battery_Asset.png",              "type": "equipment" },
	{ "name": "Electric Baton",                    "rarity": "common",    "file": "Electric_Baton_Asset.png",                   "type": "weapon"    },
	{ "name": "Detonator Mine",                    "rarity": "common",    "file": "Detonator_Mine_Asset.png",                   "type": "equipment" },
	{ "name": "Metallic Whip",                     "rarity": "common",    "file": "Metallic_Whip_Asset.png",                    "type": "weapon"    },
	{ "name": "Daggers",                           "rarity": "common",    "file": "Daggers_Asset.png",                          "type": "weapon"    },
	{ "name": "Passive Health Regen Vial",         "rarity": "common",    "file": "Passive_Health_Regen_Vial_Asset.png",        "type": "defensive" },
	{ "name": "Force Push Bracelet",               "rarity": "common",    "file": "Force_Push_Bracelet_Asset.png",              "type": "equipment" },
	{ "name": "Light Shield Barrier",              "rarity": "common",    "file": "Light_Shield_Barrier_Asset.png",             "type": "defensive" },
	{ "name": "Warhammer",                         "rarity": "common",    "file": "Warhammer_Asset.png",                        "type": "weapon"    },
	{ "name": "Molitov Grenade",                   "rarity": "common",    "file": "Molitov_Grenade_Asset.png",                  "type": "equipment" },
	{ "name": "Magnetic Grenade",                  "rarity": "common",    "file": "Magnetic_Grenade_Asset.png",                 "type": "equipment" },
	{ "name": "Deployable Barrier Wall",           "rarity": "common",    "file": "Deployable_Barrier_Wall_Asset.png",          "type": "equipment" },
	{ "name": "Grapple Hook",                      "rarity": "common",    "file": "Grapple_Hook_Asset.png",                     "type": "equipment" },
	{ "name": "Beam Sword",                        "rarity": "uncommon",  "file": "Beam_Sword_Asset.png",                       "type": "weapon"    },
	{ "name": "Mesh Grenade",                      "rarity": "uncommon",  "file": "Mesh_Grenade_Asset.png",                     "type": "equipment" },
	{ "name": "Flash Grenade",                     "rarity": "uncommon",  "file": "Flash_Grenade_Asset.png",                    "type": "equipment" },
	{ "name": "Medium Shield Barrier",             "rarity": "uncommon",  "file": "Medium_Shield_Barrier_Asset.png",            "type": "defensive" },
	{ "name": "Medium Passive Health Regen Vial",  "rarity": "uncommon",  "file": "Medium_Passive_Health_Regen_Vial_Asset.png", "type": "defensive" },
	{ "name": "Double Pistol Blasters",            "rarity": "uncommon",  "file": "Double_Pistol_Blasters_Asset.png",           "type": "weapon"    },
	{ "name": "Ice Grenade",                       "rarity": "uncommon",  "file": "Ice_Grenade_Asset.png",                      "type": "equipment" },
	{ "name": "Distraction Grenade",               "rarity": "uncommon",  "file": "Distraction_Grenade_Asset.png",              "type": "equipment" },
	{ "name": "Turret",                            "rarity": "uncommon",  "file": "Turret_Asset.png",                           "type": "equipment" },
	{ "name": "Wave Ray Gun",                      "rarity": "uncommon",  "file": "Wave_Ray_Gun_Asset.png",                     "type": "weapon"    },
	{ "name": "Freeze Gun",                        "rarity": "uncommon",  "file": "Freeze_Gun_Asset.png",                       "type": "weapon"    },
	{ "name": "Flamethrower",                      "rarity": "uncommon",  "file": "Flamethrower_Asset.png",                     "type": "weapon"    },
	{ "name": "Heal Dispenser Farm",               "rarity": "uncommon",  "file": "Heal_Dispenser_Farm_Asset.png",              "type": "defensive" },
	{ "name": "Hand Cannon Gun",                   "rarity": "uncommon",  "file": "Hand_Cannon_Gun_Asset.png",                  "type": "weapon"    },
	{ "name": "Bigger Speed Boost Battery",        "rarity": "uncommon",  "file": "Bigger_Speed_Boost_Battery_Asset.png",       "type": "equipment" },
	{ "name": "Heavy Shield Barrier",              "rarity": "rare",      "file": "Heavy_Shield_Barrier_Asset.png",             "type": "defensive" },
	{ "name": "Large Warhammer",                   "rarity": "rare",      "file": "Large_Warhammer_Asset.png",                  "type": "weapon"    },
	{ "name": "Throwable Beam Sword",              "rarity": "rare",      "file": "Throwable_Beam_Sword_Asset.png",             "type": "weapon"    },
	{ "name": "Hoverboard",                        "rarity": "rare",      "file": "Hoverboard_Asset.png",                       "type": "equipment" },
	{ "name": "Assault Rifle Blaster",             "rarity": "rare",      "file": "Assault_Rifle_Blaster_Asset.png",            "type": "weapon"    },
	{ "name": "Sniper Rifle Blaster",              "rarity": "rare",      "file": "Sniper_Rifle_Blaster_Asset.png",             "type": "weapon"    },
	{ "name": "Large Passive Health Regen Vial",   "rarity": "rare",      "file": "Large_Passive_Health_Regen_Vial_Asset.png",  "type": "defensive" },
	{ "name": "Temporary Invincible Battery",      "rarity": "rare",      "file": "Temporary_Invincible_Battery_Asset.png",     "type": "equipment" },
	{ "name": "Teleportation Bracelet",            "rarity": "rare",      "file": "Teleportation_Bracelet_Asset.png",           "type": "equipment" },
	{ "name": "Advanced Turret",                   "rarity": "rare",      "file": "Advanced_Turret_Asset.png",                  "type": "equipment" },
	{ "name": "Sidekick Robot",                    "rarity": "epic",      "file": "Sidekick_Robot_Asset.png",                   "type": "equipment" },
	{ "name": "Double Beam Swords",                "rarity": "epic",      "file": "Double_Beam_Swords_Asset.png",               "type": "weapon"    },
	{ "name": "Void Grenade Launcher",             "rarity": "epic",      "file": "Void_Grenade_Launcher_Asset.png",            "type": "weapon"    },
	{ "name": "Reflect Shield",                    "rarity": "epic",      "file": "Reflect_Shield_Asset.png",                   "type": "defensive" },
	{ "name": "Stim Shot",                         "rarity": "epic",      "file": "Stim_Shot_Asset.png",                        "type": "defensive" },
	{ "name": "Dennis",                            "rarity": "legendary", "file": "Dennis_Asset.png",                           "type": "equipment" },
]

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
