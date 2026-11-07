class_name RiggedAvatar
extends Node3D
## The built-in companion: a real rig, not a pile of floating primitives.
##
## Structure:
##   RiggedAvatar
##   ├── Skeleton3D          19 bones (hips → spine → chest → neck → head → jaw,
##   │                       clavicles, arms, legs)
##   ├── Body (MeshInstance3D)
##   │     one skinned ArrayMesh, one surface per material, every vertex bound
##   │     to a bone with real ARRAY_BONES / ARRAY_WEIGHTS data
##   ├── AnimationPlayer     authored keyframe clips (idle, wave, nod, shake, walk)
##   └── Face                eyes, brows, mouth on BoneAttachment3D nodes, so they
##                           are carried by the head and jaw bones
##
## What is genuinely rigged: the body mesh deforms from bone transforms through a
## Skin, the head and jaw carry the face, and every gesture is a keyframed
## Animation clip, not a per-frame lerp on detached meshes.
##
## What is still stylised: skinning is rigid per part (one bone per vertex, like
## a cel-shaded figurine) and there are no facial blend shapes — the face is
## driven by moving the eye/brow/mouth meshes and by the jaw bone.
##
## Design: a fan-style anime schoolgirl (long blonde hair with pink tips, white
## shirt, navy tie, blue plaid skirt, choker, sneakers). It is an original
## low-poly interpretation, not an official asset.

const EXPRESSIONS := {
	"neutral": {"curve": 0.15, "open": 0.0, "brow": 0.0, "brow_inner": 0.0, "eye": 1.0, "pitch": 0.0, "roll": 0.0},
	"smile": {"curve": 0.95, "open": 0.05, "brow": 0.12, "brow_inner": 0.0, "eye": 0.9, "pitch": -0.03, "roll": 0.03},
	"listening": {"curve": 0.35, "open": 0.03, "brow": 0.28, "brow_inner": 0.0, "eye": 1.08, "pitch": 0.02, "roll": 0.05},
	"thinking": {"curve": -0.05, "open": 0.0, "brow": -0.1, "brow_inner": 0.3, "eye": 0.95, "pitch": 0.06, "roll": -0.07},
	"sad": {"curve": -0.75, "open": 0.0, "brow": -0.15, "brow_inner": 0.85, "eye": 0.85, "pitch": 0.1, "roll": 0.0},
	"surprised": {"curve": 0.0, "open": 0.7, "brow": 0.95, "brow_inner": 0.0, "eye": 1.18, "pitch": -0.05, "roll": 0.0},
	"laugh": {"curve": 1.0, "open": 0.5, "brow": 0.3, "brow_inner": 0.0, "eye": 0.62, "pitch": -0.1, "roll": 0.02},
	"speaking": {"curve": 0.4, "open": 0.25, "brow": 0.1, "brow_inner": 0.0, "eye": 0.95, "pitch": -0.02, "roll": 0.0},
}

const GESTURES := ["wave", "nod", "shake"]

## Bone table: offset is relative to the parent bone (rest pose, identity basis).
const BONES := [
	{"name": "hips", "parent": "", "offset": Vector3(0.0, 0.95, 0.0)},
	{"name": "spine", "parent": "hips", "offset": Vector3(0.0, 0.10, 0.0)},
	{"name": "chest", "parent": "spine", "offset": Vector3(0.0, 0.18, 0.0)},
	{"name": "neck", "parent": "chest", "offset": Vector3(0.0, 0.22, 0.0)},
	{"name": "head", "parent": "neck", "offset": Vector3(0.0, 0.09, 0.0)},
	{"name": "jaw", "parent": "head", "offset": Vector3(0.0, -0.035, 0.03)},
	{"name": "shoulder.L", "parent": "chest", "offset": Vector3(0.05, 0.185, 0.0)},
	{"name": "upperarm.L", "parent": "shoulder.L", "offset": Vector3(0.075, 0.0, 0.0)},
	{"name": "forearm.L", "parent": "upperarm.L", "offset": Vector3(0.0, -0.24, 0.0)},
	{"name": "hand.L", "parent": "forearm.L", "offset": Vector3(0.0, -0.22, 0.0)},
	{"name": "shoulder.R", "parent": "chest", "offset": Vector3(-0.05, 0.185, 0.0)},
	{"name": "upperarm.R", "parent": "shoulder.R", "offset": Vector3(-0.075, 0.0, 0.0)},
	{"name": "forearm.R", "parent": "upperarm.R", "offset": Vector3(0.0, -0.24, 0.0)},
	{"name": "hand.R", "parent": "forearm.R", "offset": Vector3(0.0, -0.22, 0.0)},
	{"name": "thigh.L", "parent": "hips", "offset": Vector3(0.085, -0.04, 0.0)},
	{"name": "shin.L", "parent": "thigh.L", "offset": Vector3(0.0, -0.40, 0.0)},
	{"name": "foot.L", "parent": "shin.L", "offset": Vector3(0.0, -0.38, 0.0)},
	{"name": "thigh.R", "parent": "hips", "offset": Vector3(-0.085, -0.04, 0.0)},
	{"name": "shin.R", "parent": "thigh.R", "offset": Vector3(0.0, -0.40, 0.0)},
	{"name": "foot.R", "parent": "shin.R", "offset": Vector3(0.0, -0.38, 0.0)},
]

signal expression_changed(expression_name: String)
signal gesture_finished(gesture_name: String)
signal animation_started(animation_name: String)

var profile: CompanionProfile = null

var skeleton: Skeleton3D
var body: MeshInstance3D
var animation_player: AnimationPlayer
var face_root: BoneAttachment3D

var _detail: int = 1
var _build_key: String = ""
var _bone_world: Dictionary = {}
var _bone_index: Dictionary = {}
var _groups: Dictionary = {}
var _surface_vertex_base: int = 0

var _skin_mat: StandardMaterial3D
var _shirt_mat: StandardMaterial3D
var _tie_mat: StandardMaterial3D
var _skirt_mat: StandardMaterial3D
var _hair_mat: StandardMaterial3D
var _hair_tip_mat: StandardMaterial3D
var _eye_white_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _lip_mat: StandardMaterial3D
var _shoe_mat: StandardMaterial3D
var _sole_mat: StandardMaterial3D

var _eye_l: Node3D
var _eye_r: Node3D
var _lid_l: Node3D
var _lid_r: Node3D
var _brow_l: Node3D
var _brow_r: Node3D
var _mouth: Node3D
var _mouth_corner_l: Node3D
var _mouth_corner_r: Node3D

var _elapsed: float = 0.0
var _blink_timer: float = 2.0
var _blink_progress: float = -1.0
var _talk_target: float = 0.0
var _talk_current: float = 0.0
var _expression: String = "neutral"
var _face: Dictionary = {}
var _face_target: Dictionary = {}
var _look_target: Vector3 = Vector3.ZERO
var _look_enabled: bool = false
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0
var _gesture: String = ""
var _gesture_timer: float = 0.0


func _ready() -> void:
	randomize()
	_blink_timer = randf_range(1.5, 4.0)
	_face = (EXPRESSIONS["neutral"] as Dictionary).duplicate(true)
	_face_target = (EXPRESSIONS["neutral"] as Dictionary).duplicate(true)
	rebuild()


# --------------------------------------------------------------------------
# Public avatar API (identical to the GLB adapter contract)
# --------------------------------------------------------------------------

func apply_profile(new_profile: CompanionProfile) -> void:
	profile = new_profile
	if _compute_build_key() != _build_key:
		rebuild()
	else:
		_apply_materials()


func set_quality(level: int) -> void:
	preset_detail(int(QualityPresets.for_level(level).get("mesh_detail", 1)))


func preset_detail(detail: int) -> void:
	var clamped := clampi(detail, 0, 3)
	if clamped == _detail:
		return
	_detail = clamped
	if is_inside_tree():
		rebuild()


func set_expression(expression_name: String) -> void:
	var resolved := expression_name
	if not EXPRESSIONS.has(resolved):
		resolved = "neutral"
	_expression = resolved
	_face_target = (EXPRESSIONS[resolved] as Dictionary).duplicate(true)
	expression_changed.emit(resolved)


func current_expression() -> String:
	return _expression


## 0..1 mouth opening. Drives the jaw bone and the mouth meshes together.
func set_talking(amount: float) -> void:
	_talk_target = clampf(amount, 0.0, 1.0)


func is_talking() -> bool:
	return _talk_target > 0.01 or _talk_current > 0.01


func play_gesture(gesture_name: String) -> bool:
	if not GESTURES.has(gesture_name) or animation_player == null:
		return false
	if not animation_player.has_animation(gesture_name):
		return false
	_gesture = gesture_name
	_gesture_timer = animation_player.get_animation(gesture_name).length
	animation_player.play(gesture_name, 0.15)
	animation_started.emit(gesture_name)
	return true


## Plays a locomotion clip. `walk` is in place; it does not move the avatar.
func play_animation(animation_name: String, loop: bool = false) -> bool:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return false
	animation_player.play(animation_name, 0.2)
	if not loop:
		_gesture = animation_name
		_gesture_timer = animation_player.get_animation(animation_name).length
	animation_started.emit(animation_name)
	return true


func set_look_at(world_position: Vector3) -> void:
	_look_target = world_position
	_look_enabled = true


func clear_look_at() -> void:
	_look_enabled = false


func get_capabilities() -> Dictionary:
	return {
		"kind": "rigged",
		"rigged": skeleton != null,
		"blendshapes": false,
		"animations": animation_player.get_animation_list() if animation_player != null else [],
		"expressions": EXPRESSIONS.keys(),
		"gestures": GESTURES,
		"lip_sync": "jaw bone amplitude",
		"notes": "Built-in rigged companion: 20 bones, skinned mesh, keyframed clips. No facial blend shapes.",
	}


func head_global_position() -> Vector3:
	if skeleton == null:
		return global_position + Vector3(0, 1.6, 0)
	var index := skeleton.find_bone("head")
	if index < 0:
		return global_position + Vector3(0, 1.6, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func bone_names() -> Array:
	var names: Array = []
	if skeleton != null:
		for index in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(index))
	return names


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_key = _compute_build_key()
	_make_materials()

	_build_skeleton()
	_build_body()
	_build_face()
	_build_animations()

	_apply_materials()
	_apply_face(1.0)


func _compute_build_key() -> String:
	if profile == null:
		return "default|%d" % _detail
	return "%s|%s|%s|%d" % [profile.hair_style(), profile.outfit(), str(profile.height_scale()), _detail]


func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	_bone_world.clear()
	_bone_index.clear()

	for entry in BONES:
		var bone_name := str(entry["name"])
		var index := skeleton.add_bone(bone_name)
		_bone_index[bone_name] = index
		var parent_name := str(entry["parent"])
		if not parent_name.is_empty():
			skeleton.set_bone_parent(index, int(_bone_index[parent_name]))
		var offset: Vector3 = entry["offset"]
		skeleton.set_bone_rest(index, Transform3D(Basis(), offset))
		var parent_world: Vector3 = _bone_world.get(parent_name, Vector3.ZERO)
		_bone_world[bone_name] = parent_world + offset

	# Bones are created with their pose at the origin; without this the skin
	# collapses every vertex onto (0,0,0).
	skeleton.reset_bone_poses()

	var height := profile.height_scale() if profile != null else 1.0
	skeleton.scale = Vector3.ONE * height


func _bone_position(bone_name: String, local_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var base: Vector3 = _bone_world.get(bone_name, Vector3.ZERO)
	return base + local_offset


# --------------------------------------------------------------------------
# Skinned body
# --------------------------------------------------------------------------

func _build_body() -> void:
	_groups.clear()

	# --- skin ---------------------------------------------------------
	_add_part("skin", "head", _sphere(Vector3(0.215, 0.245, 0.208)), _bone_position("head", Vector3(0, 0.105, 0)))
	_add_part("skin", "jaw", _sphere(Vector3(0.128, 0.082, 0.128)), _bone_position("jaw", Vector3(0, -0.005, 0.008)))
	_add_part("skin", "neck", _capsule(0.043, 0.12), _bone_position("neck", Vector3(0, 0.040, 0)))
	_add_part("skin", "forearm.L", _capsule(0.036, 0.22), _bone_position("forearm.L", Vector3(0, -0.11, 0)))
	_add_part("skin", "forearm.R", _capsule(0.036, 0.22), _bone_position("forearm.R", Vector3(0, -0.11, 0)))
	_add_part("skin", "hand.L", _sphere(Vector3(0.07, 0.10, 0.045)), _bone_position("hand.L", Vector3(0, -0.05, 0)))
	_add_part("skin", "hand.R", _sphere(Vector3(0.07, 0.10, 0.045)), _bone_position("hand.R", Vector3(0, -0.05, 0)))
	_add_part("skin", "thigh.L", _capsule(0.076, 0.40), _bone_position("thigh.L", Vector3(0, -0.20, 0)))
	_add_part("skin", "thigh.R", _capsule(0.076, 0.40), _bone_position("thigh.R", Vector3(0, -0.20, 0)))
	_add_part("skin", "shin.L", _capsule(0.061, 0.38), _bone_position("shin.L", Vector3(0, -0.19, 0)))
	_add_part("skin", "shin.R", _capsule(0.061, 0.38), _bone_position("shin.R", Vector3(0, -0.19, 0)))

	# --- shirt --------------------------------------------------------
	_add_part("shirt", "spine", _capsule(0.125, 0.36), _bone_position("spine", Vector3(0, 0.10, 0)))
	_add_part("shirt", "chest", _sphere(Vector3(0.27, 0.17, 0.185)), _bone_position("chest", Vector3(0, 0.06, 0.01)))
	_add_part("shirt", "chest", _sphere(Vector3(0.155, 0.05, 0.13)), _bone_position("chest", Vector3(0, 0.222, 0)))
	_add_part("shirt", "shoulder.L", _sphere(Vector3(0.11, 0.10, 0.11)), _bone_position("shoulder.L", Vector3(0.02, 0, 0)))
	_add_part("shirt", "shoulder.R", _sphere(Vector3(0.11, 0.10, 0.11)), _bone_position("shoulder.R", Vector3(-0.02, 0, 0)))
	_add_part("shirt", "upperarm.L", _capsule(0.052, 0.23), _bone_position("upperarm.L", Vector3(0, -0.115, 0)))
	_add_part("shirt", "upperarm.R", _capsule(0.052, 0.23), _bone_position("upperarm.R", Vector3(0, -0.115, 0)))

	# --- tie ----------------------------------------------------------
	_add_part("tie", "chest", _box(Vector3(0.042, 0.19, 0.018)), _bone_position("chest", Vector3(0, -0.02, 0.118)))
	_add_part("tie", "chest", _box(Vector3(0.058, 0.034, 0.022)), _bone_position("chest", Vector3(0, 0.072, 0.116)))

	# --- skirt --------------------------------------------------------
	_add_part("skirt", "hips", _cone(0.168, 0.212, 0.22), _bone_position("hips", Vector3(0, -0.075, 0)))
	_add_part("skirt", "hips", _sphere(Vector3(0.275, 0.155, 0.20)), _bone_position("hips", Vector3(0, 0.015, 0)))

	# --- choker -------------------------------------------------------
	_add_part("dark", "neck", _cone(0.046, 0.046, 0.022), _bone_position("neck", Vector3(0, 0.015, 0)))
	# wrist bracelet (the reference has a black beaded band)
	_add_part("dark", "forearm.R", _cone(0.043, 0.043, 0.02), _bone_position("forearm.R", Vector3(0, -0.185, 0)))

	# --- hair ---------------------------------------------------------
	_add_part("hair", "head", _sphere(Vector3(0.238, 0.17, 0.226)), _bone_position("head", Vector3(0, 0.118, -0.010)))
	_add_part("hair", "head", _sphere(Vector3(0.226, 0.235, 0.18)), _bone_position("head", Vector3(0, 0.035, -0.062)))
	_add_part("hair", "head", _sphere(Vector3(0.212, 0.075, 0.105)), _bone_position("head", Vector3(0, 0.148, 0.072)))
	_add_part("hair", "head", _capsule(0.030, 0.26), _bone_position("head", Vector3(-0.107, -0.02, 0.030)))
	_add_part("hair", "head", _capsule(0.030, 0.26), _bone_position("head", Vector3(0.107, -0.02, 0.030)))
	# long back length, split into a blonde upper part and pink tips
	_add_part("hair", "head", _capsule(0.112, 0.34), _bone_position("head", Vector3(0, -0.13, -0.080)))
	_add_part("hair_tip", "head", _capsule(0.100, 0.26), _bone_position("head", Vector3(0, -0.38, -0.080)))
	_add_part("hair_tip", "head", _capsule(0.026, 0.10), _bone_position("head", Vector3(-0.108, -0.20, 0.030)))
	_add_part("hair_tip", "head", _capsule(0.026, 0.10), _bone_position("head", Vector3(0.108, -0.20, 0.030)))

	# --- shoes --------------------------------------------------------
	_add_part("shoe", "foot.L", _box(Vector3(0.115, 0.085, 0.235)), _bone_position("foot.L", Vector3(0, -0.015, 0.045)))
	_add_part("shoe", "foot.R", _box(Vector3(0.115, 0.085, 0.235)), _bone_position("foot.R", Vector3(0, -0.015, 0.045)))
	_add_part("sole", "foot.L", _box(Vector3(0.12, 0.03, 0.24)), _bone_position("foot.L", Vector3(0, -0.055, 0.045)))
	_add_part("sole", "foot.R", _box(Vector3(0.12, 0.03, 0.24)), _bone_position("foot.R", Vector3(0, -0.055, 0.045)))

	var mesh := ArrayMesh.new()
	for group_name in _groups.keys():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_material_for(str(group_name)))
		_surface_vertex_base = 0
		for part in _groups[group_name]:
			_append_part(st, part)
		st.commit(mesh)

	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skeleton = NodePath("../Skeleton3D")
	body.skin = skeleton.create_skin_from_rest_transforms()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _detail >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)


func _add_part(group: String, bone_name: String, mesh: Mesh, position: Vector3) -> void:
	if not _groups.has(group):
		_groups[group] = []
	_groups[group].append({
		"mesh": mesh,
		"bone": int(_bone_index.get(bone_name, 0)),
		"xform": Transform3D(Basis(), position),
	})


## Writes one primitive into the surface tool, tagging every vertex with its bone.
func _append_part(st: SurfaceTool, part: Dictionary) -> void:
	var mesh: Mesh = part["mesh"]
	var bone: int = part["bone"]
	var xform: Transform3D = part["xform"]
	# Primitive meshes expose get_mesh_arrays(); an already-baked ArrayMesh
	# (the non-uniformly scaled spheres) exposes surface arrays instead.
	var arrays: Array = mesh.get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)

	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]

	var bones := PackedInt32Array([bone, 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	var normal_basis := xform.basis.inverse().transposed()

	for i in vertices.size():
		st.set_normal((normal_basis * normals[i]).normalized())
		if i < uvs.size():
			st.set_uv(uvs[i])
		st.set_bones(bones)
		st.set_weights(weights)
		st.add_vertex(xform * vertices[i])

	if not indices.is_empty():
		for index in indices:
			st.add_index(_surface_vertex_base + index)
	_surface_vertex_base += vertices.size()


# --------------------------------------------------------------------------
# Face (carried by the head and jaw bones)
# --------------------------------------------------------------------------

func _build_face() -> void:
	face_root = BoneAttachment3D.new()
	face_root.name = "FaceRoot"
	face_root.bone_name = "head"
	skeleton.add_child(face_root)

	var head_origin := Vector3(0, 0.105, 0)  # skull centre in head-bone space

	_add_face_mesh(face_root, "EyeL", _sphere(Vector3(0.058, 0.055, 0.03)), head_origin + Vector3(-0.056, -0.008, 0.086), "eye_white")
	_add_face_mesh(face_root, "EyeR", _sphere(Vector3(0.058, 0.055, 0.03)), head_origin + Vector3(0.056, -0.008, 0.086), "eye_white")

	_eye_l = _face_group(face_root, "EyeGroupL", head_origin + Vector3(-0.056, -0.008, 0.086))
	_eye_r = _face_group(face_root, "EyeGroupR", head_origin + Vector3(0.056, -0.008, 0.086))
	for group in [_eye_l, _eye_r]:
		_add_face_mesh(group, "Iris", _sphere(Vector3(0.032, 0.040, 0.026)), Vector3(0, 0, 0.008), "eye")
		_add_face_mesh(group, "Pupil", _sphere(Vector3(0.016, 0.020, 0.018)), Vector3(0, 0, 0.014), "dark")
		_add_face_mesh(group, "Glint", _sphere(Vector3(0.012, 0.014, 0.011)), Vector3(-0.008, 0.012, 0.017), "eye_white")

	_lid_l = _face_group(face_root, "LidL", head_origin + Vector3(-0.056, 0.020, 0.086))
	_lid_r = _face_group(face_root, "LidR", head_origin + Vector3(0.056, 0.020, 0.086))
	_add_face_mesh(_lid_l, "LidMesh", _sphere(Vector3(0.056, 0.028, 0.032)), Vector3.ZERO, "skin")
	_add_face_mesh(_lid_r, "LidMesh", _sphere(Vector3(0.056, 0.028, 0.032)), Vector3.ZERO, "skin")

	_brow_l = _face_group(face_root, "BrowL", head_origin + Vector3(-0.058, 0.052, 0.086))
	_brow_r = _face_group(face_root, "BrowR", head_origin + Vector3(0.058, 0.052, 0.086))
	_add_face_mesh(_brow_l, "BrowMesh", _sphere(Vector3(0.052, 0.011, 0.013)), Vector3.ZERO, "hair")
	_add_face_mesh(_brow_r, "BrowMesh", _sphere(Vector3(0.052, 0.011, 0.013)), Vector3.ZERO, "hair")

	_add_face_mesh(face_root, "Nose", _sphere(Vector3(0.022, 0.03, 0.026)), head_origin + Vector3(0, -0.045, 0.088), "skin")

	_mouth = _face_group(face_root, "Mouth", head_origin + Vector3(0, -0.082, 0.085))
	_add_face_mesh(_mouth, "InnerMouth", _sphere(Vector3(0.055, 0.022, 0.02)), Vector3(0, 0, -0.004), "dark")
	_add_face_mesh(_mouth, "LipUpper", _sphere(Vector3(0.060, 0.012, 0.017)), Vector3(0, 0.007, 0.002), "lip")
	_add_face_mesh(_mouth, "LipLower", _sphere(Vector3(0.055, 0.014, 0.017)), Vector3(0, -0.009, 0.002), "lip")

	_mouth_corner_l = _face_group(_mouth, "CornerL", Vector3(-0.030, 0, 0))
	_mouth_corner_r = _face_group(_mouth, "CornerR", Vector3(0.030, 0, 0))
	_add_face_mesh(_mouth_corner_l, "CornerMesh", _sphere(Vector3(0.014, 0.014, 0.014)), Vector3.ZERO, "lip")
	_add_face_mesh(_mouth_corner_r, "CornerMesh", _sphere(Vector3(0.014, 0.014, 0.014)), Vector3.ZERO, "lip")

	# ears / earrings, the reference has a small hoop
	_add_face_mesh(face_root, "EarL", _sphere(Vector3(0.032, 0.055, 0.03)), head_origin + Vector3(-0.100, -0.010, 0.0), "skin")
	_add_face_mesh(face_root, "EarR", _sphere(Vector3(0.032, 0.055, 0.03)), head_origin + Vector3(0.100, -0.010, 0.0), "skin")


func _face_group(parent: Node3D, group_name: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	node.position = position
	parent.add_child(node)
	return node


func _add_face_mesh(parent: Node3D, node_name: String, mesh: Mesh, position: Vector3, group: String) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = node_name
	item.mesh = mesh
	item.position = position
	item.material_override = _material_for(group)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


# --------------------------------------------------------------------------
# Animation clips (real keyframes on real bones)
# --------------------------------------------------------------------------

func _build_animations() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)

	var library := AnimationLibrary.new()

	# Idle: weight shift, breathing through the spine, small head drift.
	library.add_animation("idle", _anim(4.0, true, [
		{"bone": "hips", "axis": Vector3(0, 0, 1), "keys": [[0.0, 0.0], [2.0, 1.2], [4.0, 0.0]]},
		{"bone": "spine", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [2.0, -1.4], [4.0, 0.0]]},
		{"bone": "chest", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [2.0, 1.0], [4.0, 0.0]]},
		{"bone": "head", "axis": Vector3(0, 1, 0), "keys": [[0.0, 0.0], [1.3, 2.5], [2.6, -1.5], [4.0, 0.0]]},
		{"bone": "upperarm.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [2.0, 2.0], [4.0, 0.0]]},
		{"bone": "upperarm.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [2.0, -2.0], [4.0, 0.0]]},
	]))

	# Wave: raise the right arm out and to the side, then oscillate the forearm.
	library.add_animation("wave", _anim(1.6, false, [
		{"bone": "upperarm.R", "axis": Vector3(0, 0, 1), "keys": [
			[0.0, 0.0], [0.35, -125.0], [1.2, -125.0], [1.6, 0.0]]},
		{"bone": "forearm.R", "axis": Vector3(0, 0, 1), "keys": [
			[0.0, 0.0], [0.35, -20.0], [0.55, -45.0], [0.75, -12.0], [0.95, -45.0], [1.15, -20.0], [1.6, 0.0]]},
		{"bone": "upperarm.L", "axis": Vector3(0, 0, 1), "keys": [[0.0, 0.0], [0.35, 8.0], [1.6, 0.0]]},
		{"bone": "head", "axis": Vector3(0, 0, 1), "keys": [[0.0, 0.0], [0.4, -4.0], [1.6, 0.0]]},
	]))

	# Nod / shake.
	library.add_animation("nod", _anim(1.0, false, [
		{"bone": "head", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [0.22, 11.0], [0.5, -2.0], [0.75, 9.0], [1.0, 0.0]]},
	]))
	library.add_animation("shake", _anim(1.0, false, [
		{"bone": "head", "axis": Vector3(0, 1, 0), "keys": [
			[0.0, 0.0], [0.18, 12.0], [0.42, -12.0], [0.66, 9.0], [1.0, 0.0]]},
	]))

	# Walk cycle, in place.
	library.add_animation("walk", _anim(1.1, true, [
		{"bone": "thigh.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, 22.0], [0.55, -22.0], [1.1, 22.0]]},
		{"bone": "thigh.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, -22.0], [0.55, 22.0], [1.1, -22.0]]},
		{"bone": "shin.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, -6.0], [0.3, -38.0], [0.55, -2.0], [1.1, -6.0]]},
		{"bone": "shin.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, -2.0], [0.55, -6.0], [0.85, -38.0], [1.1, -2.0]]},
		{"bone": "upperarm.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, -16.0], [0.55, 16.0], [1.1, -16.0]]},
		{"bone": "upperarm.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, 16.0], [0.55, -16.0], [1.1, 16.0]]},
		{"bone": "hips", "axis": Vector3(0, 0, 1), "keys": [[0.0, 0.0], [0.55, 2.0], [1.1, 0.0]]},
	]))

	# Sit: thighs forward, knees bent, hips lowered.
	library.add_animation("sit", _anim(1.2, false, [
		{"bone": "thigh.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [1.2, 82.0]]},
		{"bone": "thigh.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [1.2, 82.0]]},
		{"bone": "shin.L", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [1.2, -78.0]]},
		{"bone": "shin.R", "axis": Vector3(1, 0, 0), "keys": [[0.0, 0.0], [1.2, -78.0]]},
	]))

	animation_player.add_animation_library("", library)
	animation_player.play("idle")


func _anim(length: float, loop: bool, tracks: Array) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	for track in tracks:
		var bone_name := str(track["bone"])
		if not _bone_index.has(bone_name):
			continue
		var axis: Vector3 = track["axis"]
		var path := "Skeleton3D:" + bone_name
		var track_index := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track_index, path)
		animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
		for key in track["keys"]:
			var time := float(key[0])
			var degrees := float(key[1])
			var rotation := Quaternion(axis.normalized(), deg_to_rad(degrees))
			animation.track_insert_key(track_index, time, rotation)

	return animation


# --------------------------------------------------------------------------
# Per-frame: face, look-at, blink, jaw lip-sync
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if skeleton == null:
		return
	_elapsed += delta
	_update_blink(delta)
	_update_look(delta)
	_update_face(delta)
	_update_jaw(delta)

	if _gesture_timer > 0.0:
		_gesture_timer -= delta
		if _gesture_timer <= 0.0:
			var finished := _gesture
			_gesture = ""
			if animation_player != null:
				animation_player.play("idle", 0.25)
			gesture_finished.emit(finished)


func _update_blink(delta: float) -> void:
	if _blink_progress >= 0.0:
		_blink_progress += delta
		if _blink_progress > 0.20:
			_blink_progress = -1.0
			_blink_timer = randf_range(2.0, 5.5)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_progress = 0.0


func _blink_amount() -> float:
	if _blink_progress < 0.0:
		return 0.0
	return sin(clampf(_blink_progress / 0.20, 0.0, 1.0) * PI)


func _update_look(delta: float) -> void:
	var weight := clampf(delta * 4.0, 0.0, 1.0)
	if not _look_enabled:
		_head_yaw = lerpf(_head_yaw, 0.0, weight)
		_head_pitch = lerpf(_head_pitch, 0.0, weight)
		return

	var head_index := skeleton.find_bone("head")
	if head_index < 0:
		return
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_index)
	var local_target := head_world.affine_inverse() * _look_target
	var flat := Vector2(local_target.x, local_target.z).length()
	var yaw := atan2(local_target.x, maxf(local_target.z, 0.05))
	var pitch := -atan2(local_target.y, maxf(flat, 0.05))
	_head_yaw = lerpf(_head_yaw, clampf(yaw, -0.55, 0.55), weight)
	_head_pitch = lerpf(_head_pitch, clampf(pitch, -0.3, 0.28), weight)


func _update_face(delta: float) -> void:
	_talk_current = lerpf(_talk_current, _talk_target, minf(1.0, delta * 9.0))
	for key in _face_target.keys():
		var speed := 8.0 if key != "open" else 14.0
		_face[key] = lerpf(float(_face.get(key, 0.0)), float(_face_target[key]), minf(1.0, delta * speed))
	if _talk_current > 0.01:
		var wobble := 0.85 + sin(_elapsed * 13.0) * 0.15
		_face["open"] = clampf(_talk_current * wobble, 0.0, 1.0)
	_apply_face(delta)


func _apply_face(delta: float) -> void:
	if _eye_l == null:
		return
	var blink := _blink_amount()
	var eye_open := float(_face.get("eye", 1.0)) * (1.0 - blink * 0.95)
	var curve := float(_face.get("curve", 0.0))
	var open := clampf(float(_face.get("open", 0.0)), 0.0, 1.0)
	var brow := float(_face.get("brow", 0.0))
	var brow_inner := float(_face.get("brow_inner", 0.0))

	_eye_l.scale = Vector3(1.0, maxf(eye_open, 0.06), 1.0)
	_eye_r.scale = Vector3(1.0, maxf(eye_open, 0.06), 1.0)
	_lid_l.position.y = 0.020 - blink * 0.030
	_lid_r.position.y = 0.020 - blink * 0.030
	_brow_l.position.y = 0.052 + brow * 0.012
	_brow_r.position.y = 0.052 + brow * 0.012
	_brow_l.rotation.z = brow_inner * 0.30
	_brow_r.rotation.z = -brow_inner * 0.30
	_mouth.scale = Vector3(1.0 + curve * 0.26, 1.0 + open * 1.5, 1.0)
	_mouth_corner_l.position.y = curve * 0.009
	_mouth_corner_r.position.y = curve * 0.009

	# Look-at is applied to the neck, which no clip animates, so it adds to the
	# head motion from the animation instead of overwriting it.
	var neck_index := skeleton.find_bone("neck")
	if neck_index >= 0:
		var look := Quaternion.from_euler(Vector3(_head_pitch * 0.6, _head_yaw * 0.6, 0.0))
		var weight := clampf(delta * 10.0, 0.0, 1.0)
		var current := skeleton.get_bone_pose_rotation(neck_index)
		skeleton.set_bone_pose_rotation(neck_index, current.slerp(look, weight))


## Lip-sync: the jaw bone actually rotates, deforming the chin of the skinned mesh.
func _update_jaw(_delta: float) -> void:
	var jaw_index := skeleton.find_bone("jaw")
	if jaw_index < 0:
		return
	var open := clampf(_talk_current, 0.0, 1.0)
	var angle := deg_to_rad(lerpf(2.0, 16.0, open))
	skeleton.set_bone_pose_rotation(jaw_index, Quaternion(Vector3.RIGHT, angle))


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

func _make_materials() -> void:
	var skin := profile.skin_color() if profile != null else Color(0.94, 0.78, 0.70)
	var hair := profile.hair_color() if profile != null else Color(0.95, 0.82, 0.55)
	var tip := Color.from_string(str(profile.appearance.get("hair_tip_color", "#ef9db4")), Color(0.94, 0.62, 0.70)) if profile != null else Color(0.94, 0.62, 0.70)
	var eye := profile.eye_color() if profile != null else Color(0.78, 0.28, 0.36)
	var outfit := profile.outfit_color() if profile != null else Color(0.90, 0.92, 0.96)

	_skin_mat = _material(skin, 0.75)
	_shirt_mat = _material(outfit, 0.85)
	_tie_mat = _material(Color(0.13, 0.17, 0.28), 0.7)
	_skirt_mat = _material(Color(0.62, 0.74, 0.86), 0.85)
	_skirt_mat.albedo_texture = _plaid_texture(Color(0.62, 0.74, 0.86), Color(0.92, 0.95, 0.99), Color(0.55, 0.35, 0.30))
	_hair_mat = _material(hair, 0.5)
	_hair_tip_mat = _material(tip, 0.5)
	_eye_white_mat = _material(Color(0.99, 0.98, 0.99), 0.3)
	_eye_mat = _material(eye, 0.25)
	_dark_mat = _material(Color(0.12, 0.11, 0.14), 0.6)
	_lip_mat = _material(Color(0.78, 0.38, 0.44), 0.5)
	_shoe_mat = _material(Color(0.95, 0.94, 0.93), 0.6)
	_sole_mat = _material(Color(0.28, 0.26, 0.28), 0.8)


func _apply_materials() -> void:
	if _skin_mat == null or profile == null:
		return
	_skin_mat.albedo_color = profile.skin_color()
	_hair_mat.albedo_color = profile.hair_color()
	_shirt_mat.albedo_color = profile.outfit_color()
	_eye_mat.albedo_color = profile.eye_color()
	_hair_tip_mat.albedo_color = Color.from_string(
		str(profile.appearance.get("hair_tip_color", "#ef9db4")), Color(0.94, 0.62, 0.70))


func _material_for(group: String) -> Material:
	match group:
		"skin":
			return _skin_mat
		"shirt":
			return _shirt_mat
		"tie":
			return _tie_mat
		"skirt":
			return _skirt_mat
		"hair":
			return _hair_mat
		"hair_tip":
			return _hair_tip_mat
		"eye_white":
			return _eye_white_mat
		"eye":
			return _eye_mat
		"lip":
			return _lip_mat
		"shoe":
			return _shoe_mat
		"sole":
			return _sole_mat
		_:
			return _dark_mat


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if _detail <= 0 else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material


## Small procedural plaid so the skirt is patterned instead of flat blue.
func _plaid_texture(base: Color, line: Color, accent: Color) -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(base)
	for y in size:
		for x in size:
			var colour := base
			var vertical := x % 16 < 3
			var horizontal := y % 16 < 3
			if vertical or horizontal:
				colour = line
			if vertical and horizontal:
				colour = accent
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)


# --------------------------------------------------------------------------
# Primitive helpers (segments follow the graphics preset)
# --------------------------------------------------------------------------

func _segments() -> Vector2i:
	match _detail:
		0:
			return Vector2i(10, 5)
		1:
			return Vector2i(14, 7)
		2:
			return Vector2i(20, 10)
		_:
			return Vector2i(28, 14)


func _sphere(size: Vector3) -> ArrayMesh:
	var seg := _segments()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = seg.x
	sphere.rings = seg.y
	return _scale_mesh(sphere, size)


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var seg := _segments()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = seg.x
	mesh.rings = maxi(3, seg.y / 2)
	return mesh


func _cone(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var seg := _segments()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = seg.x
	mesh.rings = maxi(1, seg.y / 3)
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Bakes a non-uniform scale into a primitive's vertices.
func _scale_mesh(source: Mesh, scale_value: Vector3) -> ArrayMesh:
	var arrays: Array = source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		vertices[index] = vertices[index] * scale_value
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in normals.size():
		normals[index] = (normals[index] / scale_value).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
