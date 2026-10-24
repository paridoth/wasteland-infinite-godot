extends SceneTree
## Dev helper: print node trees, animations and sizes of imported models.
## ~/tools/godot --headless --path game -s res://tools/inspect.gd -- res://path.fbx ...

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var node: Node = load(path).instantiate()
		print("== ", path)
		_dump(node, "  ")
		var aabb := AABB()
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge(mesh.get_aabb())
		print("  size ", aabb.size)
		for player in node.find_children("*", "AnimationPlayer", true, false):
			print("  anims ", player.get_animation_list())
		node.free()
	quit()


func _dump(node: Node, indent: String) -> void:
	print(indent, node.name, " <", node.get_class(), ">")
	if indent.length() < 10:
		for child in node.get_children():
			_dump(child, indent + "  ")
