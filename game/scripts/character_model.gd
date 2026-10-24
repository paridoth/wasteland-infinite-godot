extends Node3D
## Kenney "Animated Characters: Survivors" rig (CC0) with a chosen skin and Idle/Run clips.
## Shared by the player and, later, NPCs and enemies.

const MODEL := preload("res://assets/kenney/survivors/characterMedium.fbx")
const CLIPS := {"idle": "res://assets/kenney/survivors/idle.fbx",
		"run": "res://assets/kenney/survivors/run.fbx"}
const HEIGHT := 1.75
const RIG_HEIGHT := 3.77  # Measured with tools/inspect.gd.

@export var skin := "survivorMaleB"

var anim := AnimationPlayer.new()


func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	model.scale = Vector3.ONE * HEIGHT / RIG_HEIGHT
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/kenney/survivors/%s.png" % skin)
		material.roughness = 0.9
		mesh.material_override = material
	var library := AnimationLibrary.new()
	for clip: String in CLIPS:
		var source: Node = load(CLIPS[clip]).instantiate()
		var player: AnimationPlayer = source.get_node("AnimationPlayer")
		var animation: Animation = player.get_animation(player.get_animation_list()[-1]).duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip, animation)
		source.free()
	model.add_child(anim)
	anim.add_animation_library("", library)
	anim.play("idle")


func play(clip: String) -> void:
	if anim.current_animation != clip:
		anim.play(clip, 0.15)
