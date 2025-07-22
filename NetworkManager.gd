# NetworkManager.gd
extends Node

signal player_connected(player_id: int, player_name: String)
signal player_disconnected(player_id: int)
signal server_created(port: int)

signal server_disconnected()
signal server_list_updated(servers: Array)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 8

var connected_players: Dictionary = {}
var player_name: String = "Player"
var is_host: bool = false
var discovered_servers: Array = []

# Server browser
var server_browser: UDPServer
var client_browser: PacketPeerUDP
var server_info: Dictionary = {}

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta):
	# Handle server discovery
	if server_browser and server_browser.is_listening():
		server_browser.poll()
		if server_browser.is_connection_available():
			var peer = server_browser.take_connection()
			var packet = peer.get_packet()
			var message = packet.get_string_from_utf8()
			
			if message == "MAFIA_GAME_DISCOVERY":
				# Send server info back
				var response = JSON.stringify(server_info)
				peer.put_packet(response.to_utf8_buffer())
	
	if client_browser:
		if client_browser.get_available_packet_count() > 0:
			var packet = client_browser.get_packet()
			var message = packet.get_string_from_utf8()
			
			var json = JSON.new()
			var parse_result = json.parse(message)
			if parse_result == OK:
				var server_data = json.data
				if server_data and not is_server_in_list(server_data):
					discovered_servers.append(server_data)
					server_list_updated.emit(discovered_servers)

func create_server(server_name: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	
	# Setup server info for discovery
	server_info = {
		"name": server_name,
		"host": player_name,
		"port": port,
		"current_players": 1,
		"max_players": MAX_PLAYERS
	}
	
	# Add host to connected players
	connected_players[1] = {"name": player_name, "id": 1}
	
	# Start server browser for discovery
	start_server_discovery(port + 1)
	
	server_created.emit(port)
	return true

func join_server(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("Failed to connect to server: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true

func disconnect_from_server():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	stop_server_browser()
	connected_players.clear()
	is_host = false
	server_disconnected.emit()

func start_server_discovery(discovery_port: int):
	server_browser = UDPServer.new()
	server_browser.listen(discovery_port)
	print("Server discovery started on port: ", discovery_port)

func start_server_browser():
	discovered_servers.clear()
	client_browser = PacketPeerUDP.new()
	client_browser.connect_to_host("255.255.255.255", DEFAULT_PORT + 1)
	
	# Send discovery request
	var discovery_msg = "MAFIA_GAME_DISCOVERY"
	client_browser.put_packet(discovery_msg.to_utf8_buffer())

func stop_server_browser():
	if server_browser:
		server_browser.stop()
		server_browser = null
	
	if client_browser:
		client_browser.close()
		client_browser = null

func is_server_in_list(server_data: Dictionary) -> bool:
	for server in discovered_servers:
		if server["port"] == server_data["port"] and server["host"] == server_data["host"]:
			return true
	return false

func get_discovered_servers() -> Array:
	return discovered_servers

func set_player_name(name: String):
	player_name = name

func get_player_name() -> String:
	return player_name

func is_server_host() -> bool:
	return is_host

func get_player_count() -> int:
	return connected_players.size()

func get_player_name_by_id(player_id: int) -> String:
	if connected_players.has(player_id):
		return connected_players[player_id]["name"]
	return "Unknown"

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	
	# Send player info to new peer
	if is_host:
		request_player_info.rpc_id(id)

func _on_peer_disconnected(id: int):
	print("Peer disconnected: ", id)
	
	if connected_players.has(id):
		player_disconnected.emit(id)
		connected_players.erase(id)
	
	# Update server info
	if is_host and server_info:
		server_info["current_players"] = connected_players.size()

func _on_connected_to_server():
	print("Connected to server")
	# Send our player info to server
	send_player_info.rpc_id(1, player_name)

func _on_connection_failed():
	print("Connection failed")
	server_disconnected.emit()

func _on_server_disconnected():
	print("Server disconnected")
	connected_players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

@rpc("any_peer", "call_remote")
func request_player_info():
	# Send our info to the server
	send_player_info.rpc_id(1, player_name)

@rpc("any_peer", "call_remote")
func send_player_info(player_info_name: String):
	var sender_id = multiplayer.get_remote_sender_id()
	
	connected_players[sender_id] = {
		"name": player_info_name,
		"id": sender_id
	}
	
	# Update server info
	if is_host and server_info:
		server_info["current_players"] = connected_players.size()
	
	# Notify all clients about the new player
	player_connected.emit(sender_id, player_info_name)
	
	# Send current player list to new player
	if is_host:
		sync_player_list.rpc_id(sender_id, connected_players)

@rpc("authority", "call_local")
func sync_player_list(players: Dictionary):
	for player_id in players:
		if not connected_players.has(player_id):
			connected_players[player_id] = players[player_id]
			player_connected.emit(player_id, players[player_id]["name"])
