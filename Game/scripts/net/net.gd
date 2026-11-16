extends Node
## Net (autoload)
##
## Online play over the Supabase Realtime relay. One player HOSTS a match:
## their game runs the real simulation (rules, bots, hit detection) and
## sends snapshots to everyone. Other players JOIN with a room code: they
## move their own soldier, send their position and shots to the host, and
## draw everyone else from the host's snapshots.
##
## Channels (all prefixed with the protocol version):
##   <p>_lobby              presence: one entry per open room (the server list)
##   <p>_room_<CODE>        host -> everyone: snapshots; presence = who is in the room
##   <p>_room_<CODE>_<id>   one per joiner, joiner -> host: input and shots
##
## A separate uplink channel per joiner means a joiner's packets reach only
## the host, which keeps the message count inside the free plan's
## 100 messages / second budget (see MAX_HUMANS and send_rate()).

signal status_changed(text: String)
signal rooms_changed
signal room_joined(code: String)
signal room_left(reason: String)
signal peer_joined(peer_id: String, meta: Dictionary)
signal peer_left(peer_id: String)
signal snapshot_received(snapshot: Dictionary)
signal uplink_received(peer_id: String, event: String, data: Dictionary)

enum Role { OFFLINE, HOST, CLIENT }

## Humans per match on the free relay plan (the rest of the 8 slots are bots).
const MAX_HUMANS := 4
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var role: Role = Role.OFFLINE
var my_id := ""
var room_code := ""
var host_id := ""
var status := "Offline"
## code -> {"code", "host", "humans", "max", "state"}
var rooms: Dictionary = {}
## peer_id -> {"name": String} for everyone in my room except me.
var peers: Dictionary = {}

var _client: RealtimeClient
var _want_lobby := false
var _lobby_topic := ""
var _room_topic := ""
var _uplink_topic := ""
var _host_uplinks: Dictionary = {}      # peer_id -> topic (host side)


## Browser tabs in the background stop running the game loop, which would
## stop our 25-second heartbeat and get us dropped by the relay. This
## wraps the page's WebSocket so a plain JavaScript timer (which keeps
## running in background tabs) sends the heartbeat instead.
const WEB_KEEPALIVE_JS := """
(function () {
  if (window.__saKeepAlive) return;
  window.__saKeepAlive = true;
  var Native = window.WebSocket;
  function Patched(url, protocols) {
    var ws = protocols === undefined ? new Native(url) : new Native(url, protocols);
    if (String(url).indexOf('/websocket') >= 0) {
      var ref = 900000;
      var timer = setInterval(function () {
        if (ws.readyState === 1) {
          ws.send(JSON.stringify({topic: 'phoenix', event: 'heartbeat', payload: {}, ref: String(ref++)}));
        } else if (ws.readyState > 1) {
          clearInterval(timer);
        }
      }, 20000);
    }
    return ws;
  }
  Patched.prototype = Native.prototype;
  Patched.CONNECTING = 0; Patched.OPEN = 1; Patched.CLOSING = 2; Patched.CLOSED = 3;
  window.WebSocket = Patched;
})();
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_KEEPALIVE_JS, true)
	my_id = "%08x" % (randi() & 0x7fffffff)
	_client = RealtimeClient.new()
	add_child(_client)
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(_on_disconnected)
	_client.channel_error.connect(_on_channel_error)
	_client.broadcast_received.connect(_on_broadcast)
	_client.presence_state.connect(_on_presence_state)
	_client.presence_diff.connect(_on_presence_diff)
	_lobby_topic = NetConfig.PROTOCOL + "_lobby"


# ------------------------------------------------------------------ state
func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func player_name() -> String:
	var name := str(Game.settings.get("player_name", "")).strip_edges()
	return name if name != "" else "Player-" + my_id.substr(0, 4).to_upper()


func is_connected_to_relay() -> bool:
	return _client.is_open


func human_count() -> int:
	# A joiner's peer list holds the other joiners but not the host.
	return peers.size() + (2 if role == Role.CLIENT else 1)


## Snapshots / uplink packets per second. Drops a little with 4 humans so
## (snapshots + uplinks) stay under the relay's 100 messages per second.
func send_rate() -> float:
	return 10.0 if human_count() <= 3 else 7.0


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


# ------------------------------------------------------------------ lobby
## Connects (if needed) and starts listening to the server list.
func open_lobby() -> void:
	_want_lobby = true
	if _client.is_connecting():
		return
	if not _client.is_open:
		_set_status("Connecting...")
		_client.open(NetConfig.socket_url())
	else:
		_client.join(_lobby_topic, my_id)     # no-op if already joined / joining


func close_lobby() -> void:
	_want_lobby = false
	if role == Role.OFFLINE:
		_client.close()
		rooms.clear()
		_set_status("Offline")


# ------------------------------------------------------------ host / join
## Creates a room and becomes its host. The match scene is loaded by the caller.
func host_room() -> String:
	if role != Role.OFFLINE:
		return room_code
	open_lobby()
	room_code = ""
	for i in 4:
		room_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	role = Role.HOST
	host_id = my_id
	peers.clear()
	_host_uplinks.clear()
	_room_topic = "%s_room_%s" % [NetConfig.PROTOCOL, room_code]
	_client.join(_room_topic, my_id)
	_client.track(_room_topic, {"id": my_id, "name": player_name(), "host": true})
	update_room_listing("playing")
	_set_status("Hosting room %s" % room_code)
	room_joined.emit(room_code)
	return room_code


## Re-publishes this room in the server list (host only).
func update_room_listing(state: String) -> void:
	if role != Role.HOST:
		return
	_client.track(_lobby_topic, {"code": room_code, "host": player_name(),
			"humans": human_count(), "max": MAX_HUMANS, "state": state})


## Joins someone else's room by code. The match scene waits for the
## host's first snapshot.
func join_room(code: String) -> void:
	if role != Role.OFFLINE:
		return
	open_lobby()
	room_code = code.strip_edges().to_upper()
	role = Role.CLIENT
	host_id = ""
	peers.clear()
	_room_topic = "%s_room_%s" % [NetConfig.PROTOCOL, room_code]
	_uplink_topic = "%s_%s" % [_room_topic, my_id]
	_client.join(_room_topic, my_id)
	_client.join(_uplink_topic)
	_client.track(_room_topic, {"id": my_id, "name": player_name(), "host": false})
	_set_status("Joining room %s..." % room_code)
	room_joined.emit(room_code)


## Leaves the current room (host or joiner) and goes back to offline.
func leave_room(reason: String = "") -> void:
	if role == Role.OFFLINE:
		return
	for topic: String in _host_uplinks.values():
		_client.leave(topic)
	_host_uplinks.clear()
	if _uplink_topic != "":
		_client.leave(_uplink_topic)
	if _room_topic != "":
		_client.leave(_room_topic)
	if role == Role.HOST:
		# Publishing an empty entry removes our room from the server list.
		_client.track(_lobby_topic, {"closed": true})
	role = Role.OFFLINE
	_room_topic = ""
	_uplink_topic = ""
	room_code = ""
	host_id = ""
	peers.clear()
	_set_status("Offline" if not _client.is_open else "Connected")
	room_left.emit(reason)


# ---------------------------------------------------------------- sending
## Host: snapshot to everyone in the room.
func send_snapshot(snapshot: Dictionary) -> void:
	if role == Role.HOST and not peers.is_empty():
		_client.broadcast(_room_topic, "s", snapshot)


## Joiner: a packet to the host only.
func send_uplink(event: String, data: Dictionary) -> void:
	if role == Role.CLIENT:
		_client.broadcast(_uplink_topic, event, data)


# --------------------------------------------------------------- handlers
func _on_connected() -> void:
	_set_status("Connected")
	if _want_lobby and not _client.is_joined(_lobby_topic):
		_client.join(_lobby_topic, my_id)


func _on_disconnected(reason: String) -> void:
	rooms.clear()
	rooms_changed.emit()
	_set_status("Offline: " + reason)
	if role != Role.OFFLINE:
		var was := role
		role = Role.OFFLINE
		peers.clear()
		_host_uplinks.clear()
		room_left.emit("Connection lost: " + reason if was == Role.CLIENT else "Connection lost")


func _on_channel_error(topic: String, reason: String) -> void:
	push_warning("Realtime channel %s: %s" % [topic, reason])
	if topic == _room_topic and role == Role.CLIENT:
		leave_room("Could not join the room: " + reason)


func _on_broadcast(topic: String, event: String, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	if topic == _room_topic and role == Role.CLIENT and event == "s":
		if host_id == "":
			_set_status("In room %s" % room_code)
		host_id = str(payload.get("hid", host_id))
		snapshot_received.emit(payload)
	elif role == Role.HOST:
		for peer_id: String in _host_uplinks:
			if _host_uplinks[peer_id] == topic:
				uplink_received.emit(peer_id, event, payload)
				return


func _on_presence_state(topic: String, state: Dictionary) -> void:
	_apply_presence(topic, state, {})


func _on_presence_diff(topic: String, joins: Dictionary, leaves: Dictionary) -> void:
	_apply_presence(topic, joins, leaves)


func _apply_presence(topic: String, joins: Dictionary, leaves: Dictionary) -> void:
	# A key that both leaves and joins in one diff just updated its data.
	var real_leaves := {}
	for key: String in leaves:
		if not joins.has(key):
			real_leaves[key] = leaves[key]
	if topic == _lobby_topic:
		for key: String in leaves:
			for meta in _metas(leaves[key]):
				rooms.erase(str(meta.get("code", "")))
		for key: String in joins:
			for meta in _metas(joins[key]):
				if meta.has("code") and key != my_id:
					rooms[str(meta["code"])] = meta
		rooms_changed.emit()
	elif topic == _room_topic:
		for key: String in real_leaves:
			if key == my_id:
				continue
			if role == Role.CLIENT and (key == host_id or _is_host_meta(real_leaves[key])):
				leave_room("The host left the match")
				return
			if peers.has(key):
				peers.erase(key)
				if role == Role.HOST and _host_uplinks.has(key):
					_client.leave(_host_uplinks[key])
					_host_uplinks.erase(key)
					update_room_listing("playing")
				peer_left.emit(key)
		for key: String in joins:
			if key == my_id:
				continue
			var metas := _metas(joins[key])
			var meta: Dictionary = metas[0] if not metas.is_empty() else {}
			if bool(meta.get("host", false)):
				host_id = key
				continue
			if not peers.has(key):
				peers[key] = {"name": str(meta.get("name", "Player"))}
				if role == Role.HOST:
					var uplink := "%s_%s" % [_room_topic, key]
					_host_uplinks[key] = uplink
					_client.join(uplink)
					update_room_listing("playing")
				peer_joined.emit(key, meta)


func _metas(entry: Variant) -> Array:
	if entry is Dictionary and entry.get("metas") is Array:
		return entry["metas"]
	return []


func _is_host_meta(entry: Variant) -> bool:
	for meta in _metas(entry):
		if bool(meta.get("host", false)):
			return true
	return false
