# SHADOW ARENA

A 4v4 Team Deathmatch shooter (first/third person) set in an abandoned
Pakistani industrial area. Solo student project, zero budget, free assets only.

| | |
|---|---|
| Engine | Godot 4.7 (Mobile renderer) |
| Language | GDScript |
| Mode | 4v4 TDM - first to 40 kills or 10 minutes |
| Phase 1 | Offline vs AI bots |
| Phase 2 | Online multiplayer (server-authoritative) |
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
  Docs/        Design notes, roadmap, per-step guides
  Builds/      Exported builds (ignored by Git)
```

## Run it
Open Godot 4.7, click Import, pick `Game/project.godot`, press F5.

## Roadmap

See [Docs/ROADMAP.md](Docs/ROADMAP.md).
