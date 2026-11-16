#!/usr/bin/env bash
# Two-player online test against a local stand-in relay (no internet needed).
# Usage: Tools/tests/run_mp_test.sh [path-to-godot] [one-way-delay-ms]
# Needs: python3 with `pip install websockets`.
set -e
GODOT=${1:-godot}
DELAY=${2:-60}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="$ROOT/Game"
mkdir -p "$GAME/tests_tmp"
for n in host client; do
  cp "$ROOT/Tools/tests/mp_test_$n.gd" "$GAME/tests_tmp/mp_test_$n.gd"
  printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://tests_tmp/mp_test_%s.gd" id="1"]\n\n[node name="T" type="Node"]\nscript = ExtResource("1")\n' $n > "$GAME/tests_tmp/mp_test_$n.tscn"
done
rm -f /tmp/sa_room.txt /tmp/sa_ready.txt
python3 "$ROOT/Tools/tests/mock_relay.py" --port 4000 --delay-ms "$DELAY" > /tmp/sa_relay.log 2>&1 &
RELAY=$!
sleep 1
RELAY_ARG="--relay=ws://127.0.0.1:4000/socket/websocket"
"$GODOT" --headless --path "$GAME" res://tests_tmp/mp_test_host.tscn -- $RELAY_ARG > /tmp/sa_host.log 2>&1 &
HOST=$!
"$GODOT" --headless --path "$GAME" res://tests_tmp/mp_test_client.tscn -- $RELAY_ARG > /tmp/sa_client.log 2>&1 || true
wait $HOST || true
kill $RELAY 2>/dev/null || true
rm -rf "$GAME/tests_tmp"
grep -hE "PASS|FAIL" /tmp/sa_host.log /tmp/sa_client.log
grep -qE "(HOST|JOIN) FAIL " /tmp/sa_host.log /tmp/sa_client.log && exit 1 || echo "ALL PASSED"
