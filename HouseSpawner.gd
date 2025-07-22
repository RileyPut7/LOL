# HouseSpawner.gd - Attach to a Node3D in your main game scene
extends Node3D

@export var house_scene: PackedScene = preload("res://House.tscn")
@export var houses_container: Node3D
@export var spawn_houses_automatically: bool = true

# House positions around town square (adjust based on your map size)
var house_positions: Array = [
	Vector3(15, 0, 15),   # Northeast
	Vector3(-15, 0, 15),  # Northwest  
	Vector3(15, 0, -15),  # Southeast
	Vector3(-15, 0, -15), # Southwest
	Vector3(20, 0, 0),    # East
	Vector3(-20, 0, 0),   # West
	Vector3(0, 0, 20),    # North
	Vector3(0, 0, -20)    # South
]

var house_rotations: Array = [
	225,  # Northeast faces southwest (toward center)
	315,  # Northwest faces southeast
	135,  # Southeast faces northwest  
	45,   # Southwest faces northeast
	270,  # East faces west
	90,   # West faces east
	180,  # North faces south
	0     # South faces north
]

var spawned_houses: Array = []

func _ready():
	if spawn_houses_automatically:
		call_deferred("spawn_all_houses")

func spawn_all_houses():
	print("Spawning houses...")
	
	if not houses_container:
		houses_container = Node3D.new()
		houses_container.name = "Houses"
		get_parent().add_child(houses_container)
		print("Created houses container")
	
	# Clear existing houses
	for child in houses_container.get_children():
		child.queue_free()
	spawned_houses.clear()
	
	# Spawn new houses
	for i in range(min(house_positions.size(), 8)):  # Max 8 houses
		spawn_house(i)
	
	print("Spawned ", spawned_houses.size(), " houses")

func spawn_house(house_index: int):
	if house_index >= house_positions.size():
		return
	
	if not house_scene:
		print("ERROR: House scene not set!")
		return
	
	var house_instance = house_scene.instantiate()
	house_instance.name = "House_" + str(house_index)
	house_instance.house_id = house_index
	
	# Position house
	house_instance.global_position = house_positions[house_index]
	
	# Rotate house to face town center
	house_instance.rotation_degrees.y = house_rotations[house_index]
	
	# Add to scene
	houses_container.add_child(house_instance)
	spawned_houses.append(house_instance)
	
	print("Spawned house ", house_index, " at ", house_positions[house_index])

func assign_houses_to_players():
	# Call this after players join and game starts
	if not PlayerManager or not NetworkManager:
		print("ERROR: Cannot assign houses - managers not found")
		return
	
	var connected_players = NetworkManager.connected_players.keys()
	
	for i in range(min(connected_players.size(), spawned_houses.size())):
		var player_id = connected_players[i]
		var house = spawned_houses[i]
		
		if house and house.has_method("assign_to_player"):
			house.assign_to_player(player_id)
			print("Assigned house ", i, " to player ", player_id)

func get_house_by_id(house_id: int) -> Node3D:
	for house in spawned_houses:
		if house.house_id == house_id:
			return house
	return null

func get_player_house(player_id: int) -> Node3D:
	for house in spawned_houses:
		if house.assigned_player_id == player_id:
			return house
	return null

func teleport_all_players_to_houses():
	# Call this at start of night phase
	if not PlayerManager:
		return
	
	for house in spawned_houses:
		if house.assigned_player_id != -1:
			var player = PlayerManager.get_player_by_id(house.assigned_player_id)
			if player and house.player_spawn_point:
				player.global_position = house.player_spawn_point.global_position
				print("Teleported player ", house.assigned_player_id, " to their house")

# Debug functions
func debug_show_house_info():
	print("=== HOUSE DEBUG INFO ===")
	for i in range(spawned_houses.size()):
		var house = spawned_houses[i]
		print("House ", i, ":")
		print("  Position: ", house.global_position)
		print("  Assigned Player: ", house.assigned_player_id)
		print("  Occupied: ", house.is_occupied)
		print("  Can Enter: ", house.can_be_entered)

# Call these from GameManager at appropriate times
func on_game_started():
	assign_houses_to_players()

func on_night_phase_started():
	teleport_all_players_to_houses()

func on_day_phase_started():
	# Allow free movement during day
	pass
