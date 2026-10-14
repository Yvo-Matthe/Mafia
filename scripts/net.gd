extends Node
## Autoload. Holds the match setup (who sits in each family's seat) and how
## this copy of the game takes part (alone, hosting or joining) across the
## change from the menu scene to the match scene.

enum Mode { SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 7777
const MAX_CLIENTS := GameData.MAX_FAMILIES - 1

## One seat per family: {kind: "human" | "ai" | "open" | "closed", team, peer}.
## A human seat's peer is that player's multiplayer id (the host is 1).
var slots: Array = []
var mode := Mode.SINGLE
var local_family := 0
var autoplay := false
## Shown on the menu after a match ends or a connection drops.
var status_message := ""
## Set once every other player's match scene has finished loading.
var loaded_peers := {}


func _ready() -> void:
	slots = default_slots(false)


func is_online() -> bool:
	return mode != Mode.SINGLE


func default_slots(online: bool) -> Array:
	var out := [{"kind": "human", "team": 0, "peer": 1}]
	out.append({"kind": "open" if online else "ai", "team": 1, "peer": 0})
	for i in range(2, GameData.MAX_FAMILIES):
		out.append({"kind": "closed", "team": i, "peer": 0})
	return out


func family_of_peer(peer: int) -> int:
	for i in slots.size():
		if slots[i]["kind"] == "human" and slots[i]["peer"] == peer:
			return i
	return -1


## The seats as a match uses them: unfilled open seats are left empty.
func match_slots() -> Array:
	var out := []
	for s in slots:
		var c: Dictionary = s.duplicate()
		if c["kind"] == "open":
			c["kind"] = "closed"
		out.append(c)
	return out


func host(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	loaded_peers.clear()
	mode = Mode.HOST
	slots = default_slots(true)
	return OK


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	loaded_peers.clear()
	mode = Mode.CLIENT
	return OK


func play_single() -> void:
	leave()
	slots = default_slots(false)


## Called by the match scene when it is ready. Lives here rather than in the
## match scene because that scene may not exist yet on the other side.
func announce_loaded() -> void:
	_peer_loaded.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _peer_loaded() -> void:
	loaded_peers[multiplayer.get_remote_sender_id()] = true


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SINGLE
