# Debug MainMenu.gd - Fixed paths
extends Control

# Fixed paths to match your actual scene structure
@onready var main_panel: Panel = get_node_or_null("MainPanel")
@onready var server_browser: Panel = get_node_or_null("ServerBrowser")
@onready var create_server: Panel = get_node_or_null("CreateServer")
@onready var player_name_input: LineEdit = get_node_or_null("MainPanel/VBoxContainer/PlayerNameInput")
@onready var host_button: Button = get_node_or_null("MainPanel/VBoxContainer/HostButton")
@onready var join_button: Button = get_node_or_null("MainPanel/VBoxContainer/JoinButton")
@onready var quit_button: Button = get_node_or_null("MainPanel/VBoxContainer/QuitButton")

# Server Browser
@onready var server_list: ItemList = get_node_or_null("ServerBrowser/VBoxContainer/ItemList")
@onready var refresh_button: Button = get_node_or_null("ServerBrowser/VBoxContainer/HBoxContainer/RefreshButton")
@onready var browser_join_button: Button = get_node_or_null("ServerBrowser/VBoxContainer/HBoxContainer/JoinButton")
@onready var browser_back_button: Button = get_node_or_null("ServerBrowser/VBoxContainer/HBoxContainer/BackButton")

# Create Server
@onready var server_name_input: LineEdit = get_node_or_null("CreateServer/VBoxContainer/ServerNameInput")
@onready var port_input: SpinBox = get_node_or_null("CreateServer/VBoxContainer/PortInput")
@onready var create_button: Button = get_node_or_null("CreateServer/VBoxContainer/HBoxContainer/CreateButton")
@onready var create_back_button: Button = get_node_or_null("CreateServer/VBoxContainer/HBoxContainer/BackButton")

func _ready():
	setup_ui()
	connect_signals()
	
	# Set default player name
	if player_name_input:
		player_name_input.text = "Player" + str(randi() % 1000)
		print("Set default player name")
	else:
		print("ERROR: PlayerNameInput not found!")

func setup_ui():
	# Show only main panel initially
	if main_panel:
		main_panel.visible = true
		print("MainPanel made visible")
	if server_browser:
		server_browser.visible = false
		print("ServerBrowser hidden")
	if create_server:
		create_server.visible = false
		print("CreateServer hidden")
	
	# Setup server browser
	if server_list:
		server_list.select_mode = ItemList.SELECT_SINGLE
		print("Server list configured")
	
	# Setup port input
	if port_input:
		port_input.min_value = 1024
		port_input.max_value = 65535
		port_input.value = 7000  # Default port since NetworkManager might not be ready yet
		print("Port input configured")

func connect_signals():
	print("=== CONNECTING SIGNALS ===")
	
	# Main menu buttons
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
		print("Connected host button")
	else:
		print("ERROR: Host button not found!")
		
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
		print("Connected join button")
	else:
		print("ERROR: Join button not found!")
		
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		print("Connected quit button")
	else:
		print("ERROR: Quit button not found!")
	
	# Server browser buttons
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
		print("Connected refresh button")
	
	if browser_join_button:
		browser_join_button.pressed.connect(_on_browser_join_pressed)
		print("Connected browser join button")
	
	if browser_back_button:
		browser_back_button.pressed.connect(_on_browser_back_pressed)
		print("Connected browser back button")
	
	if server_list:
		server_list.item_selected.connect(_on_server_selected)
		print("Connected server list")
	
	# Create server buttons
	if create_button:
		create_button.pressed.connect(_on_create_pressed)
		print("Connected create button")
	
	# Network signals - check if NetworkManager exists
	if NetworkManager:
		NetworkManager.server_created.connect(_on_server_created)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
		NetworkManager.server_list_updated.connect(_on_server_list_updated)
		print("Connected to NetworkManager signals")
	else:
		print("ERROR: NetworkManager not found for signal connections!")

func _on_host_pressed():
	print("HOST BUTTON CLICKED!")
	if not player_name_input:
		print("ERROR: Player name input not found")
		return
		
	if player_name_input.text.strip_edges().length() < 3:
		print("ERROR: Player name must be at least 3 characters")
		return
		
	show_create_server_panel()

func _on_join_pressed():
	print("JOIN BUTTON CLICKED!")
	if not player_name_input:
		print("ERROR: Player name input not found")
		return
		
	if player_name_input.text.strip_edges().length() < 3:
		print("ERROR: Player name must be at least 3 characters")
		return
		
	show_server_browser()

func _on_quit_pressed():
	print("QUIT BUTTON CLICKED!")
	get_tree().quit()

func show_create_server_panel():
	print("Switching to create server panel")
	if main_panel:
		main_panel.visible = false
	if create_server:
		create_server.visible = true
	if server_name_input and player_name_input:
		server_name_input.text = player_name_input.text + "'s Server"

func show_server_browser():
	print("Switching to server browser")
	if main_panel:
		main_panel.visible = false
	if server_browser:
		server_browser.visible = true

func _on_refresh_pressed():
	print("Refresh button clicked!")

func _on_browser_join_pressed():
	print("Browser join button clicked!")

func _on_browser_back_pressed():
	print("Browser back button clicked!")
	if server_browser:
		server_browser.visible = false
	if main_panel:
		main_panel.visible = true

func _on_server_selected(index: int):
	print("Server selected: ", index)

func _on_create_pressed():
	print("Create server button clicked!")
	
	if not server_name_input or not port_input or not create_button:
		print("ERROR: Create server UI elements not found")
		return
		
	var server_name = server_name_input.text.strip_edges()
	var port = int(port_input.value)
	
	if server_name.length() < 3:
		print("ERROR: Server name must be at least 3 characters")
		return
		
	if not NetworkManager:
		print("ERROR: NetworkManager not found")
		return
		
	if player_name_input:
		NetworkManager.set_player_name(player_name_input.text.strip_edges())
		print("Set player name: ", player_name_input.text.strip_edges())
	
	print("Attempting to create server: ", server_name, " on port: ", port)
	
	if NetworkManager.create_server(server_name, port):
		create_button.disabled = true
		create_button.text = "Creating..."
		print("Server creation initiated...")
	else:
		print("ERROR: Failed to create server")

func _on_create_back_pressed():
	print("Create back button clicked!")
	if create_server:
		create_server.visible = false
	if main_panel:
		main_panel.visible = true

func _on_server_created(port: int):
	print("Server created successfully on port ", port)
	# Switch to game lobby
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_server_disconnected():
	print("Server disconnected!")
	# Return to main menu
	if main_panel:
		main_panel.visible = true
	if server_browser:
		server_browser.visible = false
	if create_server:
		create_server.visible = false
	
	# Reset button states
	if browser_join_button:
		browser_join_button.disabled = false
		browser_join_button.text = "Join"
	if create_button:
		create_button.disabled = false
		create_button.text = "Create"

func _on_server_list_updated(servers: Array):
	print("Server list updated with ", servers.size(), " servers")
	if not server_list:
		return
		
	server_list.clear()
	
	for server in servers:
		var text = "%s (%d/%d) - %s" % [
			server["name"],
			server["current_players"],
			server["max_players"],
			server["host"]
		]
		server_list.add_item(text)
