# Weapon Overhaul — structural design

Companion to `Weapon Overhaul Specs.tsv` (per-weapon behaviour). This file is the system design:
loadout, fusion, elemental boosts. Nothing here is implemented yet.

## Loadout

- The player brings a **primary** and an optional **secondary** weapon into a run.
- **Both cost equipment points**, against the existing 10-point budget
  (`EQUIPMENT_POINT_BUDGET`, costed by rarity via `RARITY_COST`).
- A run can be played with the primary alone — the secondary is optional.

## Fusion

- Combined weapons **cannot spawn from crates**. The only way to get one is to fuse.
- Fusing happens **at the shop**, costs **100 credits**.
- Fusing consumes **both** component weapons.
- **Only one fusion per run.**
- If the player never fuses, the secondary weapon is **not** lost — it comes back out of the run
  intact. (Contrast with the normal run-loss rule.)
- Only **tier 1 and tier 2** weapons appear in the combination matrices, so tier 3+ never fuses.

### Combined-weapon rarity

Derived from the shading in the Combinations tabs, and it reduces to one rule:

| Components | Result |
|---|---|
| common + common | **uncommon** |
| anything + uncommon | **rare** |

The uncommon "rare-makers" are Beam Sword, Metallic Whip, Grapple Spear (melee) and
Beam Rifle, Wave Ray Gun, Boomerang (ranged). This reproduces all 37 shaded cells exactly.

## Elemental boosts

Six boosts (from the Elemental Boosts tab): Ice, Fire, Electric (common); Void, Kinetic,
Stun (uncommon).

- Boosts come from their **own crate type** — an elemental crate, alongside weapon/equipment/medical.
- Applied **in the fuse option at the shop for 50 credits** (separate from the 100-credit weapon fusion).
- Before a run the player loads boosts into a **catalog**. When they pay to apply one in-run, the
  game picks **one at random from that catalog**, weighted by the normal rarity odds — the player
  does not choose which.
- A boost consumed in a run follows the **existing run-loss rule**: lost unless the final boss is
  beaten (see `SaveManager.resolve_run_loss` / hedge tokens).

### How many boosts a weapon can hold

| Weapon rarity | Boost slots |
|---|---|
| common | 2 |
| uncommon | 2 |
| rare | **1** |
| epic | ? not specified |
| legendary | ? not specified |

Note this is deliberately inverted — commons and uncommons are more customisable than rares.
Combined weapons are uncommon or rare, so they inherit those limits: an uncommon combo takes 2
boosts, a rare combo takes 1.

## Roster changes

Cut outright: **Electric Baton, Ice Staff, Fire Blaster, Double Pistol Blasters, Large Warhammer**
(Dual Laser Blasters and Dual Hammers replace the last two as combinations).

Kept: **Assault Rifle Blaster**, as a rare item, despite not appearing in the new weapon list.

Also cut from the new list: **Singularity Cannon** (dropped during spec review).

Existing weapon changed: **War Hammer** is redesigned from a 128px directional cone into a
ground-slam pulse ring (6 dmg, 300px). This propagates into its seven combinations.

## Open decisions

1. War Hammer — does a direct swing hit remain, or is the ring the only damage?
2. Boost slots for epic and legendary weapons.
3. Catalog size — how many boosts can the player load before a run?
4. Nova Gloves — one hit per 0.6s, or two staggered hits?
5. Scatter Blaster needs an explicit range/falloff, or "longer range" on Ranged Scatter
   Blaster is meaningless (bullets currently travel until they hit a wall).
6. Pulse Hammer — ring range and swing rate.
7. ~20 smaller per-weapon numbers, marked `[TBD]` / `[Q:]` in the specs TSV.
