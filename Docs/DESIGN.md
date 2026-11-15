# Shadow Arena - Design Summary

## Game mode
- 4v4 Team Deathmatch. First team to 40 kills, or highest score at 10:00.
- Instant respawn at a spawn point with no enemy nearby / in line of sight.
- Phase 1 offline with bots. Phase 2 online, only after Phase 1 is finished.

## Map
- One arena, about 120 x 120 m.
- Setting: abandoned Pakistani industrial area (brick kiln yard, textile
  godowns, truck workshop). Chosen over the fort courtyard because boxy
  warehouses and containers are easy to gray-box, match the TDM-warehouse
  feel, and are well covered by free assets (Poly Haven, Fab/Quixel).
  A fort needs custom Mughal-style architecture that free libraries lack.
- Two protected spawns at opposite ends, open centre with one sniper lane,
  close-quarter buildings and alleys on both flanks, rooftops and 2nd floors
  by stairs/ramps, cover every 5-8 m, at least 3 routes between spawns.
- Full dimensioned layout comes in Step 8.

## Weapons (generic names in the public build)
- AR: M416-style, AKM-style
- Sniper: M24-style (bolt), AWM-style (one-shot body)
- SMG: UMP-style, Vector-style
- Shotgun: S12K-style
- Pistol: P18C-style, Desert Eagle-style
- Data-driven: one Resource file (.tres) per weapon in `Game/data/` (Step 4).

## Engine choices
- Godot 4.7, GDScript. No account, no installer, runs on integrated graphics.
- Renderer: Mobile (Vulkan). If the GPU struggles, switch to Compatibility
  (OpenGL) in Project Settings > Rendering > Renderer.
- Lighting: baked LightmapGI + one shadowed sun. No SDFGI / volumetric fog
  (Forward+ only, too heavy for this PC); dust is done with particles.

## Naming and folder rules (inside Game/)
- Files and folders: snake_case (`player_controller.gd`, `main.tscn`).
- Classes: PascalCase via `class_name`. One class per script.
- Our content in `scenes/`, `scripts/`, `data/`, `assets/`. Imported packs
  stay in `third_party/` so they never mix with our files.
