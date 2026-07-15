extends Node2D

# Constants to control the movement
const SPEED: float = 10.0          # Pixels per second
const TARGET_X: float = 0.0       # The X coordinate where the car should stop
const WAIT_TIME: float = 5.0       # Seconds to wait before showing the branch

# Constants for scene transition
const BRANCH_DISPLAY_TIME: float = 3.0   # How long to show the branch before starting the fadeout
const FADE_DURATION: float = 1.5         # How long the fadeout should take (in seconds)
# Exported PackedScene variable (Assign this in the Godot Inspector!)
@export var next_scene: PackedScene

# Reference to the car node (adjust the path if it's not a direct child)
@onready var car: Node2D = $car_1
@onready var branch: Node2D = $branch_1
@onready var transition_splash_screen: ColorRect = $transition_splash_screen

# A boolean variable to keep track of whether we've already started the wait timer
var reached_target: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Check if the car exists to avoid errors
	if car:
		# move_toward smoothly transitions from current X to TARGET_X 
		# at a maximum speed scaled by delta (time elapsed since last frame)
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
	
	# 4. Perform the fadeout
	# We create a Tween and target "modulate:a" (alpha channel of this script's node)
	# This smoothly fades this node and all of its children to transparent
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	
	# Wait until the transition animation actually finishes
	await fade_tween.finished
	
	# 5. Change to the new scene safely
	if next_scene:
		get_tree().change_scene_to_packed(next_scene)
	else:
		push_error("Next Scene is not assigned in the Inspector!")
