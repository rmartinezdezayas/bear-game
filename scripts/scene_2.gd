extends Node2D

# --- Cutscene Timings & Constants ---
const FADE_IN_DURATION: float = 3.5      # Time to reveal scene 2 from black
const WAIT_0_DISABLE_INPUT: float = 1.0  # Time to wait initially before crouch
const WAIT_3_CROUCH_DURATION: float = 2.0 # Wait while crouched
const WAIT_4_FLIP_LOOK: float = 1.5      # Wait after flipping the player's face
const BEAR_SLOW_SPEED: float = 1.0     # Slow move speed of the bear
const BEAR_FAST_SPEED: float = 2.0    # Quick move speed of the bear
const RUN_DURATION: float = 2.5          # How long the player runs before gaining control

# --- Positions ---
const BEAR_TARGET_X_SLOW: float = 600.0  # X coordinate where the bear wanders slowly
const BEAR_TARGET_X_FAST: float = 1200.0 # X coordinate where the bear flees quickly
const PLAYER_RUN_TARGET_X: float = 400.0 # How far right the player runs in cutscene

# --- Node References ---
@onready var player: CharacterBody2D = $player
@onready var bear: CharacterBody2D = $bear
@onready var camera: Camera2D = $Camera2D

# AnimationTree and StateMachine setup for the Player
@onready var anim_tree: AnimationTree = $Player/AnimationTree
var anim_state_machine # Will hold the playback resource

# Splash overlay to handle the fade-in at the start of this level
@onready var transition_canvas_layer: CanvasLayer = $transition_splash_screen/CanvasLayer
@onready var fade_rect: ColorRect = $transition_splash_screen/CanvasLayer/ColorRect

func _ready() -> void:
	# Fetch the animation playback controller
	if anim_tree:
		anim_state_machine = anim_tree.get("parameters/playback")
		
	# Start the cinematic sequence
	run_cutscene()


# The master timeline function that handles steps 0-7 sequentially
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
	# STEP 2: Play crouch-idle animation
	# ----------------------------------------------------
	if anim_state_machine:
		anim_state_machine.travel("crouch-idle")

	# ----------------------------------------------------
	# STEP 3: Wait while crouched
	# ----------------------------------------------------
	await get_tree().create_timer(WAIT_3_CROUCH_DURATION).timeout

	# ----------------------------------------------------
	# STEP 4: Flip player horizontally & wait
	# ----------------------------------------------------
	if player:
		# If you use a Sprite2D inside Player, toggle its flip_h property
		var sprite = player.get_node_or_null("Sprite2D")
		if sprite:
			sprite.flip_h = !sprite.flip_h
		else:
			# Alternative: Rotate/Scale the player node to flip
			player.scale.x = -abs(player.scale.x)
			
	await get_tree().create_timer(WAIT_4_FLIP_LOOK).timeout

	# ----------------------------------------------------
	# STEP 5: Wait briefly, then make the Bear flee quickly
	# ----------------------------------------------------
	await get_tree().create_timer(0.5).timeout
	
	if bear:
		var bear_run_tween = create_tween()
		bear_run_tween.tween_property(bear, "global_position:x", BEAR_TARGET_X_FAST, 1.5)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_IN)
		await bear_run_tween.finished
		
		# (Optional) Hide or queue_free the bear once it is far off screen
		bear.visible = false 

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

		# Put Player in run state and move them to the right
		if anim_state_machine:
			# Make sure your Sprite2D scale/flip faces right first
			var sprite = player.get_node_or_null("Sprite2D")
			if sprite:
				sprite.flip_h = false # Face right
			else:
				player.scale.x = abs(player.scale.x)
				
			anim_state_machine.travel("run")
			
		# Auto-run player to the right
		var player_run_tween = create_tween()
		player_run_tween.tween_property(player, "global_position:x", PLAYER_RUN_TARGET_X, RUN_DURATION)\
			.set_trans(Tween.TRANS_LINEAR)
		await player_run_tween.finished

	# ----------------------------------------------------
	# FINISH: Return control to Player
	# ----------------------------------------------------
	set_player_control(true)


# Helper function to enable/disable your gameplay input script
func set_player_control(has_control: bool) -> void:
	if player:
		# E.g., toggling a custom variable in your movement script:
		if player.has_method("set_input_enabled"):
			player.call("set_input_enabled", has_control)
		else:
			# Alternative simple approach: toggle the physics loop itself
			player.set_physics_process(has_control)
			player.set_process_unhandled_input(has_control)
			
		# If we are giving control back, make sure the player transitions back to an idle state
		if has_control and anim_state_machine:
			anim_state_machine.travel("idle")
