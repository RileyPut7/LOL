# MainMenu.gd
extends Control

@onready var main_panel: Panel = $MainPanel
@onready var server_browser: Panel = $ServerBrowser
@onready var create_server: Panel = $CreateServer
@onready var player_name_input: LineEdit = $MainPanel/VBox/PlayerNameInput
@onready var host_button: Button = $MainPanel/VBox/HostButton
@onready var join_button: Button = $MainPanel/VBox/JoinButton
@onready var quit_button: Button = $MainPanel/VBox/QuitButton

# Server Browser
@onready var server_list: ItemList = $ServerBrowser/VBox/ServerList
@onready var refresh_button: Button = $ServerBrowser/VBox/HBox/RefreshButton
@onready var browser_join_button: Button = $ServerBrowser/VBox/HBox/JoinButton
@onready var browser_back_button: Button = $ServerBrowser/VBox/HBox/BackButton

# Create Server
@onready var server_name_input: LineEdit = $CreateServer/VBox/ServerNameInput
@onready var port_input: SpinBox = $CreateServer/VBox/PortInput
@onready var create_button: Button = $CreateServer/VBox/HBox/CreateButton
@onready var create_back_button: Button = $CreateServer/VBox/HBox/BackButton

func _ready():
	setup_ui()
	connect_signals()
	
	# Set default player name
	player_name_input.text = "Player" + str(randi() % 1000)

func setup_ui():
	# Show only main panel initially
	main_panel.visible = true
	server_browser.visible = false
	create_server.visible = false
	
	# Setup server browser
	server_list.select_mode = ItemList.SELECT_SINGLE
	
	# Setup port input
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = NetworkManager.DEFAULT_PORT

func connect_signals():
	# Main menu buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Server browser
	refresh_button.pressed.connect(_on_refresh_pressed)
	browser_join_button.pressed.connect(_on_browser_join_pressed)
	browser_back_button.pressed.connect(_on_browser_back_pressed)
	server_list.item_selected.connect(_on_server_selected)
	
	# Create server
	create_button.pressed.connect(_on_create_pressed)
	create_back_button.pressed.connect(_on_create_back_pressed)
	
	# Network signals
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.server_joined.connect(_on_server_joined)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.server_list_updated.connect(_on_server_list_updated)

func _on_host_pressed():
	if player_name_input.text.strip_edges().length() < 3:
		show_error("Player name must be at least 3 characters")
		return
		
	show_create_server_panel()

func _on_join_pressed():
	if player_name_input.text.strip_edges().length() < 3:
		show_error("Player name must be at least 3 characters")
		return
		
	show_server_browser()

func _on_quit_pressed():
	get_tree().quit()

func show_create_server_panel():
	main_panel.visible = false
	create_server.visible = true
	server_name_input.text = player_name_input.text + "'s Server"

func show_server_browser():
	main_panel.visible = false
	server_browser.visible = true
	_on_refresh_pressed()

func _on_refresh_pressed():
	refresh_button.disabled = true
	refresh_button.text = "Refreshing..."
	server_list.clear()
	
	NetworkManager.start_server_browser()
	
	# Re-enable after delay
	await get_tree().create_timer(2.0).timeout
	refresh_button.disabled = false
	refresh_button.text = "Refresh"

func _on_server_selected(index: int):
	browser_join_button.disabled = false

func _on_browser_join_pressed():
	var selected = server_list.get_selected_items()
	if selected.is_empty():
		return
		
	var index = selected[0]
	var servers = NetworkManager.get_discovered_servers()
	if index >= servers.size():
		return
		
	var server = servers[index]
	NetworkManager.set_player_name(player_name_input.text.strip_edges())
	
	if NetworkManager.join_server("127.0.0.1", server["port"]):  # Use localhost for discovery
		browser_join_button.disabled = true
		browser_join_button.text = "Joining..."

func _on_browser_back_pressed():
	NetworkManager.stop_server_browser()
	server_browser.visible = false
	main_panel.visible = true

func _on_create_pressed():
	var server_name = server_name_input.text.strip_edges()
	var port = int(port_input.value)
	
	if server_name.length() < 3:
		show_error("Server name must be at least 3 characters")
		return
		
	NetworkManager.set_player_name(player_name_input.text.strip_edges())
	
	if NetworkManager.create_server(server_name, port):
		create_button.disabled = true
		create_button.text = "Creating..."

func _on_create_back_pressed():
	create_server.visible = false
	main_panel.visible = true

func _on_server_created(port: int):
	print("Server created successfully on port ", port)
	# Switch to game lobby
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_server_joined(address: String):
	print("Joined server: ", address)
	# Switch to game lobby
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_server_disconnected():
	# Return to main menu
	main_panel.visible = true
	server_browser.visible = false
	create_server.visible = false
	
	# Reset button states
	browser_join_button.disabled = false
	browser_join_button.text = "Join"
	create_button.disabled = false
	create_button.text = "Create"
	
	show_error("Disconnected from server")

func _on_server_list_updated(servers: Array):
	server_list.clear()
	
	for server in servers:
		var text = "%s (%d/%d) - %s" % [
			server["name"],
			server["current_players"],
			server["max_players"],
			server["host"]
		]
		server_list.add_item(text)

func show_error(message: String):
	# Simple error display - you might want to create a proper dialog
	print("Error: ", message)
	# You could add an AcceptDialog here for better UX
