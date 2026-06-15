---
description: Launch the Parsec Godot project in the editor or run a specific scene
---

# Run Godot — Parsec Project

## Godot Executable

```
C:\Users\ryanv\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe
```

## Project Path

```
C:\Users\ryanv\OneDrive\Desktop\AI Projects\Step Rogue\parsec
```

## Open the Editor

```powershell
& "C:\Users\ryanv\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe" --path "C:\Users\ryanv\OneDrive\Desktop\AI Projects\Step Rogue\parsec" --editor
```

## Run a Specific Scene

```powershell
& "C:\Users\ryanv\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe" --path "C:\Users\ryanv\OneDrive\Desktop\AI Projects\Step Rogue\parsec" --scene "res://scenes/menu/menu.tscn"
```

Replace `menu/menu.tscn` with any scene path under `res://scenes/`.

## Key Scenes

| Scene | Path |
|-------|------|
| Main Menu | `res://scenes/menu/menu.tscn` |
| Open Crate | `res://scenes/open_crate/open_crate.tscn` |
| Inventory | `res://scenes/inventory/inventory.tscn` |
| Trade Up | `res://scenes/trade_up/trade_up.tscn` |
| Sync Steps | `res://scenes/sync_steps/sync_steps.tscn` |
| Game (world) | `res://world.tscn` |

## Notes

- Run with `run_in_background: true` so the process stays open while you work
- Check the output file for GDScript errors after running
- After editing `.gd` or `.tscn` files externally, Godot picks up changes on next run (no reload needed when running via CLI)
