class_name AvatarLoader
extends Node3D
## Builds the companion node for a profile, preferring a real GLB avatar and
## falling back to the procedural placeholder with an explicit, user-visible
## reason.
##
## Contract for whatever this returns (see docs/AVATAR_INTEGRATION.md):
##   apply_profile(CompanionProfile)
##   set_quality(int)
##   set_expression(String)
##   set_talking(float)
##   play_gesture(String) -> bool
##   set_look_at(Vector3) / clear_look_at()
##   get_capabilities() -> Dictionary
##   head_global_position() -> Vector3
##
## A GLB avatar is wrapped by `GlbAvatarAdapter`, which forwards the same calls
## to a Skeleton3D + AnimationPlayer + blend shapes when the model has them.

signal avatar_ready(kind: String)
signal fallback_used(reason: String)

var current: Node3D = null
var used_fallback: bool = true
var fallback_reason: String = "No avatar loaded yet."
var capabilities: Dictionary = {}
var active_descriptor: Dictionary = {}


## Replaces the current avatar with the one the profile asks for.
func load_for_profile(profile: CompanionProfile, quality_level: int = 1) -> Node3D:
	_clear_current()
	active_descriptor = {}
	used_fallback = false
	fallback_reason = ""

	var requested_id := ""
	if profile != null:
		requested_id = str(profile.appearance.get("avatar_id", ""))

	if not requested_id.is_empty():
		var descriptor := AvatarCatalog.find_by_id(requested_id)
		if descriptor.is_empty():
			used_fallback = true
			fallback_reason = "Avatar '%s' is not installed." % requested_id
		else:
			var node := _build_from_descriptor(descriptor, profile, quality_level)
			if node != null:
				current = node
				add_child(current)
				capabilities = _capabilities_of(current)
				avatar_ready.emit(str(capabilities.get("kind", "unknown")))
				return current
			used_fallback = true
			if fallback_reason.is_empty():
				fallback_reason = "Avatar '%s' could not be loaded." % requested_id
	else:
		used_fallback = true
		fallback_reason = "No GLB avatar selected; using the built-in rigged companion."

	current = _build_procedural(profile, quality_level)
	add_child(current)
	capabilities = _capabilities_of(current)
	if used_fallback:
		fallback_used.emit(fallback_reason)
	avatar_ready.emit(str(capabilities.get("kind", "rigged")))
	return current


func _clear_current() -> void:
	if current != null and is_instance_valid(current):
		if current.get_parent() == self:
			remove_child(current)
		current.queue_free()
	current = null


func _build_from_descriptor(descriptor: Dictionary, profile: CompanionProfile, quality_level: int) -> Node3D:
	if not bool(descriptor.get("valid", false)):
		fallback_reason = str(descriptor.get("problem", "Avatar is not usable."))
		return null

	var path := str(descriptor["path"])
	var scene_root := _instantiate_avatar(path)
	if scene_root == null:
		fallback_reason = "Could not read '%s'. Re-export it as GLB (glTF 2.0 binary)." % path.get_file()
		return null

	if not (scene_root is Node3D):
		scene_root.queue_free()
		fallback_reason = "Avatar root node is not a 3D node."
		return null

	active_descriptor = descriptor
	var adapter := GlbAvatarAdapter.new()
	adapter.name = "AvatarAdapter"
	adapter.setup(scene_root as Node3D, descriptor)
	adapter.apply_profile(profile)
	adapter.set_quality(quality_level)
	return adapter


## Instantiates a .glb/.gltf from either res:// (imported) or user:// (runtime).
func _instantiate_avatar(path: String) -> Node3D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var resource := load(path)
		if resource is PackedScene:
			var instance := (resource as PackedScene).instantiate()
			return instance as Node3D

	# Runtime import: works for files the editor never saw (user-installed
	# avatars), and as a fallback for a .glb that is present but not imported.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		return null
	var generated := document.generate_scene(state)
	return generated as Node3D


func _build_procedural(profile: CompanionProfile, quality_level: int) -> Node3D:
	var avatar := RiggedAvatar.new()
	avatar.name = "RiggedAvatar"
	avatar.preset_detail(int(QualityPresets.for_level(quality_level).get("mesh_detail", 1)))
	avatar.apply_profile(profile)
	return avatar


func _capabilities_of(avatar: Node3D) -> Dictionary:
	if avatar != null and avatar.has_method("get_capabilities"):
		return avatar.get_capabilities()
	return {
		"kind": "unknown",
		"rigged": false,
		"blendshapes": false,
		"animations": [],
		"expressions": [],
		"gestures": [],
		"lip_sync": "none",
		"notes": "Avatar does not implement the Waifu World avatar API.",
	}


# --------------------------------------------------------------------------
# GLB adapter
# --------------------------------------------------------------------------

## Wraps an arbitrary imported GLB scene so it satisfies the avatar API.
##
## It maps what actually exists in the model: a Skeleton3D for rigged models,
## an AnimationPlayer for clips, and ARKit-style blend shapes for expressions
## and lip-sync. Anything the model lacks is reported honestly in
## `get_capabilities()` and quietly ignored instead of pretending to work.
class GlbAvatarAdapter extends Node3D:
	const BLENDSHAPE_ALIASES := {
		"blink": ["eyeBlinkLeft", "eyesClosed", "blink", "eye_blink_L"],
		"smile": ["mouthSmile", "mouthSmileLeft", "smile"],
		"mouth_open": ["jawOpen", "mouthOpen", "viseme_aa"],
		"brow_raise": ["browInnerUp", "browOuterUpLeft", "eyebrowUp"],
		"look_up": ["eyeLookUpLeft", "eyeLookUpRight"],
	}

	var descriptor: Dictionary = {}
	var model: Node3D = null
	var skeleton: Skeleton3D = null
	var animation_player: AnimationPlayer = null
	var face_meshes: Array = []
	var animation_names: Array = []

	var _blink_time: float = 2.5
	var _blink_value: float = 0.0
	var _talking: float = 0.0
	var _expression: String = "neutral"
	var _has_blendshapes: bool = false


	func setup(scene_root: Node3D, source_descriptor: Dictionary) -> void:
		descriptor = source_descriptor
		model = scene_root
		model.name = "Model"
		add_child(model)

		_scale_to_height(float(descriptor.get("height_meters", 1.65)))
		_discover()

	func _scale_to_height(target_height: float) -> void:
		var bounds := _measure(model)
		if bounds.size.y <= 0.01:
			return
		var factor := target_height / bounds.size.y
		# Ignore absurd scale factors from broken exports.
		if factor > 0.05 and factor < 20.0:
			model.scale = Vector3.ONE * factor

	func _measure(node: Node3D) -> AABB:
		var combined := AABB()
		var first := true
		for mesh_instance in _find_mesh_instances(node):
			var box: AABB = mesh_instance.get_aabb()
			# Convert into model space.
			box = mesh_instance.transform * box
			if first:
				combined = box
				first = false
			else:
				combined = combined.merge(box)
		return combined

	func _discover() -> void:
		skeleton = _find_first(model, "Skeleton3D") as Skeleton3D
		animation_player = _find_first(model, "AnimationPlayer") as AnimationPlayer
		face_meshes.clear()
		for mesh_instance in _find_mesh_instances(model):
			if mesh_instance.mesh != null and mesh_instance.mesh.get_blend_shape_count() > 0:
				face_meshes.append(mesh_instance)

		_has_blendshapes = not face_meshes.is_empty()
		animation_names.clear()
		if animation_player != null:
			animation_names = animation_player.get_animation_list()
			var idle := str(descriptor.get("idle_animation", "Idle"))
			for candidate in [idle, "Idle", "idle", "Breathing", "rest"]:
				if animation_names.has(candidate):
					animation_player.play(candidate)
					break

	func _find_first(node: Node, type_name: String) -> Node:
		if node.is_class(type_name):
			return node
		for child in node.get_children():
			var found := _find_first(child, type_name)
			if found != null:
				return found
		return null

	func _find_mesh_instances(node: Node) -> Array:
		var found: Array = []
		if node is MeshInstance3D:
			found.append(node)
		for child in node.get_children():
			found.append_array(_find_mesh_instances(child))
		return found

	# -- avatar API ------------------------------------------------------

	func apply_profile(_profile: CompanionProfile) -> void:
		# A GLB carries its own materials and textures; recolouring it would
		# require per-model material names, so nothing is applied here. The
		# editor tells the user which fields only affect the placeholder.
		pass

	func set_quality(level: int) -> void:
		var preset := QualityPresets.for_level(level)
		var shadows := bool(preset.get("shadows", false))
		for mesh_instance in _find_mesh_instances(self):
			mesh_instance.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)

	func set_expression(expression_name: String) -> void:
		_expression = expression_name
		if not _has_blendshapes:
			return
		var smile := 0.0
		var brow := 0.0
		match expression_name:
			"smile", "laugh":
				smile = 1.0
			"sad":
				smile = -0.6
			"surprised":
				brow = 1.0
			_:
				pass
		_set_blendshape("smile", maxf(smile, 0.0))
		_set_blendshape("brow_raise", brow)

	func set_talking(amount: float) -> void:
		_talking = clampf(amount, 0.0, 1.0)
		if _has_blendshapes:
			_set_blendshape("mouth_open", _talking)

	func play_gesture(_gesture_name: String) -> bool:
		# Gestures need model-specific clips; only play a clip if it exists.
		if animation_player == null:
			return false
		for candidate in ["Wave", "wave", "Greeting", "Gesture"]:
			if animation_names.has(candidate):
				animation_player.play(candidate)
				return true
		return false

	func set_look_at(_world_position: Vector3) -> void:
		pass

	func clear_look_at() -> void:
		pass

	func head_global_position() -> Vector3:
		if skeleton != null:
			var bone_count := skeleton.get_bone_count()
			for index in bone_count:
				if skeleton.get_bone_name(index).to_lower().contains("head"):
					return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		return global_position + Vector3(0, 1.6, 0)

	func get_capabilities() -> Dictionary:
		return {
			"kind": "glb",
			"rigged": skeleton != null,
			"blendshapes": _has_blendshapes,
			"animations": animation_names,
			"expressions": ["neutral", "smile", "sad", "surprised"] if _has_blendshapes else [],
			"gestures": ["wave"] if animation_names.has("Wave") or animation_names.has("wave") else [],
			"lip_sync": "blendshape" if _has_blendshapes else "none",
			"notes": "Loaded from %s" % str(descriptor.get("path", "?")),
		}

	func _process(delta: float) -> void:
		if not _has_blendshapes:
			return
		_blink_time -= delta
		if _blink_time <= 0.0:
			_blink_value = 1.0
			_blink_time = randf_range(2.0, 5.5)
		_blink_value = maxf(0.0, _blink_value - delta * 8.0)
		_set_blendshape("blink", _blink_value)

	func _set_blendshape(alias: String, value: float) -> void:
		var names: Array = BLENDSHAPE_ALIASES.get(alias, [])
		for mesh_instance in face_meshes:
			var mesh: Mesh = mesh_instance.mesh
			for index in mesh.get_blend_shape_count():
				var shape_name: String = str(mesh.get_blend_shape_name(index))
				for candidate in names:
					if shape_name.findn(candidate) >= 0:
						mesh_instance.set_blend_shape_value(index, clampf(value, 0.0, 1.0))
						break
