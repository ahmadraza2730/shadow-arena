# Step 15 - packaging a Windows build

The export preset is already in `Game/export_presets.cfg`.

1. In Godot: Editor > Manage Export Templates > Download and Install
   (about 1 GB, one time).
2. Project > Export > "Windows Desktop" > Export Project.
3. Save as `E:\ShadowArena\Builds\ShadowArena.exe` ("Export With Debug" off).
4. Run the .exe. `Builds/` is ignored by Git; upload builds to GitHub
   Releases or itch.io instead.

If weapons are missing in the build: Project > Export > Resources tab >
"Filters to export non-resource files" must contain `*.json`.

Before publishing: all weapon names are already fictional; keep it that
way, and do not ship any ripped game assets.


## Web build (Vercel)
1. Export: `godot --headless --path Game --export-release "Web" ../web/index.html`
   (needs the web export templates, part of the same template download).
2. Commit and push the `web/` folder. The Vercel project `shadow-arena` (root directory `web`)
   redeploys automatically on every push to `main`.
