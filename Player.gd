# Player.gd
extends CharacterBody3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/InteractionRay
@onready var mesh: MeshInstance3D = $MeshInstance3D

# Movement constants (CS:GO-like)
const WALK_SPEED = 4.5
const RUN_SPEED = 6.0
const CROUCH_SPEED = 2.0
const JUMP_VELOCITY = 5.5
const AIR_ACCELERATION = 3.0
const GROUND_ACCELERATION = 10.0
const GROUND_FRICTION = 14
const AIR_FRICTION = 0.7
const MAX_SLOPE_ANGLE = 45.0

# Mouse settings
var mouse_sensitivity = 0.002
var mouse_captured = false

# Player state
var is_crouching = false
var is_running = false
var current_speed = WALK_SPEED
var player_role: GameManager.PlayerRole = GameManager.PlayerRole.INNOCENT
var is_alive = true
var held_item = null

# Networking
var player_id: int
var player_name: String = "Player"

# Input buffer for smooth networking
var input_buffer: Array = []

func _ready():
	player_id = get_multiplayer_authority()
	
	# Only setup camera and input for local player
	if player_id == multiplayer.get_unique_id():
		setup_local_player()
	else:
		setup_remote_player()
	
	# Setup interaction ray
	interaction_ray.collision_mask = 4  # Layer 3 for interactables
	interaction_ray.target_position = Vector3(0, 0, -2)

func setup_local_player():
	camera.current = true
	mouse_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func setup_remote_player():
	# Disable camera for remote players
	camera.queue_free()
	# You might want to add a nameplate or other visual indicators

func _input(event):
	# Only handle input for local player
	if player_id != multiplayer.get_unique_id() or not is_alive:
		return
		
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	if event.is_action_pressed("ui_cancel"):
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_captured = true
	
	if event.is_action_pressed("interact"):
		try_interact()

func _physics_process(delta):
	if player_id != multiplayer.get_unique_id() or not is_alive:
		return
		
	handle_input()
	apply_movement(delta)
	
	# Send position to other clients
	if is_on_floor() or velocity.length() > 0.1:
		sync_position.rpc(global_position, rotation, head.rotation)

func handle_input():
	# Crouching
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			start_crouch()
	else:
		if is_crouching:
			try_stand()
	
	# Running
	is_running = Input.is_action_pressed("run") and not is_crouching
	
	# Update current speed
	if is_crouching:
		current_speed = CROUCH_SPEED
	elif is_running:
		current_speed = RUN_SPEED
	else:
		current_speed = WALK_SPEED

func apply_movement(delta):
	# Get input direction
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_back"):
		input_dir.y += 1
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	
	# Normalize diagonal movement
	if input_dir.length() > 1:
		input_dir = input_dir.normalized()
	
	# Convert to 3D direction relative to player rotation
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply gravity
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	
	# Handle jumping
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Ground movement (CS:GO-style)
	if is_on_floor():
		if direction:
			# Accelerate
			var target_velocity = direction * current_speed
			var velocity_2d = Vector2(velocity.x, velocity.z)
			var target_2d = Vector2(target_velocity.x, target_velocity.z)
			
			velocity_2d = velocity_2d.move_toward(target_2d, GROUND_ACCELERATION * delta)
			velocity.x = velocity_2d.x
			velocity.z = velocity_2d.y
		else:
			# Apply friction
			var velocity_2d = Vector2(velocity.x, velocity.z)
			velocity_2d = velocity_2d.move_toward(Vector2.ZERO, GROUND_FRICTION * delta)
			velocity.x = velocity_2d.x
			velocity.z = velocity_2d.y
	else:
		# Air movement (strafe jumping mechanics)
		if direction:
			var target_velocity = direction * current_speed
			var velocity_2d = Vector2(velocity.x, velocity.z)
			var target_2d = Vector2(target_velocity.x, target_velocity.z)
			
			# Only accelerate if it would increase speed in the desired direction
			var dot = velocity_2d.dot(target_2d.normalized())
			if dot < current_speed:
				velocity_2d = velocity_2d.move_toward(target_2d, AIR_ACCELERATION * delta)
				velocity.x = velocity_2d.x
				velocity.z = velocity_2d.y
		
		# Minimal air friction
		var velocity_2d = Vector2(velocity.x, velocity.z)
		velocity_2d = velocity_2d.move_toward(Vector2.ZERO, AIR_FRICTION * delta)
		velocity.x = velocity_2d.x
		velocity.z = velocity_2d.y
	
	move_and_slide()

func start_crouch():
	is_crouching = true
	# Scale down the collision shape
	var collision = $CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule = collision.shape as CapsuleShape3D
		capsule.height *= 0.5
		collision.position.y -= 0.5

func try_stand():
	# Check if there's room to stand
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, 2, 0)
	)
	var result = space_state.intersect_ray(query)
	
	if not result:
		# Safe to stand
		is_crouching = false
		var collision = $CollisionShape3D
		if collision and collision.shape is CapsuleShape3D:
			var capsule = collision.shape as CapsuleShape3D
			capsule.height *= 2.0
			collision.position.y += 0.5

func try_interact():
	if not interaction_ray.is_colliding():
		return
		
	var collider = interaction_ray.get_collider()
	if collider and collider.has_method("interact"):
		collider.interact(self)
	elif collider and collider.is_in_group("items"):
		pickup_item(collider)

func pickup_item(item):
	if held_item:
		drop_item()
	
	held_item = item
	item.get_parent().remove_child(item)
	head.add_child(item)
	item.position = Vector3(0.5, -0.3, -1)
	
	print("Picked up: ", item.name)
	sync_item_pickup.rpc(item.name)

@rpc("any_peer", "call_local")
func sync_item_pickup(item_name: String):
	print("Player ", player_id, " picked up ", item_name)

func drop_item():
	if not held_item:
		return
		
	head.remove_child(held_item)
	get_tree().current_scene.add_child(held_item)
	held_item.global_position = global_position + transform.basis.z * 2
	
	print("Dropped: ", held_item.name)
	sync_item_drop.rpc(held_item.name, held_item.global_position)
	held_item = null

@rpc("any_peer", "call_local")
func sync_item_drop(item_name: String, drop_position: Vector3):
	print("Player ", player_id, " dropped ", item_name)

@rpc("unreliable", "any_peer", "call_local")
func sync_position(pos: Vector3, rot: Vector3, head_rot: Vector3):
	if player_id == multiplayer.get_unique_id():
		return  # Don't sync own position
	
	global_position = pos
	rotation = rot
	if head:
		head.rotation = head_rot

func set_role(role: GameManager.PlayerRole):
	player_role = role
	# Update player behavior based on role
	print("Role set to: ", GameManager.PlayerRole.keys()[role])

func eliminate():
	is_alive = false
	set_physics_process(false)
	# Make semi-transparent for ghost mode
	if mesh and mesh.material_override:
		var material = mesh.material_override as StandardMaterial3D
		material.flags_transparent = true
		material.albedo_color.a = 0.3
	
	# Disable collision
	$CollisionShape3D.disabled = true
	
	print("Player eliminated - entering spectator mode")

func reset():
	is_alive = true
	set_physics_process(true)
	velocity = Vector3.ZERO
	
	# Reset material
	if mesh and mesh.material_override:
		var material = mesh.material_override as StandardMaterial3D
		material.flags_transparent = false
		material.albedo_color.a = 1.0
	
	# Enable collision
	$CollisionShape3D.disabled = false
	
	# Drop any held items
	if held_item:
		drop_item()

func get_interaction_target():
	if interaction_ray.is_colliding():
		return interaction_ray.get_collider()
	return null

func can_see_player(target_player: Node3D) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		head.global_position,
		target_player.global_position + Vector3(0, 1, 0)  # Aim for head
	)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	
	if result and result["collider"] == target_player:
		return true
	return false

# Voting and night action methods
func vote_player(target_id: int):
	PlayerManager.request_player_action(player_id, "vote", target_id)

func perform_night_action(action_type: String, target_id: int):
	match player_role:
		GameManager.PlayerRole.MAFIA, GameManager.PlayerRole.GODFATHER:
			if action_type == "kill":
				PlayerManager.request_player_action(player_id, "night_kill", target_id)
				
		GameManager.PlayerRole.DOCTOR:
			if action_type == "protect":
				PlayerManager.request_player_action(player_id, "night_protect", target_id)
				
		GameManager.PlayerRole.SHERIFF:
			if action_type == "investigate":
				PlayerManager.request_player_action(player_id, "night_investigate", target_id)
				
		GameManager.PlayerRole.SERIAL_KILLER:
			if action_type == "kill":
				PlayerManager.request_player_action(player_id, "night_kill", target_id)

func get_nearby_players(radius: float = 5.0) -> Array:
	var nearby = []
	for p_id in PlayerManager.players:  # Renamed from player_id
		var player = PlayerManager.players[p_id]
		if player != self and is_instance_valid(player):
			if global_position.distance_to(player.global_position) <= radius:
				nearby.append(player)
	return nearby
