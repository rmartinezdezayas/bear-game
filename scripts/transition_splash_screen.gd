extends Node2D

@export var default_fade_duration: float = 0.3

@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var fade_rect: ColorRect = $CanvasLayer/ColorRect

func _ready() -> void:
	prepare()

func prepare() -> void:
	if fade_rect:
		fade_rect.modulate.a = 0.0
	if canvas_layer:
		canvas_layer.visible = false

func fade_in(duration: float = default_fade_duration) -> void:
	if not canvas_layer or not fade_rect:
		return

	canvas_layer.visible = true
	fade_rect.modulate.a = 1.0

	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	canvas_layer.visible = false

func fade_out(duration: float = default_fade_duration) -> void:
	if not canvas_layer or not fade_rect:
		return

	canvas_layer.visible = true
	fade_rect.modulate.a = 0.0

	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished
