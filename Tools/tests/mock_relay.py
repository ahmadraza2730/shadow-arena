#!/usr/bin/env python3
"""A local stand-in for Supabase Realtime, for automated multiplayer tests.

Implements the parts of the Phoenix / Realtime protocol (v1.0.0 JSON) the
game uses: phx_join, phx_leave, heartbeat, broadcast (self=false) and
presence (track, presence_state, presence_diff), with an optional one-way
delay to imitate internet latency. It also counts messages the way
Supabase does (every message sent by or delivered to a client) and prints
the peak per second, to check the free plan's 100/s budget.

Run:  python3 Tools/tests/mock_relay.py --port 4000 --delay-ms 60
"""
import argparse, asyncio, json, time, uuid
import websockets

subs = {}        # topic -> {ws: {"join_ref", "key", "presence"}}
presence = {}    # topic -> {key: meta}
counter = {"sec": 0, "count": 0, "peak": 0, "total": 0}
DELAY = 0.0


def count(n=1):
    now = int(time.time())
    if now != counter["sec"]:
        counter["peak"] = max(counter["peak"], counter["count"])
        if counter["count"]:
            print(f"[relay] {counter['count']} msgs/s (peak {counter['peak']})", flush=True)
        counter["sec"], counter["count"] = now, 0
    counter["count"] += n
    counter["total"] += n


async def deliver(ws, msg):
    count()
    if DELAY:
        await asyncio.sleep(DELAY)
    try:
        await ws.send(json.dumps(msg))
    except Exception:
        pass


def send(ws, msg):
    asyncio.get_running_loop().create_task(deliver(ws, msg))


def diff(topic, joins, leaves):
    for other in list(subs.get(topic, {})):
        if subs[topic][other]["presence"]:
            send(other, {"topic": topic, "event": "presence_diff",
                         "payload": {"joins": joins, "leaves": leaves}, "ref": None})


def drop(ws, topic):
    info = subs.get(topic, {}).pop(ws, None)
    if info and info["key"] and info["key"] in presence.get(topic, {}):
        meta = presence[topic].pop(info["key"])
        diff(topic, {}, {info["key"]: {"metas": [meta]}})


async def handler(ws):
    try:
        async for raw in ws:
            count()
            m = json.loads(raw)
            topic, event, payload = m.get("topic"), m.get("event"), m.get("payload") or {}
            ref, join_ref = m.get("ref"), m.get("join_ref")
            reply = {"topic": topic, "event": "phx_reply", "payload": {"status": "ok", "response": {}},
                     "ref": ref, "join_ref": join_ref}
            if event == "heartbeat":
                send(ws, reply)
            elif event == "phx_join":
                old = subs.get(topic, {}).get(ws)
                if old:
                    # Like Phoenix: a second join of the same topic closes the first one.
                    send(ws, {"topic": topic, "event": "phx_close", "payload": {}, "ref": old["join_ref"],
                              "join_ref": old["join_ref"]})
                    drop(ws, topic)
                cfg = payload.get("config", {})
                pres = cfg.get("presence", {})
                enabled = pres.get("enabled", False) or bool(pres.get("key"))
                subs.setdefault(topic, {})[ws] = {"join_ref": join_ref, "key": pres.get("key") or str(uuid.uuid4()),
                                                  "presence": enabled}
                send(ws, reply)
                if enabled:
                    state = {k: {"metas": [v]} for k, v in presence.get(topic, {}).items()}
                    send(ws, {"topic": topic, "event": "presence_state", "payload": state, "ref": None})
            elif event == "phx_leave":
                drop(ws, topic)
                send(ws, reply)
            elif event == "broadcast":
                if ws not in subs.get(topic, {}):
                    continue
                for other in list(subs.get(topic, {})):
                    if other is not ws:
                        send(other, {"topic": topic, "event": "broadcast", "payload": payload, "ref": None})
            elif event == "presence":
                info = subs.get(topic, {}).get(ws)
                if info and payload.get("event") == "track":
                    meta = dict(payload.get("payload", {}))
                    meta["phx_ref"] = uuid.uuid4().hex[:12]
                    old = presence.setdefault(topic, {}).get(info["key"])
                    presence[topic][info["key"]] = meta
                    diff(topic, {info["key"]: {"metas": [meta]}}, {info["key"]: {"metas": [old]}} if old else {})
                send(ws, reply)
    finally:
        for topic in list(subs):
            if ws in subs[topic]:
                drop(ws, topic)


async def main(port):
    async with websockets.serve(handler, "127.0.0.1", port, max_size=2 ** 22):
        print(f"[relay] listening on ws://127.0.0.1:{port} (delay {DELAY * 1000:.0f} ms)", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=4000)
    ap.add_argument("--delay-ms", type=float, default=0)
    a = ap.parse_args()
    DELAY = a.delay_ms / 1000.0
    asyncio.run(main(a.port))
