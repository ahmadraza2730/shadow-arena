# SHADOW ARENA

**Play now in your browser: https://shadow-arena-self.vercel.app**

A 4v4 Team Deathmatch shooter (first/third person) set in an abandoned
Pakistani industrial area. Solo student project, zero budget, free assets only.

| | |
|---|---|
| Engine | Godot 4.7 (Mobile renderer) |
| Language | GDScript |
| Mode | 4v4 TDM - first to 40 kills or 10 minutes |
| Phase 1 | Offline vs AI bots |
| Online | Host or join by room code, browser and Windows together |
| Target | 60 FPS on a low-end laptop |

## Repo layout

```
ShadowArena/
  Game/        Godot project (open Game/project.godot)
    scenes/      .tscn scenes
    scripts/     GDScript, grouped by system
    data/        weapon/attachment resources (.tres)
    assets/      our models, textures, audio, vfx, materials
    third_party/ imported free asset packs
  MapSource/   Python generators: map, textures, music
  web/         Exported browser build (served by Vercel)
  Tools/tests/ Local relay + automated multiplayer test
  Docs/        Design notes, roadmap, guides
  Builds/      Exported builds (ignored by Git)
```

## Run it
Open Godot 4.7, click Import, pick `Game/project.godot`, press F5.

## Docs
- [Game guide](Docs/GAME_GUIDE.md): controls, rules, weapons, code map, what was tested
- [Map](Docs/MAP.md): top-down diagram and dimensions
- [Graphics](Docs/GRAPHICS.md): quality presets, 60 FPS plan, free assets
- [Packaging](Docs/PACKAGING.md): making the Windows build
- [Roadmap](Docs/ROADMAP.md): status of every step
- [Online play](Docs/ONLINE.md): hosting, joining, how the netcode works, free-plan limits
- [Credits](Docs/CREDITS.md): third-party assets and licences

## Status
Playable offline (4v4 vs bots) and online (up to 4 humans + bots), on
Windows and in the browser. CC0 gun models, an animated soldier rig,
recorded gunshots, scanned textures, original music, aim assist.
