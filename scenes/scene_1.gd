extends Node2D

# Constants to control the movement
const SPEED: float = 10.0          # Pixels per second
const TARGET_X: float = 0.0       # The X coordinate where the car should stop
const WAIT_TIME: float = 5.0       # Seconds to wait before showing the branch

# Constants for scene transition
const BRANCH_DISPLAY_TIME: float = 3.0   # How long to show the branch before starting the fadeout
const FADE_DURATION: float = 0.3         # How long the fadeout should take (in seconds)

# Exported PackedScene variable (Assign this in the Godot Inspector!)
@export var next_scene: PackedScene

# Reference to your game nodes
@onready var car: Node2D = $car_1
@onready var branch: Node2D = $branch_1

# References to your nested transition nodes
@onready var transition_splash_screen: Node2D = $transition_splash_screen
@onready var transition_canvas_layer: CanvasLayer = $transition_splash_screen/CanvasLayer
@onready var fade_rect: ColorRect = $transition_splash_screen/CanvasLayer/ColorRect

# A boolean variable to keep track of whether we've already started the wait timer
var reached_target: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Make sure the overlay is fully transparent and hidden on game launch
	if fade_rect:
		fade_rect.modulate.a = 0.0
	if transition_canvas_layer:
		transition_canvas_layer.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Check if the car exists to avoid errors
	if car:
		# move_toward smoothly transitions from current X to TARGET_X 
		# at a maximum speed scaled by delta
		car.position.x = move_toward(car.position.x, TARGET_X, SPEED * delta)
		
		# Check if the car has arrived and we haven't triggered the timer yet
		if car.position.x == TARGET_X and not reached_target:
			reached_target = true
			trigger_branch_appearance()
			
# Handles waiting, showing the branch, fading out, and changing scenes
func trigger_branch_appearance() -> void:
	# 1. Wait the initial wait time
	await get_tree().create_timer(WAIT_TIME).timeout
	
	# 2. Turn on visibility of the branch
	if branch:
		branch.visible = true
		
	# 3. Wait while the branch is on screen
	await get_tree().create_timer(BRANCH_DISPLAY_TIME).timeout
	
	# 4. Perform the fade in of the custom transition splash screen
	if transition_canvas_layer and fade_rect:
		# Show the CanvasLayer so the color rect becomes active
		transition_canvas_layer.visible = true
		
		# We target "fade_rect" directly to smoothly animate its transparency to 1.0
		var fade_tween = create_tween()
		fade_tween.tween_property(fade_rect, "modulate:a", 1.0, FADE_DURATION)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)
		
		# Wait until the screen is completely covered by your custom color
		await fade_tween.finished
	else:
		push_warning("transition_splash_screen structure is missing! Changing scenes immediately.")

	# 5. Change to the new scene safely while the screen is covered
	if next_scene:
		get_tree().change_scene_to_packed(next_scene)
	else:
		push_error("Next Scene is not assigned in the Inspector!")
