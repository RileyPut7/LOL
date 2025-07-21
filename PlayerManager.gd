# PlayerManager.gd
extends Node

signal player_role_assigned(player_id: int, role: GameManager.PlayerRole)
signal player_eliminated(player_id: int)
signal player_spawned(player_id: int)

const PLAYER_SCENE = preload("res://Player.tscn")

var players: Dictionary = {}
var player_roles: Dictionary = {}
var player_houses: Dictionary = {}
var spawn_points: Array = []

# House positions (you'll want to adjust these based on your map)
var house_positions: Array = [
	Vector3(10, 0, 10),
	Vector3(-10, 0, 10), 
	Vector3(10, 0, -10),
	Vector3(-10, 0, -10),
	Vector3(20, 0, 0),
	Vector3(-20, 0, 0),
	Vector3(0, 0, 20),
	Vector3(0, 0, -20)
]

func _ready():
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	# Setup spawn points (adjust positions based on your map)
	spawn_points = [
		Vector3(0, 1, 0),
		Vector3(5, 1, 0),
		Vector3(-5, 1, 0),
		Vector3(0, 1, 5),
		Vector3(0, 1, -5),
		Vector3(5, 1, 5),
		Vector3(-5, 1, 5),
		Vector3(5, 1, -5)
	]

func spawn_player(player_id: int):
	if players.has(player_id):
		return  # Player already spawned
		
	var player_scene = PLAYER_SCENE.instantiate()
	player_scene.name = "Player_" + str(player_id)
	player_scene.set_multiplayer_authority(player_id)
	
	# Get spawn position
	var spawn_index = players.size() % spawn_points.size()
	var spawn_pos = spawn_points[spawn_index]
	player_scene.global_position = spawn_pos
	
	# Add to scene
	get_tree().current_scene.add_child(player_scene)
	
	players[player_id] = player_scene
	player_spawned.emit(player_id)
	
	# Assign house
	assign_house(player_id)
	
	print("Player spawned: ", player_id, " at ", spawn_pos)

func assign_role(player_id: int, role: GameManager.PlayerRole):
	player_roles[player_id] = role
	player_role_assigned.emit(player_id, role)
	
	# Send role to specific player only
	if multiplayer.is_server():
		receive_role.rpc_id(player_id, role)

@rpc("authority", "call_local")
func receive_role(role: GameManager.PlayerRole):
	var my_id = multiplayer.get_unique_id()
	player_roles[my_id] = role
	print("Received role: ", GameManager.PlayerRole.keys()[role])
	
	# Update UI or player behavior based on role
	if players.has(my_id):
		var player = players[my_id]
		if player.has_method("set_role"):
			player.set_role(role)

func assign_house(player_id: int):
	if player_houses.has(player_id):
		return  # Already has house
		
	var house_index = player_houses.size() % house_positions.size()
	var house_pos = house_positions[house_index]
	
	player_houses[player_id] = {
		"position": house_pos,
		"index": house_index
	}
	
	# Notify player of their house
	if multiplayer.is_server():
		assign_house_position.rpc_id(player_id, house_pos, house_index)

@rpc("authority", "call_local")
func assign_house_position(position: Vector3, index: int):
	var my_id = multiplayer.get_unique_id()
	player_houses[my_id] = {
		"position": position,
		"index": index
	}
	print("Assigned house at position: ", position)

func eliminate_player(player_id: int):
	if not players.has(player_id):
		return
		
	var player = players[player_id]
	if player and is_instance_valid(player):
		# Make player a ghost/spectator
		if player.has_method("eliminate"):
			player.eliminate()
		else:
			# Default elimination - disable movement and hide
			player.set_physics_process(false)
			player.visible = false
	
	player_eliminated.emit(player_id)
	print("Player eliminated: ", player_id)

func get_player_role(player_id: int) -> GameManager.PlayerRole:
	return player_roles.get(player_id, GameManager.PlayerRole.INNOCENT)

func get_player_house(player_id: int) -> Dictionary:
	return player_houses.get(player_id, {})

func get_alive_players() -> Array:
	var alive = []
	for player_id in players:
		var player = players[player_id]
		if player and is_instance_valid(player) and player.visible:
			alive.append(player_id)
	return alive

func get_players_by_role(role: GameManager.PlayerRole) -> Array:
	var result = []
	for player_id in player_roles:
		if player_roles[player_id] == role:
			result.append(player_id)
	return result

func teleport_player_to_house(player_id: int):
	if not players.has(player_id) or not player_houses.has(player_id):
		return
		
	var player = players[player_id]
	var house_info = player_houses[player_id]
	
	if player and is_instance_valid(player):
		player.global_position = house_info["position"]

func teleport_all_players_to_houses():
	for player_id in players:
		teleport_player_to_house(player_id)

func get_player_at_position(position: Vector3, max_distance: float = 2.0) -> int:
	for player_id in players:
		var player = players[player_id]
		if player and is_instance_valid(player):
			if player.global_position.distance_to(position) <= max_distance:
				return player_id
	return -1

func get_player_by_id(player_id: int) -> Node:
	return players.get(player_id, null)

func _on_player_connected(player_id: int, player_name: String):
	# Spawn player when they connect
	call_deferred("spawn_player", player_id)

func _on_player_disconnected(player_id: int):
	# Remove player from game
	if players.has(player_id):
		var player = players[player_id]
		if player and is_instance_valid(player):
			player.queue_free()
		players.erase(player_id)
	
	player_roles.erase(player_id)
	player_houses.erase(player_id)

func reset_all_players():
	"""Reset all players for new game"""
	player_roles.clear()
	player_houses.clear()
	
	for player_id in players:
		var player = players[player_id]
		if player and is_instance_valid(player):
			# Reset player state
			player.visible = true
			player.set_physics_process(true)
			if player.has_method("reset"):
				player.reset()

@rpc("any_peer", "call_local")
func request_player_action(player_id: int, action: String, target_id: int = -1):
	"""Handle player action requests (voting, night actions, etc.)"""
	if not multiplayer.is_server():
		return
		
	match action:
		"vote":
			GameManager.submit_vote(player_id, target_id)
		"night_kill":
			GameManager.submit_night_action(player_id, "kill", target_id)
		"night_protect":
			GameManager.submit_night_action(player_id, "protect", target_id)
		"night_investigate":
			GameManager.submit_night_action(player_id, "investigate", target_id)

# Utility functions for role checking
func is_mafia(player_id: int) -> bool:
	var role = get_player_role(player_id)
	return role in [GameManager.PlayerRole.MAFIA, GameManager.PlayerRole.GODFATHER]

func is_innocent_team(player_id: int) -> bool:
	var role = get_player_role(player_id)
	return role in [GameManager.PlayerRole.INNOCENT, GameManager.PlayerRole.SHERIFF, 
					GameManager.PlayerRole.DOCTOR, GameManager.PlayerRole.INVESTIGATOR]

func can_perform_night_action(player_id: int) -> bool:
	var role = get_player_role(player_id)
	return role in [GameManager.PlayerRole.MAFIA, GameManager.PlayerRole.GODFATHER,
					GameManager.PlayerRole.SHERIFF, GameManager.PlayerRole.DOCTOR,
					GameManager.PlayerRole.INVESTIGATOR, GameManager.PlayerRole.SERIAL_KILLER]

func get_role_description(role: GameManager.PlayerRole) -> String:
	match role:
		GameManager.PlayerRole.INNOCENT:
			return "You are an Innocent. Help find and eliminate the Mafia."
		GameManager.PlayerRole.SHERIFF:
			return "You are the Sheriff. You can investigate players at night."
		GameManager.PlayerRole.DOCTOR:
			return "You are the Doctor. You can protect players from death at night."
		GameManager.PlayerRole.INVESTIGATOR:
			return "You are the Investigator. You can learn about players' roles."
		GameManager.PlayerRole.MAFIA:
			return "You are Mafia. Eliminate innocents at night and blend in during the day."
		GameManager.PlayerRole.GODFATHER:
			return "You are the Godfather. Lead the Mafia to victory."
		GameManager.PlayerRole.SERIAL_KILLER:
			return "You are the Serial Killer. Eliminate everyone to win."
		GameManager.PlayerRole.JESTER:
			return "You are the Jester. Get voted out during the day to win."
		_:
			return "Unknown role"
