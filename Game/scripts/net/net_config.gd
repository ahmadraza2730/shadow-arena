class_name NetConfig
extends RefCounted
## Where the online relay lives. This is the project's own free Supabase
## project ("shadow-arena"); only its public (anon) key is stored here,
## which is safe to ship in a game.
##
## Override for testing with the command line:  -- --relay=ws://127.0.0.1:4000/socket/websocket

const SUPABASE_REF := "mfzauhedufjkwlnxqimo"
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1memF1aGVkdWZqa3dsbnhxaW1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4MjEwNDEsImV4cCI6MjExMDM5NzA0MX0.yHQ716XCcKs4sUoMnJpdjYI6fD_6DTnAeH_OAtiOSUA"
## Bump when the network format changes so old and new builds never meet.
const PROTOCOL := "sa1"


static func socket_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			return arg.trim_prefix("--relay=")
	return "wss://%s.supabase.co/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [SUPABASE_REF, ANON_KEY]
