extends Node2D

# --- Cutscene Timings & Constants ---
const FADE_IN_DURATION: float = 3.5      # Time to reveal scene 2 from black
const WAIT_0_DISABLE_INPUT: float = 1.0  # Time to wait initially before crouch
const WAIT_3_CROUCH_DURATION: float = 2.0 # Wait while crouched
const WAIT_4_FLIP_LOOK: float = 1.5      # Wait after flipping the player's face
const RUN_DURATION: float = 2.5          # How long the player runs before gaining control

# --- Positions ---
const BEAR_TARGET_X_FAST: float = 1200.0 # X coordinate where the bear flees quickly

# --- Node References ---
@onready var player: CharacterBody2D = $player
@onready var bear: CharacterBody2D = $bear
@onready var camera: Camera2D = $Camera2D

# Splash overlay to handle the fade-in at the start of this level
@onready var transition_canvas_layer: CanvasLayer = $transition_splash_screen/CanvasLayer
@onready var fade_rect: ColorRect = $transition_splash_screen/CanvasLayer/ColorRect

func _ready() -> void:
	# Start the cinematic sequence
	run_cutscene()

# The master timeline function that handles steps sequentially
func run_cutscene() -> void:
	# ----------------------------------------------------
	# STEP 0: Lock Player Controls & Initialize Overlay
	# ----------------------------------------------------
	set_player_control(false)
	
	if fade_rect and transition_canvas_layer:
		transition_canvas_layer.visible = true
		fade_rect.modulate.a = 1.0 # Start fully covered
		
		# Fade OUT the black screen to reveal scene_2
		var reveal_tween = create_tween()
		reveal_tween.tween_property(fade_rect, "modulate:a", 0.0, FADE_IN_DURATION)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		await reveal_tween.finished
		transition_canvas_layer.visible = false

	# ----------------------------------------------------
	# STEP 1: Wait for a moment
	# ----------------------------------------------------
	await get_tree().create_timer(WAIT_0_DISABLE_INPUT).timeout

	# ----------------------------------------------------
	# STEP 2 & 3: Simulate crouching
	# ----------------------------------------------------
	if player:
		player.simulated_crouch = true # Virtally press down
	
	await get_tree().create_timer(WAIT_3_CROUCH_DURATION).timeout

	if player:
		player.simulated_crouch = false # Release crouch

	# ----------------------------------------------------
	# STEP 4: Flip player horizontally (Turn Left) & wait
	# ----------------------------------------------------
	if player:
		# Simulate tapping left for a split second to flip the character face
		player.simulated_left = true
		await get_tree().create_timer(0.1).timeout
		player.simulated_left = false
			
	await get_tree().create_timer(WAIT_4_FLIP_LOOK).timeout

	# ----------------------------------------------------
	# STEP 5: Wait briefly, then make the Bear flee quickly
	# ----------------------------------------------------
	#await get_tree().create_timer(0.5).timeout
	#
	#if bear:
		#var bear_run_tween = create_tween()
		#bear_run_tween.tween_property(bear, "global_position:x", BEAR_TARGET_X_FAST, 1.5)\
			#.set_trans(Tween.TRANS_QUAD)\
			#.set_ease(Tween.EASE_IN)
		#await bear_run_tween.finished
		#bear.visible = false 

	# ----------------------------------------------------
	# STEP 7: Pan camera back to Player & make Player run
	# ----------------------------------------------------
	if camera and player:
		# Smoothly slide camera back to focus on our player
		var cam_return_tween = create_tween()
		cam_return_tween.tween_property(camera, "global_position:x", player.global_position.x, 2.0)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		await cam_return_tween.finished

		# Attach camera to player so it follows during the run
		camera.reparent(player)
		
		# Virtally hold "Right" to make them run naturally
		player.simulated_right = true
		
		# Wait for the duration of the scripted run
		await get_tree().create_timer(RUN_DURATION).timeout

	# ----------------------------------------------------
	# FINISH: Return control to Player
	# ----------------------------------------------------
	set_player_control(true)


# Helper function to enable/disable your gameplay input script
func set_player_control(has_control: bool) -> void:
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(has_control)
