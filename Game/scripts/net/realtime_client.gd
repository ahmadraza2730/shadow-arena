class_name RealtimeClient
extends Node
## A minimal Supabase Realtime client (Phoenix channels, protocol 1.0.0,
## JSON text frames) built on Godot's WebSocketPeer, so it works the same
## in the Windows build and in the browser.
##
## Supports what the game needs: joining public channels, broadcast send
## and receive, and presence (track / state / diff). Docs:
## https://supabase.com/docs/guides/realtime/protocol

signal connected
signal disconnected(reason: String)
signal channel_joined(topic: String)
signal channel_error(topic: String, reason: String)
signal broadcast_received(topic: String, event: String, payload: Variant)
signal presence_state(topic: String, state: Dictionary)
signal presence_diff(topic: String, joins: Dictionary, leaves: Dictionary)

const HEARTBEAT_INTERVAL := 25.0
const CONNECT_TIMEOUT := 10.0

var url := ""
var is_open := false

var _socket := WebSocketPeer.new()
var _ref := 0
var _heartbeat_left := HEARTBEAT_INTERVAL
var _connecting := false
var _connect_time := 0.0
## topic -> {"join_ref": String, "joined": bool, "config": Dictionary, "track": Variant}
var _channels: Dictionary = {}
## Messages queued per topic until that channel's join is confirmed.
var _pending: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_socket.inbound_buffer_size = 1 << 20
	_socket.outbound_buffer_size = 1 << 20


## Opens the socket. `socket_url` is the full wss:// URL including ?apikey=.
func open(socket_url: String) -> void:
	close()
	url = socket_url
	var err := _socket.connect_to_url(url)
	if err != OK:
		disconnected.emit("Could not start connection (error %d)" % err)
		return
	_connecting = true
	_connect_time = 0.0


func is_connecting() -> bool:
	return _connecting


func close() -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	_channels.clear()
	_pending.clear()
	is_open = false
	_connecting = false


## Joins a channel. Topic is given without the "realtime:" prefix.
## presence_key: "" = presence off, otherwise this client's presence key.
func join(topic: String, presence_key: String = "") -> void:
	var full := "realtime:" + topic
	# Joining twice would make the server close the first join; once is enough.
	if _channels.has(full):
		return
	_ref += 1
	var join_ref := str(_ref)
	var config := {
		"broadcast": {"ack": false, "self": false},
		"presence": {"enabled": presence_key != "", "key": presence_key},
		"private": false,
	}
	_channels[full] = {"join_ref": join_ref, "joined": false, "config": config, "track": null}
	_pending[full] = []
	if is_open:
		_send_join(full)


func leave(topic: String) -> void:
	var full := "realtime:" + topic
	if not _channels.has(full):
		return
	if is_open:
		_push(full, "phx_leave", {})
	_channels.erase(full)
	_pending.erase(full)


func is_joined(topic: String) -> bool:
	var full := "realtime:" + topic
	return _channels.has(full) and bool(_channels[full]["joined"])


## Sends a broadcast event to everyone else on the channel.
func broadcast(topic: String, event: String, payload: Variant) -> void:
	_push_or_queue("realtime:" + topic, "broadcast",
			{"type": "broadcast", "event": event, "payload": payload})


## Publishes (or updates) this client's presence data on a channel.
func track(topic: String, data: Dictionary) -> void:
	var full := "realtime:" + topic
	if _channels.has(full):
		_channels[full]["track"] = data
	_push_or_queue(full, "presence", {"type": "presence", "event": "track", "payload": data})


func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if _connecting:
		_connect_time += delta
		if state == WebSocketPeer.STATE_OPEN:
			_connecting = false
			is_open = true
			_heartbeat_left = HEARTBEAT_INTERVAL
			connected.emit()
			for topic: String in _channels:
				_send_join(topic)
		elif state == WebSocketPeer.STATE_CLOSED or _connect_time > CONNECT_TIMEOUT:
			_connecting = false
			var reason := _socket.get_close_reason()
			if reason == "":
				reason = "Could not reach the server (check your internet connection)"
			disconnected.emit(reason)
			return
	if not is_open:
		return
	if state == WebSocketPeer.STATE_CLOSED:
		is_open = false
		var reason := _socket.get_close_reason()
		disconnected.emit(reason if reason != "" else "Connection lost")
		return
	while _socket.get_available_packet_count() > 0:
		var text := _socket.get_packet().get_string_from_utf8()
		var message: Variant = JSON.parse_string(text)
		if message is Dictionary:
			_handle(message)
	_heartbeat_left -= delta
	if _heartbeat_left <= 0.0:
		_heartbeat_left = HEARTBEAT_INTERVAL
		_ref += 1
		_send({"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": str(_ref)})


func _send_join(full: String) -> void:
	var channel: Dictionary = _channels[full]
	_send({"topic": full, "event": "phx_join", "payload": {"config": channel["config"]},
			"ref": channel["join_ref"], "join_ref": channel["join_ref"]})


func _push_or_queue(full: String, event: String, payload: Dictionary) -> void:
	if _channels.has(full) and bool(_channels[full]["joined"]) and is_open:
		_push(full, event, payload)
	elif _pending.has(full):
		# Presence: only the latest track matters.
		if event == "presence":
			_pending[full] = (_pending[full] as Array).filter(
					func(m: Array) -> bool: return m[0] != "presence")
		(_pending[full] as Array).append([event, payload])


func _push(full: String, event: String, payload: Dictionary) -> void:
	_ref += 1
	var join_ref: Variant = _channels[full]["join_ref"] if _channels.has(full) else null
	_send({"topic": full, "event": event, "payload": payload, "ref": str(_ref), "join_ref": join_ref})


func _send(message: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


func _handle(message: Dictionary) -> void:
	var topic: String = str(message.get("topic", ""))
	var event: String = str(message.get("event", ""))
	var payload: Variant = message.get("payload", {})
	var short := topic.trim_prefix("realtime:")
	match event:
		"phx_reply":
			if not _channels.has(topic) or not (payload is Dictionary):
				return
			var channel: Dictionary = _channels[topic]
			if str(message.get("ref", "")) != channel["join_ref"] or bool(channel["joined"]):
				return
			if payload.get("status", "") == "ok":
				channel["joined"] = true
				channel_joined.emit(short)
				for queued: Array in _pending.get(topic, []):
					_push(topic, queued[0], queued[1])
				_pending[topic] = []
			else:
				var response: Variant = payload.get("response", {})
				var reason := str(response.get("reason", "join refused")) if response is Dictionary else "join refused"
				channel_error.emit(short, reason)
		"broadcast":
			if payload is Dictionary:
				broadcast_received.emit(short, str(payload.get("event", "")), payload.get("payload"))
		"presence_state":
			if payload is Dictionary:
				presence_state.emit(short, payload)
		"presence_diff":
			if payload is Dictionary:
				presence_diff.emit(short, payload.get("joins", {}), payload.get("leaves", {}))
		"system":
			if payload is Dictionary and payload.get("status", "") == "error":
				channel_error.emit(short, str(payload.get("message", "channel error")))
		"phx_error", "phx_close":
			# Only react if it is about our current join of this topic, not
			# an older join we already replaced or left.
			if _channels.has(topic) and str(message.get("join_ref", "")) == _channels[topic]["join_ref"]:
				_channels[topic]["joined"] = false
				channel_error.emit(short, "channel closed by server")
