# Step 1 - Project setup and version control

## Tools
- Godot 4.7.2 stable, Windows 64-bit, standard build (not .NET).
  It is a single .exe inside a zip: no installer, no account.
  Keep it at `E:\Godot\`.
- Git for Windows (already installed on this PC).

## Open the project
1. Run `E:\Godot\Godot_v4.7.2-stable_win64.exe`.
2. Project Manager > Import > browse to `E:\ShadowArena\Game\project.godot` > Import & Edit.
3. Press F5 (Run Project).

## Test
- A window opens showing a gray floor, one crate, and sky. No red errors in
  the Output panel.
- `git status` lists nothing under `Game/.godot/`.

## Commit after any change (PowerShell)
```
cd E:\ShadowArena
git add .
git commit -m "Describe the change"
```

## Connect to the GitHub repo (once)
```
git remote add origin https://github.com/<your-username>/<repo-name>.git
git push -u origin main
```
If GitHub created the repo with a README, run this once before pushing:
`git pull origin main --allow-unrelated-histories`
