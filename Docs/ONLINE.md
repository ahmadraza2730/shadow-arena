# Online play

**Play in the browser:** https://shadow-arena-self.vercel.app
**Join link:** `https://shadow-arena-self.vercel.app/?join=CODE` opens straight into a room.

## How to play with friends
1. Menu > **PLAY ONLINE**. Type a name (optional).
2. One player clicks **HOST A MATCH**. The 4-letter room code is shown top-left in the match.
3. Friends open PLAY ONLINE and either click the room in **Open rooms**, type the code and press
   **JOIN**, or open the join link.
4. Each joiner replaces a bot (joiners go to the team with fewer humans, so a 2-player room is you
   vs your friend). When someone leaves, a bot takes their place.

Windows (.exe) and browser players can play together.

**Best host = the .exe.** A browser tab in the background stops running the game, so if a browser
host switches tabs, the match freezes for everyone until they come back. The .exe keeps running.

## How it works
- **Relay:** the free Supabase project `shadow-arena` (Realtime channels). Vercel only serves the
  web page; it cannot run a live game server.
- **Host-authoritative:** the host's game runs the rules, bots and all hit detection. Joiners send
  their position and shots; the host sends snapshots 7-10 times a second.
- **Lag compensation:** a joiner's shot is checked against where everyone was *on the joiner's
  screen* (the host rewinds up to 0.6 s), so if it was on target for you, it hits.
- **Smoothing:** other soldiers are drawn 0.15 s in the past and interpolated between snapshots.
- **Your own movement** is instant (simulated on your machine); the host keeps the final say on
  health, deaths and respawns.

## Limits of the free relay plan
| Limit | Value | What it means |
|---|---|---|
| Messages per second (whole project) | 100 | One match with up to **4 human players** (measured peak: 91/s). Two 2-player matches at once also fit. |
| Messages per month | 2 million | About **14 hours** of 2-player play, or 5 hours of 4-player play, per month |
| Connections | 200 | Not a problem at this size |

When the monthly quota runs out, online play stops until the next month (offline still works).
To grow beyond this: Supabase Pro ($25/month, 500 msg/s, 5M messages) or a dedicated server
(Render / Fly.io) running the host logic headless.

## Settings files
- Relay address and public key: `Game/scripts/net/net_config.gd`
- Rates and limits: `Net.MAX_HUMANS`, `Net.send_rate()` in `Game/scripts/net/net.gd`

## Testing without the internet
`Tools/tests/run_mp_test.sh <path-to-godot> [delay-ms]` starts a local stand-in relay
(`Tools/tests/mock_relay.py`, needs `pip install websockets`) and runs a host and a joiner that
check: room list, admission, lag-compensated kills, hit markers, kill feed, ping, death/respawn
sync and a bot replacing a player who leaves.
