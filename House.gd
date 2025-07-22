# House.gd - Complete implementation for Land of Liars
extends StaticBody3D

@export var house_id: int = 0
@export var assigned_player_id: int = -1

# Node references
@onready var front_door: Area3D = $FrontDoor
@onready var back_door: Area3D = $BackDoor
@onready var front_window: MeshInstance3D = $FrontWindow
@onready var side_window: MeshInstance3D = $SideWindow
@onready var interior_light: OmniLight3D = $Interior/InteriorLight
@onready var player_spawn_point: Marker3D = $Interior/PlayerSpawnPoint
@onready var window_view_point: Marker3D = $Interior/WindowView
@onready var house_audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

# House state
var is_occupied: bool = false
var can_be_entered: bool = true
var killer_inside: bool = false
var is_night: bool = false
var player_inside: Node3D = null

# Visual materials
var window_day_material: StandardMaterial3D
var window_night_material: StandardMaterial3D

signal house_entered(killer_id: int, victim_id: int)
signal house_exited(killer_id: int)
signal player_entered_house(player_id: int)
signal window_viewed(viewer_id: int, house_id: int)

func _ready():
	add_to_group("houses")
	setup_materials()
	setup_signals()
	setup_collision_layers()
	
	# Initially setup for day
	set_house_lighting(true)
	
	print("House ", house_id, " initialized")

func setup_materials():
	# Day window material (clear, bright)
	window_day_material = StandardMaterial3D.new()
	window_day_material.flags_transparent = true
	window_day_material.albedo_color = Color(0.7, 0.9, 1.0, 0.4)
	window_day_material.emission_enabled = true
	window_day_material.emission = Color(1.0, 1.0, 0.9) * 0.2
	
	# Night window material (darker, warm glow)
	window_night_material = StandardMaterial3D.new()
	window_night_material.flags_transparent = true
	window_night_material.albedo_color = Color(1.0, 0.8, 0.6, 0.6)
	window_night_material.emission_enabled = true
	window_night_material.emission = Color(1.0, 0.7, 0.4) * 0.3

func setup_signals():
	if front_door:
		front_door.body_entered.connect(_on_front_door_entered)
		front_door.body_exited.connect(_on_front_door_exited)
		print("Front door signals connected for house ", house_id)
	
	if back_door:
		back_door.body_entered.connect(_on_back_door_entered)
		back_door.body_exited.connect(_on_back_door_exited)
		print("Back door signals connected for house ", house_id)
	
	# Connect to game manager for day/night cycle
	if GameManager:
		GameManager.day_night_changed.connect(_on_day_night_changed)

func setup_collision_layers():
	# Set collision layers appropriately
	collision_layer = 1  # World geometry
	collision_mask = 0   # Houses don't need to detect anything via collision
	
	if front_door:
		front_door.collision_layer = 8  # Layer 4 for door detection
		front_door.collision_mask = 2   # Layer 2 for players
	
	if back_door:
		back_door.collision_layer = 8
		back_door.collision_mask = 2

func assign_to_player(player_id: int):
	assigned_player_id = player_id
	print("House ", house_id, " assigned to player ", player_id)
	
	# Teleport player to house spawn point
	if PlayerManager:
		var player = PlayerManager.get_player_by_id(player_id)
		if player and player_spawn_point:
			player.global_position = player_spawn_point.global_position
			player_inside = player
			is_occupied = true

func _on_day_night_changed(day: bool):
	is_night = not day
	set_house_lighting(day)
	can_be_entered = not day  # Only allow entry at night

func set_house_lighting(day: bool):
	if interior_light:
		if day:
			interior_light.light_energy = 0.8
			interior_light.light_color = Color(1.0, 0.95, 0.8)
		else:
			interior_light.light_energy = 0.3
			interior_light.light_color = Color(1.0, 0.7, 0.4)
	
	# Update window materials
	if front_window:
		front_window.material_override = window_day_material if day else window_night_material
	if side_window:
		side_window.material_override = window_day_material if day else window_night_material

func _on_front_door_entered(body):
	if not body.is_in_group("players"):
		return
		
	var player_id = body.get_multiplayer_authority()
	print("Player ", player_id, " entered front door of house ", house_id)
	
	# During day - anyone can enter (for setup/discussion)
	if not is_night:
		handle_day_entry(body, player_id)
		return
	
	# During night - only killers can enter other houses
	if assigned_player_id != player_id:
		if PlayerManager and PlayerManager.is_mafia(player_id):
			handle_killer_entry(body, player_id)
		else:
			# Innocent players can't enter other houses at night
			print("Player ", player_id, " cannot enter house ", house_id, " at night")
			# Teleport them back outside
			var exit_position = global_position + global_transform.basis.z * -4
			body.global_position = exit_position
	else:
		# Player entering their own house
		handle_resident_entry(body, player_id)

func _on_back_door_entered(body):
	if not body.is_in_group("players"):
		return
		
	var player_id = body.get_multiplayer_authority()
	
	# Back door is primarily for killers to exit stealthily
	if killer_inside and PlayerManager and PlayerManager.is_mafia(player_id):
		handle_killer_exit(body, player_id)

func _on_front_door_exited(body):
	if not body.is_in_group("players"):
		return
		
	var player_id = body.get_multiplayer_authority()
	if player_inside == body:
		player_inside = null
		is_occupied = false

func _on_back_door_exited(body):
	if not body.is_in_group("players"):
		return
		
	var player_id = body.get_multiplayer_authority()
	if killer_inside and PlayerManager and PlayerManager.is_mafia(player_id):
		killer_inside = false
		house_exited.emit(player_id)

func handle_day_entry(player: Node3D, player_id: int):
	# During day, players can visit each other's houses
	player_inside = player
	is_occupied = true
	player_entered_house.emit(player_id)
	
	# Position player at spawn point
	if player_spawn_point:
		player.global_position = player_spawn_point.global_position

func handle_resident_entry(player: Node3D, player_id: int):
	# Player entering their own house at night
	player_inside = player
	is_occupied = true
	
	if player_spawn_point:
		player.global_position = player_spawn_point.global_position
	
	# Start moon viewing phase for townfolk
	if PlayerManager and not PlayerManager.is_mafia(player_id):
		start_moon_viewing_phase(player_id)

func handle_killer_entry(player: Node3D, player_id: int):
	if not can_be_entered or assigned_player_id == -1:
		return
	
	killer_inside = true
	can_be_entered = false
	
	print("Killer ", player_id, " entered house of player ", assigned_player_id)
	house_entered.emit(player_id, assigned_player_id)
	
	# Play entry sound
	play_house_sound("door_creak")
	
	# Start kill sequence after brief delay
	await get_tree().create_timer(1.0).timeout
	start_kill_sequence(player_id, assigned_player_id)

func handle_killer_exit(player: Node3D, player_id: int):
	killer_inside = false
	can_be_entered = true
	
	print("Killer ", player_id, " exited house ", house_id)
	house_exited.emit(player_id)
	
	# Play exit sound
	play_house_sound("door_close")

func start_moon_viewing_phase(player_id: int):
	# Allow townfolk to look out side window at moon
	if multiplayer.get_unique_id() == player_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("start_moon_viewing"):
			ui.start_moon_viewing(15.0)  # 15 seconds to look around

func start_kill_sequence(killer_id: int, victim_id: int):
	print("Kill sequence started in house ", house_id)
	
	# Notify UI to show kill interaction for killer
	if multiplayer.get_unique_id() == killer_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("start_kill_sequence"):
			ui.start_kill_sequence(victim_id, 10.0)  # 10-15 seconds to complete
	
	# Check if sheriff is defending this house
	if PlayerManager:
		var victim_role = PlayerManager.get_player_role(victim_id)
		if victim_role == GameManager.PlayerRole.SHERIFF:
			handle_sheriff_defense(killer_id, victim_id)
		else:
			# Normal kill sequence
			await get_tree().create_timer(10.0).timeout
			complete_kill(killer_id, victim_id)

func handle_sheriff_defense(killer_id: int, victim_id: int):
	print("Sheriff defending house!")
	
	# Give sheriff chance to shoot killer
	if multiplayer.get_unique_id() == victim_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("sheriff_defense_sequence"):
			ui.sheriff_defense_sequence(killer_id, 5.0)  # Quick reaction time
	
	# Wait for sheriff action or timeout
	await get_tree().create_timer(5.0).timeout
	
	# If sheriff didn't defend successfully, proceed with kill
	complete_kill(killer_id, victim_id)

func complete_kill(killer_id: int, victim_id: int):
	# Only complete if still night phase
	if GameManager and not GameManager.is_day:
		print("Player ", victim_id, " was killed in house ", house_id)
		
		# Mark victim as eliminated
		if PlayerManager:
			PlayerManager.eliminate_player(victim_id)
		
		# Play death sound
		play_house_sound("struggle")
		
		# Visual effect
		if interior_light:
			# Brief light flicker
			var original_energy = interior_light.light_energy
			interior_light.light_energy = 0.1
			await get_tree().create_timer(0.5).timeout
			interior_light.light_energy = original_energy

func get_window_view() -> Array:
	# Return what can be seen from house windows
	var visible_info = []
	
	if not window_view_point:
		return visible_info
	
	# Cast rays from window to detect other houses/players
	var space_state = get_world_3d().direct_space_state
	
	# Check each other house
	var houses = get_tree().get_nodes_in_group("houses")
	for house in houses:
		if house == self:
			continue
			
		var query = PhysicsRayQueryParameters3D.create(
			window_view_point.global_position,
			house.global_position
		)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		if result and result["collider"] == house:
			# Can see this house
			if house.killer_inside:
				visible_info.append({
					"type": "killer_in_house",
					"house_id": house.house_id,
					"target_player": house.assigned_player_id
				})
	
	return visible_info

func allow_investigator_peek(investigator_id: int):
	# Called when investigator uses their ability
	var window_view = get_window_view()
	
	if multiplayer.get_unique_id() == investigator_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("show_window_investigation"):
			ui.show_window_investigation(window_view)
	
	window_viewed.emit(investigator_id, house_id)

func play_house_sound(sound_type: String):
	if not house_audio:
		return
	
	var sound_resource = null
	match sound_type:
		"door_creak":
			# Load door creak sound
			pass
		"door_close":
			# Load door close sound  
			pass
		"struggle":
			# Load struggle sound
			pass
	
	if sound_resource:
		house_audio.stream = sound_resource
		house_audio.play()

func get_house_data() -> Dictionary:
	return {
		"house_id": house_id,
		"assigned_player": assigned_player_id,
		"is_occupied": is_occupied,
		"killer_inside": killer_inside,
		"can_enter": can_be_entered
	}

# Called by PlayerManager when assigning houses
func set_house_data(data: Dictionary):
	if data.has("house_id"):
		house_id = data["house_id"]
	if data.has("assigned_player"):
		assigned_player_id = data["assigned_player"]
