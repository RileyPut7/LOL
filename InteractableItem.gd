# InteractableItem.gd
extends RigidBody3D

@export var item_name: String = "Item"
@export var item_description: String = "A mysterious item"
@export var item_type: String = "generic"  # generic, weapon, evidence, tool
@export var can_be_picked_up: bool = true
@export var interact_distance: float = 2.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var outline: MeshInstance3D = $Outline

var is_highlighted: bool = false
var original_material: Material

func _ready():
	add_to_group("items")
	set_collision_layer_value(3, true)  # Layer 3 for interactables
	
	# Store original material
	if mesh and mesh.material_override:
		original_material = mesh.material_override
	
	# Setup outline (initially hidden)
	if outline:
		outline.visible = false
		setup_outline_material()

func setup_outline_material():
	if not outline:
		return
		
	var outline_material = StandardMaterial3D.new()
	outline_material.flags_unshaded = true
	outline_material.albedo_color = Color.YELLOW
	outline_material.flags_transparent = true
	outline_material.flags_do_not_receive_shadows = true
	outline_material.flags_disable_ambient_light = true
	outline_material.no_depth_test = true
	outline_material.grow_amount = 0.02
	
	outline.material_override = outline_material

func interact(player: Node3D):
	print("Player interacted with: ", item_name)
	
	if can_be_picked_up:
		if player.has_method("pickup_item"):
			player.pickup_item(self)
	else:
		# Handle non-pickup interactions
		handle_special_interaction(player)

func handle_special_interaction(player: Node3D):
	# Override in specific item scripts
	match item_type:
		"evidence":
			examine_evidence(player)
		"tool":
			use_tool(player)
		_:
			show_description(player)

func examine_evidence(player: Node3D):
	# Send evidence information to player
	var evidence_info = {
		"name": item_name,
		"description": item_description,
		"type": "evidence"
	}
	
	if player.has_method("receive_evidence"):
		player.receive_evidence(evidence_info)

func use_tool(player: Node3D):
	# Tool-specific logic
	print("Using tool: ", item_name)

func show_description(player: Node3D):
	# Show item description in UI
	if player.has_method("show_item_description"):
		player.show_item_description(item_name, item_description)

func highlight():
	if is_highlighted:
		return
		
	is_highlighted = true
	if outline:
		outline.visible = true

func unhighlight():
	if not is_highlighted:
		return
		
	is_highlighted = false
	if outline:
		outline.visible = false

func set_item_data(data: Dictionary):
	if data.has("name"):
		item_name = data["name"]
	if data.has("description"):
		item_description = data["description"]
	if data.has("type"):
		item_type = data["type"]
	if data.has("can_pickup"):
		can_be_picked_up = data["can_pickup"]

func get_item_data() -> Dictionary:
	return {
		"name": item_name,
		"description": item_description,
		"type": item_type,
		"can_pickup": can_be_picked_up
	}
