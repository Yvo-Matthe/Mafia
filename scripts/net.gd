extends Node
## Autoload. Holds how this match is being played (alone, hosting or
## joining) across the change from the menu scene to the match scene.

enum Mode { SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 7777

var mode := Mode.SINGLE
var local_family := GameData.PLAYER
var autoplay := false
## Shown on the menu after a match ends or a connection drops.
var status_message := ""
## Set once the other player's match scene has finished loading.
var remote_loaded := false


func is_online() -> bool:
	return mode != Mode.SINGLE


func host(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	remote_loaded = false
	mode = Mode.HOST
	local_family = GameData.PLAYER
	return OK


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	remote_loaded = false
	mode = Mode.CLIENT
	local_family = GameData.RIVAL
	return OK


func play_single() -> void:
	leave()
	local_family = GameData.PLAYER


## Called by the match scene when it is ready. Lives here rather than in the
## match scene because that scene may not exist yet on the other side.
func announce_loaded() -> void:
	_peer_loaded.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _peer_loaded() -> void:
	remote_loaded = true


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SINGLE
