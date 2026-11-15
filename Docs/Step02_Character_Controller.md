# Step 2 - Character controller

## Files
- `Game/scripts/core/input_setup.gd` - autoload that registers all key/mouse actions.
- `Game/scripts/player/player_controller.gd` - movement, look, crouch, jump, ADS, FP/TP camera.
- `Game/scenes/player.tscn` - the player scene (capsule, head, spring arm, camera).
- `Game/scenes/main.tscn` - test yard: crates, a ramp to a platform, a low tunnel.

## Controls
| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint | Shift (while moving forward) |
| Crouch | Ctrl or C (hold) |
| Jump | Space |
| Aim down sights | Right mouse (hold) |
| First / third person | V |
| Free the cursor | Esc (click the window to grab it again) |

## Tuning
Select the Player node in `player.tscn`; every value (speeds, jump height,
FOV, sensitivity, camera distance) is in the Inspector under Movement, Look,
Stance and Camera.

## Test checklist
- [ ] WASD moves, mouse looks, pitch stops before flipping over.
- [ ] Shift + W is faster and widens the view slightly.
- [ ] Space jumps about 1.1 m; you can jump onto the 1 m crate, not the 2 m one.
- [ ] Ctrl lets you enter the low tunnel; releasing Ctrl inside keeps you crouched.
- [ ] Right mouse zooms in and slows movement and mouse speed.
- [ ] V switches to an over-the-shoulder camera that does not clip through walls.
- [ ] You can walk up the ramp onto the platform.
