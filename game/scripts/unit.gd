extends Node3D
## A grid-bound character: the player, NPCs and enemies. Movement is cell-to-cell so
## real-time exploration and turn-based AP combat share the same paths.

signal arrived

const Flicker := preload("res://scripts/flicker.gd")
const CharacterModel := preload("res://scripts/character_model.gd")

@export var display_name := "Wanderer"
@export var skin := "survivorMaleB"
@export var is_player := false
@export var hostile := false
@export var speed := 4.0
@export var max_hp := 30
@export var max_ap := 8
@export var skill := 75  ## Weapon skill, percent.
@export var armor_class := 5
@export var weapon := {"name": "10mm Pistol", "ap": 4, "min": 4, "max": 11, "range": 14.0}

var grid: AStarGrid2D
var cell := Vector2i.ZERO
var path: Array[Vector2i] = []
var hp: int
var ap: int
var model: CharacterModel


static func to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0, c.y + 0.5)


func _ready() -> void:
	hp = max_hp
	ap = max_ap
	model = CharacterModel.new()
	model.skin = skin
	add_child(model)
	if is_player:
		var torch := Flicker.new()
		torch.light_color = Color(1.0, 0.7, 0.4)
		torch.omni_range = 8.0
		torch.base_energy = 1.6
		torch.shadow_enabled = true
		torch.position = Vector3(0, 2.6, 0)
		add_child(torch)


func alive() -> bool:
	return hp > 0


func moving() -> bool:
	return not path.is_empty()


func place(c: Vector2i) -> void:
	cell = c
	path.clear()
	position = to_world(c)


## Real-time movement: retarget mid-walk, getting as close as possible to blocked targets.
func move_to(target: Vector2i) -> void:
	if not grid.is_in_boundsv(target):
		return
	if not path.is_empty() and path[-1] == target:
		return
	var from := path[0] if not path.is_empty() else cell
	var route := grid.get_id_path(from, target, true)
	path.clear()
	path.append_array(route)
	if not path.is_empty() and path[0] == cell:
		path.pop_front()


## Follow an already-computed route (combat). Await `arrived` for completion.
func walk(route: Array[Vector2i]) -> void:
	path = route.duplicate()
	if path.is_empty():
		arrived.emit.call_deferred()


## Finish the step in progress, then stop.
func halt() -> void:
	if path.size() > 1:
		path.resize(1)


func face(target: Vector2i) -> void:
	var d := to_world(target) - position
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		path.clear()
		model.anim.pause()
		var fall := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(model, "rotation:x", -PI / 2, 0.45)
		fall.parallel().tween_property(model, "position:y", 0.15, 0.45)
	else:
		var flinch := create_tween()
		flinch.tween_property(model, "position:y", 0.12, 0.06)
		flinch.tween_property(model, "position:y", 0.0, 0.1)


func _process(delta: float) -> void:
	if is_player:
		RenderingServer.global_shader_parameter_set("player_pos", position)
	if not alive():
		return
	if path.is_empty():
		model.play("idle")
		return
	model.play("run")
	var goal := to_world(path[0])
	face(path[0])
	position = position.move_toward(goal, speed * delta)
	if position.is_equal_approx(goal):
		cell = path.pop_front()
		if path.is_empty():
			arrived.emit()
