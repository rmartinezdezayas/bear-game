extends CharacterBody2D


const SPEED = 50.0
const JUMP_VELOCITY = -250.0
const CROUCH_VELOCITY_MULTIPLIER = 0.5

@onready var animation_tree : AnimationTree = $AnimationTree
var state_machine

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("left", "right")
	# Use the crouch multiplier when crouched
	var crouch_multiplier = CROUCH_VELOCITY_MULTIPLIER if Input.is_action_pressed("crouch") else 1
	
	if direction:
		velocity.x = direction * SPEED * crouch_multiplier
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * crouch_multiplier)

	move_and_slide()
	animations()

func animations():
	# 1. Flip player sprite logic
	var is_moving = (Input.is_action_pressed("right") or Input.is_action_pressed("left")) and (!Input.is_action_pressed("right") or !Input.is_action_pressed("left"))
	if Input.is_action_pressed("right"):
		$Sprite2D.flip_h = false
	elif Input.is_action_pressed("left"):
		$Sprite2D.flip_h = true
	
	# 2. Air/Jump state logic (Highest Priority)
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump-max")
		else:
			state_machine.travel("fall")
			
	# 3. Ground state logic (Only runs when is_on_floor() is true)
	else:
		if Input.is_action_pressed("crouch"):
			if is_moving:
				state_machine.travel("crouch-walk")
			else:
				state_machine.travel("crouch-idle")
		else:
			if is_moving:
				state_machine.travel("run")
			else:
				state_machine.travel("idle")
