extends Node

# Equipment-point budget: the player can equip items totalling up to EQUIPMENT_POINT_BUDGET
# points across the three slots, costed by rarity (see RARITY_COST). Over budget, the run can't
# be started (enforced in menu.gd's Play button; shown on the character screen).
const EQUIPMENT_POINT_BUDGET := 10
const RARITY_COST := {"common": 1, "uncommon": 3, "rare": 5, "epic": 7, "legendary": 9}

func item_points(item: Dictionary) -> int:
	if item == null or item.is_empty():
		return 0
	return int(RARITY_COST.get(item.get("rarity", ""), 0))

# Total point cost of everything currently equipped in the three slots.
func equipped_points() -> int:
	var total := 0
	for key in ["equipped_weapon", "equipped_equipment", "equipped_defensive"]:
		total += item_points(SaveManager.get_slot(key))
	return total

func over_equipment_budget() -> bool:
	return equipped_points() > EQUIPMENT_POINT_BUDGET

# damage/heal/block are null when not applicable to that item. Asset_List.numbers is the
# single source of truth for the item roster and for name/rarity/type/damage/heal/block —
# the Asset_List*.xlsx files are throwaway exports of it, never edit those. Everything else
# below (fire_rate, ranges, the behavior flags) is gameplay tuning that lives only here.
# fire_rate (seconds between attacks) is only set for weapons tuned for actual gameplay so far;
# null means "not wired up yet, falls back to default weapon behavior". Used for both ranged
# fire rate and melee swing rate.
# barrel_offset (pixels) is set for multi-barrel weapons (e.g. dual-wielded pistols) to fire
# a bullet from each side of the aim point instead of one from dead center; null/0 = single shot.
# melee_range (pixels) marks a weapon as melee instead of ranged when set: on attack it swings
# in a cone in front of the player instead of firing a bullet_scene projectile.
# knockback (px/sec impulse) is meaningful for melee weapons and any ranged weapon whose
# bullet applies it on hit (e.g. Wave Ray Gun); null/0 = no knockback.
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
# beam_range (pixels) marks a weapon as a beam instead of ranged/melee when set (e.g.
# Flamethrower): a continuous cone, active every frame the fire input is held (no fire_rate
# cooldown), that ticks damage (used here as damage-per-second) to whatever it's touching.
# beam_arc_degrees (float) is the beam's cone width; only set on beam weapons.
# beam_tick_interval (seconds) is how often continuous contact deals a damage tick; null/1.0
# default = once per second. Only meaningful on beam weapons.
# burn_damage/burn_duration are only meaningful on beam weapons: when the beam stops
# touching a target (leaves the cone/range, or the beam is released/switched away from),
# that target burns for burn_duration seconds, taking burn_damage once per second.
# freeze_duration (seconds) marks a "frozen" effect (e.g. Freeze Gun on ranged weapons, Ice
# Grenade on throwables): fully halts the enemy's AI for that long — the same underlying
# mechanism melee stun uses (see enemy_basic.gd's take_damage stun_duration/stun_color/
# is_freeze), just flashed blue instead of white/whatever stun_color. Automatically slows
# movement by 50% for THAW_SLOW_DURATION (3s) once it "thaws" (expires) — see enemy_basic.gd's
# THAW_SLOW_MULTIPLIER/THAW_SLOW_DURATION, which apply to every freeze source uniformly, not a
# per-item field. On a ranged weapon, the bullet itself is also drawn as a blue laser rectangle
# instead of the default yellow dot whenever freeze_duration > 0 (see bullet.gd).
# wave_max_width (pixels) is only meaningful on ranged weapons (e.g. Wave Ray Gun): the
# bullet is drawn (and hit-scaled) as an expanding ellipse instead of the default yellow dot,
# growing from a small starting width up to wave_max_width as it approaches
# bullet.gd's WAVE_MAX_TRAVEL_DISTANCE (~ the room's diagonal, the longest possible shot).
# sniper_charge_time (seconds) marks a weapon as a charge-bar sniper (e.g. Sniper Rifle
# Blaster) instead of ranged/melee/beam: no joystick/button at all — mobile_controls.gd
# draws a bar in that spot that fills over this many seconds, tap it once full to arm, then
# tap anywhere on screen to fire at that point (player movement locks while armed). Ignores
# fire_rate entirely; uses damage and bullet_speed like a normal bullet.
# thrown_melee (bool) marks a weapon as a thrown-and-returns projectile (e.g. Throwable Beam
# Sword) instead of ranged/melee/beam/sniper: fired from the normal aim joystick, it flies
# out until it hits a wall then flies back to the player, dealing damage in a constant
# thrown_radius circle the whole way (out and back — same enemy can be hit twice). The
# weapon can't fire again until every copy currently in flight has returned. Uses damage,
# bullet_speed (travel speed), thrown_radius, and (optionally) barrel_offset; ignores
# fire_rate entirely.
# thrown_radius (pixels) is the AOE circle radius for thrown_melee weapons.
# barrel_offset on a thrown_melee weapon (e.g. Double Beam Swords) throws two, staggered,
# the same way it makes ranged weapons (e.g. Double Pistol Blasters) fire two.
# launcher (bool) marks a weapon as a grenade-launching weapon (e.g. Void Grenade Launcher)
# instead of ranged/melee/beam/sniper/thrown_melee: fired from the normal aim joystick at the
# usual fire_rate cadence, it flies throw_distance in front of the player, waits
# explode_delay, then either bursts once (gravity_duration == 0, using damage as the AOE hit)
# or becomes a gravity_duration-second gravity well (using damage as the per-tick damage
# instead) that continuously pulls every enemy within aoe_radius toward its center and deals
# damage every gravity_tick_interval — see grenade.gd. Shares throw_distance/aoe_radius/
# explode_delay field names with throwable equipment (same meaning, different trigger).
# heal_item (bool) marks a defensive item as usable via the blue heal button mobile_controls
# shows between the move and aim joysticks (e.g. Small Heal Vial, the Passive Health Regen
# Vials, Stim Shot, Heal Dispenser Farm, the Shield Barriers). All of the following are
# optional and independent (an item can use any combination):
# heal_instant (int) heals this much immediately.
# heal_full (bool) heals to max_health immediately instead of by a fixed amount.
# heal_regen_amount/heal_regen_interval/heal_regen_duration start a heal-over-time effect:
# heal_regen_amount HP every heal_regen_interval seconds (default 1.0), for
# heal_regen_duration seconds total.
# speed_boost_multiplier/speed_boost_duration temporarily multiply movement speed.
# heal_dispenser (bool) marks a heal_item (e.g. Heal Dispenser Farm) as placing a stationary
# dispenser prop at the player's position instead of healing them directly: every
# dispenser_interval seconds, for dispenser_duration seconds total, it drops a heal_pickup.tscn
# instance (visually the Small Heal Vial, via ItemRegistry.get_item_by_name) at a random spot
# within heal_dispenser.gd's SPAWN_RADIUS of itself, then removes itself. Each dropped vial
# heals dispenser_heal_amount once when the player walks over it, then disappears. See
# heal_dispenser.gd/heal_pickup.gd and world.gd/sandbox.gd's _spawn_heal_dispenser.
# shield (bool) marks a heal_item (e.g. Light/Medium/Heavy Shield Barrier) as a repeatable
# on/off toggle instead of healing: each tap of the blue button flips it (world.gd's
# _use_heal_item deliberately bypasses the usual one-shot heal_item_deployed gate for
# shield-type items so it can fire more than once), and while active it fully blocks all
# incoming damage using the item's own block value as an HP pool (Light 10, Medium 25, Heavy
# 50) — reused directly as the shield's absorb capacity, not a separate field. Each hit drains
# the pool by that hit's damage instead of touching the player's own health; toggling off does
# NOT refill/reset the pool, it just stops draining until toggled back on. Once the pool hits
# zero the shield "breaks" and can never be reactivated. Unlike every other heal_item, the
# button doesn't disappear the instant it's tapped — mobile_controls.gd's _heal_active shows
# it (with a small HP bar underneath, dimmer while toggled off, see _draw_shield_control) for
# as long as the shield hasn't broken, only removing both once it does. See player.gd's
# configure_shield/toggle_shield and its take_damage shield-block branch.
# shield_reflect (bool) marks a shield item (e.g. Reflect Shield) as additionally dealing each
# absorbed hit's damage straight back to whoever attacked, on top of (not instead of) depleting
# the pool exactly like any other shield. Requires the hit to carry an attacker reference
# (bullet.gd's shooter for lasers, enemy_basic.gd's ATTACK state passing itself for melee —
# take_damage's attacker param); a hit with no attacker just depletes the pool like normal,
# nothing to reflect at. Same block-value-as-HP-pool convention as shield.
# aim_preview (bool) marks equipment (e.g. Grapple Hook, Sticky Grenade) as wanting the live
# dotted aim-ray line while dragging the green equipment joystick (not just a static throw
# knob) — see player.gd's get_aim_target/_draw_aim_preview. Also set throwable: true for the
# joystick UI itself. Range is throw_distance if set, else uncapped (Grapple Hook's case).
# grapple (bool) marks equipment (e.g. Grapple Hook) as using custom release behavior instead
# of a thrown grenade: the aim ray hits either a wall (player dashes to it) or an enemy
# (dragged to just in front of the player). See player.gd's start_grapple_dash and world.gd/
# sandbox.gd's _use_grapple. No other fields needed — the effect is entirely position-based.
# teleport (bool) marks equipment (e.g. Teleportation Bracelet) as using custom release
# behavior instead of a thrown grenade: unlike every other green-joystick item, the aim target
# (player.gd's get_teleport_target) is never a raycast against walls/enemies — it's a
# free-floating point in the aimed direction, only clamped to stay inside the room, previewed
# as a dotted circle (~1.5x the player's size) instead of a dotted line. On release, the player
# is moved there directly (player.gd's teleport_to). Set throwable/aim_preview/scaleable_throw
# like a normal throwable so the joystick UI and drag-scaled range work the same way; throw_
# distance is the max range (typically ≥ the room's diagonal so anywhere is reachable at full
# drag). See world.gd/sandbox.gd's _use_teleport.
# sticky (bool) marks equipment (e.g. Sticky Grenade) as using custom release behavior
# instead of a normal thrown grenade: if the aim ray hits an enemy within throw_distance, it
# sticks to them (see grenade.gd's configure_stick) and deals sticky_damage after
# sticky_delay seconds instead of a normal AOE burst; if it misses (ray reaches throw_distance
# or hits a wall first), it explodes as a normal AOE burst there using damage/aoe_radius/
# explode_delay like any other thrown grenade. See world.gd/sandbox.gd's _use_sticky_grenade.
# confuse_duration (seconds) marks a thrown grenade (e.g. Smoke Grenade) as confusing instead
# of damaging: every enemy within aoe_radius on explosion has its movement reversed (see
# enemy_basic.gd's apply_confuse) for confuse_duration seconds and flashes white, instead of
# taking damage. Shares throw_distance/aoe_radius/explode_delay with normal throwables; damage
# is left null.
# linger_duration (seconds) marks a thrown grenade (e.g. Molotov Grenade) as leaving a
# lingering fire circle after its normal one-shot damage burst (still uses damage/aoe_radius/
# explode_delay like any other throwable): for linger_duration seconds after exploding, every
# enemy inside the circle — whether already there at explosion time or walking in afterward —
# is burned (enemy_basic.gd's apply_burn) once each using linger_burn_damage/
# linger_burn_duration. See grenade.gd's _apply_linger_burn.
# distract_duration (seconds) marks a thrown grenade (e.g. Distraction Grenade) as pulling
# every enemy on the map — regardless of distance, unlike every other burst mode here, which
# only reaches aoe_radius — toward where it landed for distract_duration seconds instead of
# damaging anyone (enemy_basic.gd's apply_distract). Pure crowd control, no damage.
# flash_duration (seconds) marks a thrown grenade (e.g. Flash Grenade) as blinding every enemy
# within aoe_radius on explosion instead of damaging anyone (enemy_basic.gd's apply_blind):
# while blinded, that enemy's own attacks miss the player entirely — melee damage is skipped,
# and any bullet it fires is spawned unable to ever hit the player (see
# GameManager.spawn_enemy_bullet's will_miss param), so it visually flies past instead of
# connecting. Decided per-shot at the moment it's fired, not retroactive. Pure crowd control,
# no damage to the enemy itself.
# mesh_count (int) marks a thrown grenade (e.g. Mesh Grenade) as popping this many independent
# mini grenades out equidistant around the edge of aoe_radius, on top of (not instead of) the
# normal damage burst using damage/aoe_radius/explode_delay. Each mini grenade flies out and
# detonates on its own shortly after, dealing mesh_damage in a circle of aoe_radius *
# mesh_radius_ratio — with no coordination between them, so an enemy standing where two
# adjacent mini blast circles overlap takes mesh_damage from each one independently, once per
# circle it's touching. See grenade.gd's _spawn_mesh_grenades.
# scaleable_throw (bool) marks throwable equipment as having its actual throw/effect distance
# scale with how far the throw joystick is dragged, from 0 up to the item's full throw_distance
# (or GRAPPLE_MAX_DISTANCE for Grapple Hook, which has no throw_distance of its own) at a
# full-length drag, instead of always reaching full range regardless of drag amount. The live
# dotted aim-preview line (if aim_preview is also set) shrinks/grows with the drag to match
# exactly what will happen on release. This is the generic "scaleable throwing" mechanic —
# currently set on every throwable item, and any future one can opt in with this one flag. See
# mobile_controls.gd's throw-joystick drag handling, player.gd's _draw_aim_preview, and
# world.gd/sandbox.gd's _throw_grenade/_use_grapple/_use_sticky_grenade.
# battery (bool) marks equipment (e.g. Speed Boost Battery) as using a tap-button-only
# activate/deplete/recharge cycle instead of a one-shot placeable/throwable: tapping the green
# equipment button (not a joystick) immediately grants speed_boost_multiplier movement speed,
# telegraphed by a bar (mobile_controls.gd's _draw_battery_bar) that depletes over
# battery_active_duration seconds; once empty it recharges over battery_recharge_duration
# seconds (same bar, filling back up), then the button reappears — repeatable indefinitely,
# unlike placeable/throwable equipment's one-shot-per-run equipment_deployed flag. Reuses
# speed_boost_multiplier (see heal_item fields above) for the multiplier itself. See
# player.gd's configure_battery/activate_battery/_tick_battery.
# mine (bool) marks equipment (e.g. Detonator Mine) as a two-tap plain button (not a joystick)
# instead of a one-shot placeable/throwable: the first tap drops it at the player's current
# position (no flight/fuse, unlike a thrown grenade — see grenade.gd's configure_mine), and the
# button switches to a highlighted "armed" shade (mobile_controls.gd's _draw_mine_button) until
# the second tap detonates it (grenade.gd's detonate()) for a normal one-shot AOE burst using
# damage/aoe_radius, same as a thrown grenade's blast. One-shot per run in world.gd (like other
# equipment) but repeatable in sandbox.gd for testing. See world.gd/sandbox.gd's _use_mine.
# force_push (bool) marks equipment (e.g. Force Push Bracelet) as a hold-to-channel green
# joystick instead of any of the above: dragging it past the dead zone in a direction pushes
# every enemy within force_push_range/force_push_arc_degrees of the player, aimed at that
# drag direction (a green cone, not the player's facing — mobile_controls.gd's
# _draw_force_push_control shows a mana bar above the joystick) continuously back out to the
# edge of that range, for as long as it's held past the dead zone and mana remains. Draws down
# force_push_mana_max at force_push_mana_drain_rate per second while held; mana never
# regenerates, and the joystick greys out (bar dims from 50% to 25% opacity) once it hits zero,
# for the rest of the run. See player.gd's configure_force_push/_tick_force_push and
# GameManager.force_push_dir.
# barrier (bool) marks equipment (e.g. Deployable Barrier Wall) as a two-tap trail-placement
# button (not a joystick, like mine): the first tap starts tracing a line under the player as
# they walk, up to barrier_max_length pixels total — auto-finalizing at the cap, or early on a
# second tap (mobile_controls.gd shows the same highlighted button shade as an armed Detonator
# Mine while tracing). The traced path bakes into a permanent chain of StaticBody2D wall
# segments (barrier_thickness pixels thick, collision layer 8 — the same layer the room's
# boundary walls use) that blocks player/enemy movement but not bullets or thrown equipment,
# neither of which check that layer. One-shot per run in world.gd (like other equipment) but
# repeatable in sandbox.gd for testing. See barrier_wall.gd and world.gd/sandbox.gd's
# _use_barrier.
# hoverboard (bool) marks equipment (e.g. Hoverboard) as a plain on/off toggle button (not a
# joystick, tap-cycle, or hold): each tap flips mounted/unmounted, no timer or resource — fully
# repeatable in both world.gd and sandbox.gd (never sets equipment_deployed). While mounted,
# movement speed is multiplied by hoverboard_speed_multiplier and a board sprite (reusing the
# item's icon) is shown under the player, rotating to track their facing angle every frame. See
# player.gd's configure_hoverboard/toggle_hoverboard.
# invincible (bool) marks equipment (e.g. Temporary Invincible Battery) as a plain on/off
# toggle button (not a joystick): each tap flips active/inactive, fully repeatable in both
# world.gd and sandbox.gd (never sets equipment_deployed) as long as mana remains — same
# non-regenerating-mana pattern as force_push (invincible_mana_max at
# invincible_mana_drain_rate per second while active; mana never regenerates, and the button
# greys out once it hits zero, for the rest of the run). While active, the player takes no
# damage at all (take_damage is a no-op) and is shown with a pulsing purple glow. See
# player.gd's configure_invincible/toggle_invincible/_tick_invincible/is_invincible.
# sidekick (bool) marks equipment (e.g. Sidekick Robot) as a passive companion with no green
# button at all — active automatically for the whole run the instant it's equipped (spawned
# directly in world.gd's _ready()/sandbox.gd's _on_item_selected(), not through the
# deploy_equipment_requested flow every other piece of equipment uses). Uses damage/fire_rate/
# bullet_speed like a placeable turret (see turret.gd), but instead of sitting still it follows
# the player, trailing sidekick_robot.gd's FOLLOW_DISTANCE (25px) behind their current
# movement direction, auto-firing at the nearest enemy the whole time.
# summon (bool) marks equipment (e.g. Dennis) as a one-shot summon button, drawn gold with
# summon_label's text (e.g. "SUMMON DENNIS") instead of the plain colored circle every other
# one-shot equipment button uses (mobile_controls.gd's _draw_summon_button) — same
# equipment_deployed one-shot gating as placeable (Turret). Dennis's own damage/fire_rate/
# bullet_speed are read live from Assault Rifle Blaster's row at summon time
# (ItemRegistry.get_item_by_name), not stored on his own row, so they can never drift out of
# sync — his own damage/fire_rate/bullet_speed fields are left null. Every 5 seconds he also
# throws a random item from "the whole grenade list" (ItemRegistry.random_grenade(), every item
# whose name ends in "Grenade") at the nearest enemy. See dennis.gd and world.gd/sandbox.gd's
# _spawn_dennis/_summon_dennis.
const ITEMS := [
	{ "name": "Staff",                             "rarity": "common",    "file": "Staff_Asset.png",                            "type": "weapon",    "damage": 3,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	{ "name": "Laser Blaster",                     "rarity": "common",    "file": "Laser_Blaster_Asset.png",                    "type": "weapon",    "damage": 2,   "heal": null, "block": null, "fire_rate": 0.2 , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	# Punching Robot Gloves removed (was a common 2dmg x2-hit melee weapon). It was the only
	# user of no_move_lock, so that flag is now read but never set (player.gd handles it fine).
	{ "name": "Sticky Grenade",                    "rarity": "common",    "file": "Sticky_Grenade_Asset.png",                   "type": "equipment", "damage": 5,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 375.0, "aoe_radius": 50.0, "explode_delay": 0.25, "sticky": true, "sticky_damage": 30, "sticky_delay": 1.0 },
	{ "name": "Smoke Grenade",                     "rarity": "common",    "file": "Smoke_Grenade_Asset.png",                    "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "confuse_duration": 2.0 },
	{ "name": "Blast Grenade",                     "rarity": "common",    "file": "Blast_Grenade_Asset.png",                    "type": "equipment", "damage": 20,  "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "explode_delay": 0.25, "aoe_radius": 100.0 },
	{ "name": "Small Heal Vial",                   "rarity": "common",    "file": "Small_Heal_Vial_Asset.png",                  "type": "defensive", "damage": null, "heal": 10,  "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_instant": 10 },
	# Speed Boost Battery removed (was common battery equipment) — see the Bigger Speed Boost
	# Battery note below for what this means for the `battery` mechanic as a whole.
	{ "name": "Electric Baton",                    "rarity": "common",    "file": "Electric_Baton_Asset.png",                   "type": "weapon",    "damage": 4,   "heal": null, "block": null, "fire_rate": 0.67, "barrel_offset": null, "melee_range": 128.0, "knockback": null, "placeable": false, "bullet_speed": null, "stun": 0.1, "melee_joystick": true, "chain_lightning": true, "element": "electric" },
	{ "name": "Detonator Mine",                    "rarity": "common",    "file": "Detonator_Mine_Asset.png",                   "type": "equipment", "damage": 20,  "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "mine": true, "aoe_radius": 100.0 },
	{ "name": "Metallic Whip",                     "rarity": "uncommon",  "file": "Metallic_Whip_Asset.png",                    "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 256.0, "knockback": null, "placeable": false, "bullet_speed": null, "melee_arc_degrees": 33.3333, "stun": 0.2, "melee_joystick": true },
	{ "name": "Fire Daggers",                      "rarity": "common",    "file": "Fire_Daggers_Asset.png",                     "type": "weapon",    "damage": 1,   "heal": null, "block": null, "fire_rate": 0.25, "barrel_offset": null, "melee_range": 96.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_hits": 2, "melee_joystick": true, "element": "fire", "burn_damage": 2, "burn_duration": 3.0 },
	{ "name": "Passive Health Regen Vial",         "rarity": "common",    "file": "Passive_Health_Regen_Vial_Asset.png",        "type": "defensive", "damage": null, "heal": 1,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_regen_amount": 1, "heal_regen_duration": 10.0 },
	{ "name": "Force Push Bracelet",               "rarity": "common",    "file": "Force_Push_Bracelet_Asset.png",              "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "force_push": true, "force_push_range": 192.0, "force_push_arc_degrees": 100.0, "force_push_mana_max": 100.0, "force_push_mana_drain_rate": 10.0 },
	{ "name": "Light Shield Barrier",              "rarity": "common",    "file": "Light_Shield_Barrier_Asset.png",             "type": "defensive", "damage": null, "heal": null, "block": 10 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "shield": true },
	{ "name": "Warhammer",                         "rarity": "common",    "file": "Warhammer_Asset.png",                        "type": "weapon",    "damage": 8,   "heal": null, "block": null, "fire_rate": 1.0 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	{ "name": "Molitov Grenade",                   "rarity": "common",    "file": "Molitov_Grenade_Asset.png",                  "type": "equipment", "damage": 10,   "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "linger_duration": 3.0, "linger_burn_damage": 5, "linger_burn_duration": 3.0 },
	{ "name": "Magnetic Grenade",                  "rarity": "common",    "file": "Magnetic_Grenade_Asset.png",                 "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "gravity_duration": 2.0 },
	{ "name": "Deployable Barrier Wall",           "rarity": "common",    "file": "Deployable_Barrier_Wall_Asset.png",          "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "barrier": true, "barrier_max_length": 250.0, "barrier_thickness": 12.0 },
	# Grapple Hook removed (was uncommon equipment). It was the only user of the `grapple` field,
	# so player.gd's start_grapple_dash / world.gd's _use_grapple are now unreachable but intact.
	{ "name": "Beam Sword",                        "rarity": "uncommon",  "file": "Beam_Sword_Asset.png",                       "type": "weapon",    "damage": 10,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	{ "name": "Mesh Grenade",                      "rarity": "uncommon",  "file": "Mesh_Grenade_Asset.png",                     "type": "equipment", "damage": 20,  "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "mesh_count": 8, "mesh_radius_ratio": 0.25, "mesh_damage": 6 },
	{ "name": "Flash Grenade",                     "rarity": "uncommon",  "file": "Flash_Grenade_Asset.png",                    "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "flash_duration": 4.0 },
	{ "name": "Medium Shield Barrier",             "rarity": "uncommon",  "file": "Medium_Shield_Barrier_Asset.png",            "type": "defensive", "damage": null, "heal": null, "block": 25 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "shield": true },
	{ "name": "Medium Passive Health Regen Vial",  "rarity": "uncommon",  "file": "Medium_Passive_Health_Regen_Vial_Asset.png", "type": "defensive", "damage": null, "heal": 1,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_regen_amount": 1, "heal_regen_duration": 20.0 },
	{ "name": "Double Pistol Blasters",            "rarity": "uncommon",  "file": "Double_Pistol_Blasters_Asset.png",           "type": "weapon",    "damage": 2,   "heal": null, "block": null, "fire_rate": 0.25 , "barrel_offset": 6.0, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	{ "name": "Ice Grenade",                       "rarity": "uncommon",  "file": "Ice_Grenade_Asset.png",                      "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "freeze_duration": 4.0 },
	{ "name": "Distraction Grenade",               "rarity": "uncommon",  "file": "Distraction_Grenade_Asset.png",              "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "throwable": true, "aim_preview": true, "scaleable_throw": true, "throw_distance": 250.0, "aoe_radius": 100.0, "explode_delay": 0.25, "distract_duration": 4.0 },
	{ "name": "Turret",                            "rarity": "uncommon",  "file": "Turret_Asset.png",                           "type": "equipment", "damage": 2,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": true, "bullet_speed": 1040.0 },
	{ "name": "Wave Ray Gun",                      "rarity": "uncommon",  "file": "Wave_Ray_Gun_Asset.png",                     "type": "weapon",    "damage": 7,   "heal": null, "block": null, "fire_rate": 0.75, "barrel_offset": null, "melee_range": null, "knockback": 80.0, "placeable": false, "bullet_speed": null, "wave_max_width": 146.84, "element": "void" },
	{ "name": "Freeze Gun",                        "rarity": "rare",      "file": "Freeze_Gun_Asset.png",                       "type": "weapon",    "damage": 7,   "heal": null, "block": null, "fire_rate": 0.75, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "freeze_duration": 1.5, "element": "ice" },
	{ "name": "Ice Staff",                         "rarity": "rare",      "file": "Ice_Staff_Asset.png",                        "type": "weapon",    "damage": 8,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_joystick": true, "element": "ice", "melee_freeze_duration": 1.0 },
	{ "name": "Fire Blaster",                      "rarity": "rare",      "file": "Fire_Blaster_Asset.png",                     "type": "weapon",    "damage": 6,   "heal": null, "block": null, "fire_rate": 0.75, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "element": "fire", "burn_damage": 3, "burn_duration": 3.0 },
	{ "name": "Electro Blaster",                   "rarity": "rare",      "file": "Electro_Blaster_Asset.png",                  "type": "weapon",    "damage": 5,   "heal": null, "block": null, "fire_rate": 0.75, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "element": "electric", "chain_lightning": true },
	# Flamethrower removed for now (was uncommon beam weapon).
	{ "name": "Heal Dispenser Farm",                "rarity": "uncommon",  "file": "Heal_Dispenser_Farm_Asset.png",              "type": "defensive", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_dispenser": true, "dispenser_interval": 5.0, "dispenser_duration": 20.0, "dispenser_heal_amount": 5 },
	# Hand Cannon fire_rate 1.5 -> 1.25: fire_rate is the INTERVAL between shots, so +20% rate of
	# fire is interval / 1.2 (0.667 -> 0.8 shots/sec), not interval * 0.8.
	{ "name": "Hand Cannon Gun",                   "rarity": "uncommon",  "file": "Hand_Cannon_Gun_Asset.png",                  "type": "weapon",    "damage": 12,  "heal": null, "block": null, "fire_rate": 1.25, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	# Bigger Speed Boost Battery removed (was uncommon battery equipment). With both batteries
	# gone nothing sets `battery` any more, so the whole tap-to-activate / deplete / recharge
	# path (mobile_controls' _draw_battery_bar, player.gd's activate_battery, GameManager's
	# battery state) is unreachable but left intact for a future battery item.
	{ "name": "Heavy Shield Barrier",              "rarity": "rare",      "file": "Heavy_Shield_Barrier_Asset.png",             "type": "defensive", "damage": null, "heal": null, "block": 50 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "shield": true },
	{ "name": "Large Warhammer",                   "rarity": "uncommon",  "file": "Large_Warhammer_Asset.png",                  "type": "weapon",    "damage": 8,   "heal": null, "block": null, "fire_rate": 1.0 , "barrel_offset": null, "melee_range": 150.0, "knockback": 270.0, "placeable": false, "bullet_speed": null, "melee_joystick": true },
	# Throwable Beam Sword removed (was a rare 10dmg weapon). It was the only user of
	# thrown_melee, so scenes/thrown_weapon and player.gd's throw path are now unused but intact.
	{ "name": "Hoverboard",                        "rarity": "rare",      "file": "Hoverboard_Asset.png",                       "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "hoverboard": true, "hoverboard_speed_multiplier": 2.0 },
	{ "name": "Assault Rifle Blaster",             "rarity": "rare",      "file": "Assault_Rifle_Blaster_Asset.png",            "type": "weapon",    "damage": 2,   "heal": null, "block": null, "fire_rate": 0.078125, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null },
	# Sniper Rifle Blaster removed (was a rare 20dmg charge weapon). It was the only user of
	# sniper_charge_time, so the charge-bar control and player.gd's sniper path are now unused.
	{ "name": "Large Passive Health Regen Vial",   "rarity": "rare",      "file": "Large_Passive_Health_Regen_Vial_Asset.png",  "type": "defensive", "damage": null, "heal": 2,   "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_regen_amount": 2, "heal_regen_duration": 20.0 },
	{ "name": "Temporary Invincible Battery",      "rarity": "rare",      "file": "Temporary_Invincible_Battery_Asset.png",     "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "invincible": true, "invincible_mana_max": 100.0, "invincible_mana_drain_rate": 10.0 },
	# Teleportation Bracelet is deliberately NOT an equippable item: the name now belongs to the
	# lobby walk-over dash pickup (scenes/dash_pickup). The `teleport` equipment plumbing below
	# and in world.gd/sandbox.gd/player.gd is left intact for any future item, but nothing sets
	# it. Asset_List.numbers still lists a "teleportation braclet" row — that row is stale.
	{ "name": "Advanced Turret",                   "rarity": "rare",      "file": "Advanced_Turret_Asset.png",                  "type": "equipment", "damage": 4,   "heal": null, "block": null, "fire_rate": 0.35, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": true, "bullet_speed": 1040.0 },
	{ "name": "Sidekick Robot",                    "rarity": "epic",      "file": "Sidekick_Robot_Asset.png",                   "type": "equipment", "damage": 2,   "heal": null, "block": null, "fire_rate": 0.175, "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": 1040.0, "sidekick": true },
	{ "name": "Double Beam Swords",                "rarity": "epic",      "file": "Double_Beam_Swords_Asset.png",               "type": "weapon",    "damage": 7,   "heal": null, "block": null, "fire_rate": 0.5 , "barrel_offset": null, "melee_range": 128.0, "knockback": 180.0, "placeable": false, "bullet_speed": null, "melee_hits": 2, "melee_joystick": true },
	# Void Grenade Launcher removed (was the epic gravity-well weapon). It was the only user of
	# `launcher`, so grenade.gd's gravity-well path is now only reached by Magnetic Grenade.
	{ "name": "Reflect Shield",                    "rarity": "epic",      "file": "Reflect_Shield_Asset.png",                   "type": "defensive", "damage": null, "heal": null, "block": 50 , "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "shield": true, "shield_reflect": true },
	{ "name": "Stim Shot",                         "rarity": "epic",      "file": "Stim_Shot_Asset.png",                        "type": "defensive", "damage": null, "heal": 100, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "heal_item": true, "heal_full": true, "speed_boost_multiplier": 1.5, "speed_boost_duration": 10.0 },
	{ "name": "Dennis",                            "rarity": "legendary", "file": "Dennis_Asset.png",                           "type": "equipment", "damage": null, "heal": null, "block": null, "fire_rate": null , "barrel_offset": null, "melee_range": null, "knockback": null, "placeable": false, "bullet_speed": null, "summon": true, "summon_label": "SUMMON DENNIS" },
]

# Applies an item's look and (if tuned) gameplay stats to the player. Safe to call with
# items that aren't weapons or don't have their stats set yet — only the texture changes then.
func equip_on_player(player: Node, item: Dictionary) -> void:
	if item.is_empty():
		return
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	player.set_weapon_texture(tex)
	if item["type"] != "weapon" or item.get("damage") == null:
		return
	# Beam weapons (e.g. Flamethrower) don't use fire_rate — they're continuous while held —
	# so this is checked before the fire_rate gate that melee/ranged both still require.
	if item.get("beam_range") != null:
		var arc: float = item["beam_arc_degrees"] if item.get("beam_arc_degrees") != null else 0.0
		var burn_damage: int = item["burn_damage"] if item.get("burn_damage") != null else 0
		var burn_duration: float = item["burn_duration"] if item.get("burn_duration") != null else 0.0
		var tick_interval: float = item["beam_tick_interval"] if item.get("beam_tick_interval") != null else 1.0
		player.set_beam_stats(item["damage"], item["beam_range"], arc, burn_damage, burn_duration, tick_interval)
		return
	# Sniper (e.g. Sniper Rifle Blaster) also skips fire_rate entirely — its cadence is
	# governed by the charge bar instead (see set_sniper_stats).
	if item.get("sniper_charge_time") != null:
		var speed: float = item["bullet_speed"] if item.get("bullet_speed") != null else -1.0
		player.set_sniper_stats(item["damage"], item["sniper_charge_time"], speed)
		return
	# Thrown melee (e.g. Throwable Beam Sword) also skips fire_rate — its "cooldown" is
	# whatever the actual round trip takes, not a fixed duration (see set_thrown_stats).
	if item.get("thrown_melee", false):
		var speed: float = item["bullet_speed"] if item.get("bullet_speed") != null else 520.0
		var radius: float = item["thrown_radius"] if item.get("thrown_radius") != null else 100.0
		var t_offset: float = item["barrel_offset"] if item.get("barrel_offset") != null else 0.0
		player.set_thrown_stats(item["damage"], radius, speed, t_offset)
		return
	if item.get("fire_rate") == null:
		return
	# Launcher (e.g. Void Grenade Launcher) uses fire_rate, unlike beam/sniper/thrown_melee,
	# but still isn't melee or a plain ranged bullet, so it's checked before that branch.
	if item.get("launcher", false):
		var throw_dist: float = item["throw_distance"] if item.get("throw_distance") != null else 200.0
		var radius: float = item["aoe_radius"] if item.get("aoe_radius") != null else 100.0
		var delay: float = item["explode_delay"] if item.get("explode_delay") != null else 0.25
		var g_duration: float = item["gravity_duration"] if item.get("gravity_duration") != null else 0.0
		var g_interval: float = item["gravity_tick_interval"] if item.get("gravity_tick_interval") != null else 0.5
		player.set_launcher_stats(item["damage"], item["fire_rate"], throw_dist, radius, delay, g_duration, g_interval)
		return
	if item.get("melee_range") != null:
		var knockback: float = item["knockback"] if item.get("knockback") != null else 0.0
		var hits: int = item.get("melee_hits") if item.get("melee_hits") != null else 1
		var arc: float = item["melee_arc_degrees"] if item.get("melee_arc_degrees") != null else -1.0
		var stun: float = item["stun"] if item.get("stun") != null else 0.0
		var use_joystick: bool = item.get("melee_joystick") if item.get("melee_joystick") != null else false
		player.set_melee_stats(item["damage"], item["fire_rate"], item["melee_range"], knockback, hits, arc, stun, use_joystick)
		player.set_chain_lightning(item.get("chain_lightning", false)) # Electric Baton arcs to a nearby enemy
		player.set_melee_no_lock(item.get("no_move_lock", false)) # Punching Gloves: keep moving while swinging
		# Elemental melee effects: Fire Daggers burn, Ice Staff freeze.
		var m_burn_dmg: int = item.get("burn_damage") if item.get("burn_damage") != null else 0
		var m_burn_dur: float = item.get("burn_duration") if item.get("burn_duration") != null else 0.0
		var m_freeze: float = item.get("melee_freeze_duration") if item.get("melee_freeze_duration") != null else 0.0
		player.set_melee_effects(m_burn_dmg, m_burn_dur, m_freeze)
	else:
		var offset: float = item["barrel_offset"] if item.get("barrel_offset") != null else 0.0
		var freeze: float = item["freeze_duration"] if item.get("freeze_duration") != null else 0.0
		var ranged_knockback: float = item["knockback"] if item.get("knockback") != null else 0.0
		var wave_width: float = item["wave_max_width"] if item.get("wave_max_width") != null else 0.0
		player.set_ranged_stats(item["damage"], item["fire_rate"], offset, freeze, ranged_knockback, wave_width)
		# Elemental ranged effects: Fire Blaster burn, Electro Blaster chain lightning.
		var r_burn_dmg: int = item.get("burn_damage") if item.get("burn_damage") != null else 0
		var r_burn_dur: float = item.get("burn_duration") if item.get("burn_duration") != null else 0.0
		player.set_ranged_effects(r_burn_dmg, r_burn_dur, item.get("chain_lightning", false))

# Base crate drop weights (percent). Same odds every crate uses.
const RARITY_WEIGHTS := {"legendary": 1.0, "epic": 4.0, "rare": 10.0, "uncommon": 30.0, "common": 55.0}
const RARITY_ORDER := ["legendary", "epic", "rare", "uncommon", "common"]

# Crate item-type per crate kind — see roll_item_for_crate. "all" = the original mixed crate.
const CRATE_TYPE := {"weapon": "weapon", "equipment": "equipment", "medical": "defensive", "all": "all"}

func roll_item() -> Dictionary:
	return roll_item_for_crate("all")

# Rolls a drop for a given crate ("weapon"/"equipment"/"medical", or "all"). Restricts the pool
# to that crate's item type, keeping the same rarity odds — except that if the type has no
# legendary item, the legendary chance is folded into epic (per design). If a rolled rarity
# somehow has no item of the type, it falls to the next lower rarity that does.
func roll_item_for_crate(crate: String) -> Dictionary:
	if crate == "artifact":
		return roll_artifact()
	var type: String = CRATE_TYPE.get(crate, "all")

	var weights := RARITY_WEIGHTS.duplicate()
	if type != "all" and _items_of_type_rarity(type, "legendary").is_empty():
		weights["epic"] += weights["legendary"]
		weights["legendary"] = 0.0

	var total := 0.0
	for r in weights:
		total += weights[r]
	var pick := randf() * total
	var acc := 0.0
	var chosen := "common"
	for r in RARITY_ORDER:
		acc += weights[r]
		if pick <= acc:
			chosen = r
			break

	# From the chosen rarity down, return the first rarity that actually has an item of this type.
	var start := RARITY_ORDER.find(chosen)
	for i in range(start, RARITY_ORDER.size()):
		var pool := _crate_pool(type, RARITY_ORDER[i])
		if not pool.is_empty():
			return pool[randi() % pool.size()]
	# Last resort: anything of the type (or any item at all for "all").
	var any := ITEMS if type == "all" else ITEMS.filter(func(x): return x["type"] == type)
	return any[randi() % any.size()] if not any.is_empty() else {}

func _crate_pool(type: String, rarity: String) -> Array:
	if type == "all":
		return items_of_rarity(rarity)
	return _items_of_type_rarity(type, rarity)

func _items_of_type_rarity(type: String, rarity: String) -> Array:
	return ITEMS.filter(func(i): return i["type"] == type and i["rarity"] == rarity)

# A random item drawn from a single crate's type — used to fill the decorative spin reel so the
# scrolling cards match the crate you're opening. Falls back to any item for "all".
func random_item_for_crate(crate: String) -> Dictionary:
	if crate == "artifact":
		return random_artifact()
	var type: String = CRATE_TYPE.get(crate, "all")
	if type == "all":
		return random_item()
	var pool := ITEMS.filter(func(i): return i["type"] == type)
	return pool[randi() % pool.size()] if not pool.is_empty() else random_item()

func random_item() -> Dictionary:
	return ITEMS[randi() % ITEMS.size()]

func items_of_rarity(rarity: String) -> Array:
	return ITEMS.filter(func(i): return i.rarity == rarity)

# Items of a rarity restricted to a type ("all" = any type). Used by the trade-up reward pool so
# a type-filtered trade (e.g. weapons only) can only yield that type at the next rarity up.
func items_of_type_rarity(type: String, rarity: String) -> Array:
	return _crate_pool(type, rarity)

# Exact-name lookup (e.g. Dennis reading Assault Rifle Blaster's own damage/fire_rate/
# bullet_speed at spawn time, so the two never drift out of sync) — {} if not found.
func get_item_by_name(item_name: String) -> Dictionary:
	for item in ITEMS:
		if item["name"] == item_name:
			return item
	return {}

# "The whole grenade list" (Dennis's every-5-seconds throw) — every item whose name ends in
# "Grenade", not just throwable equipment generally (excludes Grapple Hook, Teleportation
# Bracelet, and weapons like Void Grenade Launcher, whose name doesn't end that way).
func random_grenade() -> Dictionary:
	var pool := ITEMS.filter(func(i): return i["name"].ends_with("Grenade"))
	return pool[randi() % pool.size()]

# ── Artifacts ───────────────────────────────────────────────────────────────────
# Passive items equipped in their own character-screen slot (SaveManager.equipped_artifact), rolled
# from their own crate ("artifact") and NOT tradeable (kept out of ITEMS/the trade-up pool). Each
# carries the effect field(s) its passive uses; only ONE artifact is ever equipped, so the
# artifact_* accessors below read the single equipped artifact with a neutral default. "effect" is
# the human-readable description shown in UI. No equip-point cost for now (see item_points).
const ARTIFACTS := [
	{ "name": "Damage+",       "rarity": "common",    "type": "artifact", "file": "Artifact_Damage_Asset.png",     "effect": "Your base weapon does 1.2x damage",                                        "dmg_mult": 1.2 },
	{ "name": "Defense+",      "rarity": "common",    "type": "artifact", "file": "Artifact_Defense_Asset.png",    "effect": "Your shields have 1.5x more health",                                       "shield_mult": 1.5 },
	{ "name": "Health+",       "rarity": "common",    "type": "artifact", "file": "Artifact_Health_Asset.png",     "effect": "Start with 50 more HP",                                                    "bonus_hp": 50 },
	{ "name": "Regen+",        "rarity": "uncommon",  "type": "artifact", "file": "Artifact_Regen_Asset.png",      "effect": "Health regenerates at 1 HP/sec while enemies are engaged with the player", "regen_per_sec": 1.0 },
	{ "name": "Rate of Fire+", "rarity": "rare",      "type": "artifact", "file": "Artifact_RateOfFire_Asset.png", "effect": "Rate of fire of weapon is 1.5x",                                           "fire_rate_mult": 1.5 },
	{ "name": "Invincible+",   "rarity": "epic",      "type": "artifact", "file": "Artifact_Invincible_Asset.png", "effect": "Every new room, invincible for the first 8 seconds",                       "room_invincible_seconds": 8.0 },
	{ "name": "Lifesteal+",    "rarity": "rare",      "type": "artifact", "file": "Artifact_Lifesteal_Asset.png",  "effect": "Melee attacks that hit an enemy heal 1 HP",                                "melee_lifesteal": 1 },
	{ "name": "Knockback+",    "rarity": "common",    "type": "artifact", "file": "Artifact_Knockback_Asset.png",  "effect": "All melee attacks add 50px of knockback to the enemy",                     "melee_knockback_add": 50.0 },
	{ "name": "Perfect Dash+", "rarity": "rare",      "type": "artifact", "file": "Artifact_PerfectDash_Asset.png","effect": "Every perfect dash replenishes 5 HP",                                      "perfect_dash_heal": 5 },
	# Electric+ used to be a boss relic; it's now a regular uncommon slot-machine artifact.
	{ "name": "Electric+",     "rarity": "uncommon",  "type": "artifact", "file": "Artifact_Electric_Asset.png",   "effect": "Boosts the range of the electric (chain lightning) effect by 2x",           "electric_range_mult": 2.0 },
	{ "name": "Ice+",          "rarity": "uncommon",  "type": "artifact", "file": "Artifact_Ice_Asset.png",        "effect": "Frozen enemies take 10 damage the moment they thaw",                       "ice_thaw_damage": 10 },
	{ "name": "Fire+",         "rarity": "common",    "type": "artifact", "file": "Artifact_Fire_Asset.png",       "effect": "Burn does 2 more damage per second",                                       "burn_bonus_dmg": 2 },
	{ "name": "Elemental+",    "rarity": "common",    "type": "artifact", "file": "Artifact_Elemental_Asset.png",  "effect": "All elemental weapon damage is 1.1x stronger",                             "elemental_dmg_mult": 1.1 },
	# ── Boss relics (boss_relic: true) — NOT in the slot machine; offered as a 2-choice on boss kill.
	{ "name": "Common+",       "rarity": "legendary", "type": "artifact", "file": "Artifact_Common_Asset.png",     "effect": "Common-rarity weapons do 1.5x damage",                                     "common_dmg_mult": 1.5, "boss_relic": true },
	{ "name": "Melee Fire+",   "rarity": "legendary", "type": "artifact", "file": "Artifact_MeleeFire_Asset.png",  "effect": "Melee hits add a burn: 3 HP/sec for 3 seconds",                            "melee_burn_damage": 3, "melee_burn_duration": 3.0, "boss_relic": true },
	{ "name": "Laser Homing+", "rarity": "legendary", "type": "artifact", "file": "Artifact_LaserHoming_Asset.png","effect": "Your lasers home toward enemies within 100px",                             "laser_homing_radius": 100.0, "boss_relic": true },
	{ "name": "Shop+",         "rarity": "legendary", "type": "artifact", "file": "Artifact_Shop_Asset.png",       "effect": "Shop costs are halved for everything",                                     "shop_mult": 0.5, "boss_relic": true },
]

# Slot-machine artifacts exclude boss relics (those only drop from bosses — see boss_relics).
func artifacts_of_rarity(rarity: String) -> Array:
	return ARTIFACTS.filter(func(a): return a["rarity"] == rarity and not a.get("boss_relic", false))

func random_artifact() -> Dictionary:
	var pool := ARTIFACTS.filter(func(a): return not a.get("boss_relic", false))
	return pool[randi() % pool.size()]

# The boss-relic artifacts (offered as a 2-choice when a boss is defeated).
func boss_relics() -> Array:
	return ARTIFACTS.filter(func(a): return a.get("boss_relic", false))

# Two DISTINCT random boss relics for the post-boss choice.
func roll_two_boss_relics() -> Array:
	var pool := boss_relics().duplicate()
	pool.shuffle()
	return pool.slice(0, mini(2, pool.size()))

func get_artifact_by_name(artifact_name: String) -> Dictionary:
	for a in ARTIFACTS:
		if a["name"] == artifact_name:
			return a
	return {}

# Rarity-weighted artifact roll for the artifact crate (same odds as items; every rarity has one).
func roll_artifact() -> Dictionary:
	var total := 0.0
	for r in RARITY_WEIGHTS:
		total += RARITY_WEIGHTS[r]
	var pick := randf() * total
	var acc := 0.0
	var chosen := "common"
	for r in RARITY_ORDER:
		acc += RARITY_WEIGHTS[r]
		if pick <= acc:
			chosen = r
			break
	for i in range(RARITY_ORDER.find(chosen), RARITY_ORDER.size()):
		var pool := artifacts_of_rarity(RARITY_ORDER[i])
		if not pool.is_empty():
			return pool[randi() % pool.size()]
	return random_artifact()

# Multiplier-style effect fields stack MULTIPLICATIVELY (two ×1.2 damage artifacts = ×1.44);
# every other field stacks ADDITIVELY (two +50 HP = +100).
const ARTIFACT_MULT_KEYS := ["dmg_mult", "shield_mult", "fire_rate_mult", "shop_mult", "common_dmg_mult", "electric_range_mult", "elemental_dmg_mult"]

# All artifacts currently affecting the run — capped at MAX_ARTIFACTS (world.gd seeds this with the
# character-screen artifact at run start, then the bar slot machine adds/replaces up to the cap).
# Artifacts stack, so the same effect can appear multiple times.
const MAX_ARTIFACTS := 3
func active_artifacts() -> Array:
	return GameManager.run_artifacts

# Combined value of an effect field across every active artifact (see active_artifacts). Multiplier
# keys multiply from a 1.0 baseline; additive keys sum from 0.0. default_val is returned only when no
# active artifact carries the key (so a lone gameplay site keeps its neutral default).
func artifact_num(key: String, default_val: float) -> float:
	var arts := active_artifacts()
	var is_mult: bool = key in ARTIFACT_MULT_KEYS
	var acc: float = 1.0 if is_mult else 0.0
	var found := false
	for a in arts:
		if a.has(key):
			found = true
			if is_mult:
				acc *= float(a[key])
			else:
				acc += float(a[key])
	return acc if found else default_val
