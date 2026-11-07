class_name ProceduralAvatar
extends Node3D
## Parameter-driven placeholder companion, built entirely from real 3D meshes.
##
## HONESTY NOTE: this is not a rigged humanoid and it has no facial
## blendshapes. It is a low-poly stand-in that implements the same script API as
## a loaded GLB avatar (see docs/AVATAR_INTEGRATION.md) so the rest of the game
## does not change when a licensed rigged model is dropped into
## `assets/avatars/`. Its face is animated by moving and scaling real meshes:
## eyes narrow on blink, the jaw opens for lip-sync amplitude, brows and mouth
## corners shift per expression.
##
## What it really does:
##   - jointed hierarchy (hips/spine/chest/neck/head/shoulders/elbows)
##   - idle breathing + weight shift + head micro-motion
##   - randomised blinking with correct scale-relative eyelids
##   - amplitude driven mouth opening (used by the future voice stage)
##   - expression blending between neutral / smile / sad / surprised / laugh
##   - wave, nod and shake gestures
##   - head/eye look-at tracking
##   - LOD by graphics preset (mesh segment counts)

const EXPRESSIONS := {
	"neutral": {"curve": 0.15, "open": 0.0, "brow": 0.0, "brow_inner": 0.0, "eye": 1.0, "pitch": 0.0, "roll": 0.0},
	"smile": {"curve": 0.9, "open": 0.04, "brow": 0.12, "brow_inner": 0.0, "eye": 0.9, "pitch": -0.03, "roll": 0.03},
	"listening": {"curve": 0.35, "open": 0.03, "brow": 0.25, "brow_inner": 0.0, "eye": 1.08, "pitch": 0.02, "roll": 0.05},
	"thinking": {"curve": -0.05, "open": 0.0, "brow": -0.1, "brow_inner": 0.3, "eye": 0.95, "pitch": 0.06, "roll": -0.07},
	"sad": {"curve": -0.75, "open": 0.0, "brow": -0.15, "brow_inner": 0.85, "eye": 0.85, "pitch": 0.1, "roll": 0.0},
	"surprised": {"curve": 0.0, "open": 0.7, "brow": 0.95, "brow_inner": 0.0, "eye": 1.18, "pitch": -0.05, "roll": 0.0},
	"laugh": {"curve": 1.0, "open": 0.5, "brow": 0.3, "brow_inner": 0.0, "eye": 0.62, "pitch": -0.1, "roll": 0.02},
	"speaking": {"curve": 0.4, "open": 0.25, "brow": 0.1, "brow_inner": 0.0, "eye": 0.95, "pitch": -0.02, "roll": 0.0},
}

const GESTURES := ["wave", "nod", "shake"]

## Emitted when an expression blend finishes (or immediately for unknown names).
signal expression_changed(expression_name: String)
signal gesture_finished(gesture_name: String)

var profile: CompanionProfile = null

var _detail: int = 1
var _build_key: String = ""

var _body: Node3D
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _forearm_l: Node3D
var _forearm_r: Node3D
var _eye_l: Node3D
var _eye_r: Node3D
var _lid_l: Node3D
var _lid_r: Node3D
var _brow_l: Node3D
var _brow_r: Node3D
var _mouth: Node3D
var _mouth_corner_l: Node3D
var _mouth_corner_r: Node3D

var _skin_mat: StandardMaterial3D
var _hair_mat: StandardMaterial3D
var _outfit_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _lip_mat: StandardMaterial3D
var _brow_mat: StandardMaterial3D
var _mouth_inner_mat: StandardMaterial3D

var _elapsed: float = 0.0
var _blink_timer: float = 2.5
var _blink_progress: float = -1.0
var _talk_target: float = 0.0
var _talk_current: float = 0.0
var _expression: String = "neutral"
var _face: Dictionary = {}
var _face_target: Dictionary = {}

var _gesture: String = ""
var _gesture_time: float = 0.0
var _gesture_length: float = 1.6

var _look_target: Vector3 = Vector3.ZERO
var _look_enabled: bool = false
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0


func _ready() -> void:
	randomize()
	_blink_timer = randf_range(1.5, 4.0)
	_face = (EXPRESSIONS["neutral"] as Dictionary).duplicate(true)
	_face_target = (EXPRESSIONS["neutral"] as Dictionary).duplicate(true)
	rebuild()


# --------------------------------------------------------------------------
# Public API (kept identical for GLB avatars, see docs/AVATAR_INTEGRATION.md)
# --------------------------------------------------------------------------

func apply_profile(new_profile: CompanionProfile) -> void:
	profile = new_profile
	var key := _compute_build_key()
	if key != _build_key:
		rebuild()
	else:
		_apply_materials()


func set_quality(level: int) -> void:
	preset_detail(int(QualityPresets.for_level(level).get("mesh_detail", 1)))


## Sets the mesh density used by the next build. Safe to call before the node
## enters the tree (used by AvatarLoader while constructing the avatar).
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


## 0.0 = mouth closed, 1.0 = fully open. Driven by voice amplitude later.
func set_talking(amount: float) -> void:
	_talk_target = clampf(amount, 0.0, 1.0)


func is_talking() -> bool:
	return _talk_target > 0.01 or _talk_current > 0.01


func play_gesture(gesture_name: String) -> bool:
	if not GESTURES.has(gesture_name):
		return false
	_gesture = gesture_name
	_gesture_time = 0.0
	_gesture_length = 1.4 if gesture_name == "wave" else 0.9
	return true


func set_look_at(world_position: Vector3) -> void:
	_look_target = world_position
	_look_enabled = true


func clear_look_at() -> void:
	_look_enabled = false


## Reports exactly what this avatar can do, so the UI never over-promises.
func get_capabilities() -> Dictionary:
	return {
		"kind": "procedural",
		"rigged": false,
		"blendshapes": false,
		"animations": ["idle", "breathing", "blink", "look_at"],
		"expressions": EXPRESSIONS.keys(),
		"gestures": GESTURES,
		"lip_sync": "amplitude",
		"notes": "Placeholder avatar built from primitives. Drop a rigged GLB into assets/avatars/ to replace it.",
	}


func head_global_position() -> Vector3:
	return _head.global_position if _head != null else global_position + Vector3(0, 1.6, 0)


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_key = _compute_build_key()
	_make_materials()

	var height := profile.height_scale() if profile != null else 1.0

	_body = Node3D.new()
	_body.name = "Body"
	_body.scale = Vector3.ONE * height
	add_child(_body)

	_build_legs()
	_build_torso()
	_build_arms()
	_build_head()
	_apply_materials()
	_apply_face(1.0)


func _compute_build_key() -> String:
	if profile == null:
		return "default|%d" % _detail
	return "%s|%s|%s|%d" % [profile.hair_style(), profile.outfit(), str(profile.height_scale()), _detail]


func _make_materials() -> void:
	_skin_mat = _material(Color(0.91, 0.72, 0.61), 0.85)
	_hair_mat = _material(Color(0.29, 0.16, 0.24), 0.55)
	_outfit_mat = _material(Color(0.54, 0.25, 0.69), 0.8)
	_accent_mat = _material(Color(0.95, 0.90, 1.0), 0.6)
	_eye_mat = _material(Color(0.25, 0.16, 0.32), 0.25)
	_lip_mat = _material(Color(0.66, 0.28, 0.36), 0.5)
	_brow_mat = _material(Color(0.22, 0.13, 0.18), 0.7)
	_mouth_inner_mat = _material(Color(0.25, 0.09, 0.13), 0.6)


func _apply_materials() -> void:
	if profile == null or _skin_mat == null:
		return
	_skin_mat.albedo_color = profile.skin_color()
	_hair_mat.albedo_color = profile.hair_color()
	_eye_mat.albedo_color = profile.eye_color()
	_outfit_mat.albedo_color = profile.outfit_color()
	_accent_mat.albedo_color = profile.accent_color()
	_lip_mat.albedo_color = profile.skin_color().lerp(Color(0.72, 0.24, 0.34), 0.55)


func _build_legs() -> void:
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, 0.90, 0)
	_body.add_child(_hips)

	_add_mesh(_hips, "Pelvis", _sphere_mesh(Vector3(0.30, 0.22, 0.20)), _outfit_mat, Vector3.ZERO)

	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(0.085 * side, -0.04, 0)
		_hips.add_child(leg)

		_add_mesh(leg, "Thigh", _capsule_mesh(0.062, 0.42), _skin_mat, Vector3(0, -0.21, 0))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0, -0.42, 0)
		leg.add_child(knee)
		_add_mesh(knee, "Shin", _capsule_mesh(0.048, 0.40), _skin_mat, Vector3(0, -0.20, 0))
		_add_mesh(knee, "Foot", _sphere_mesh(Vector3(0.11, 0.07, 0.22)), _accent_mat, Vector3(0, -0.42, 0.04))

	# Skirt / shorts depending on outfit.
	if profile != null and (profile.outfit() == "dress" or profile.outfit() == "gown"):
		var skirt := _cylinder_mesh(0.16, 0.235, 0.32)
		_add_mesh(_hips, "Skirt", skirt, _outfit_mat, Vector3(0, -0.14, 0))


func _build_torso() -> void:
	_spine = Node3D.new()
	_spine.name = "Spine"
	_spine.position = Vector3(0, 0.10, 0)
	_hips.add_child(_spine)

	_add_mesh(_spine, "Waist", _capsule_mesh(0.105, 0.26), _outfit_mat, Vector3(0, 0.06, 0))

	_chest = Node3D.new()
	_chest.name = "Chest"
	_chest.position = Vector3(0, 0.20, 0)
	_spine.add_child(_chest)

	_add_mesh(_chest, "Torso", _capsule_mesh(0.138, 0.34), _outfit_mat, Vector3(0, 0.06, 0))
	_add_mesh(_chest, "Collar", _sphere_mesh(Vector3(0.19, 0.06, 0.13)), _outfit_mat, Vector3(0, 0.22, 0))

	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0, 0.27, 0)
	_chest.add_child(_neck)
	_add_mesh(_neck, "NeckMesh", _capsule_mesh(0.038, 0.11), _skin_mat, Vector3(0, 0.04, 0))


func _build_arms() -> void:
	for side in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.name = "ShoulderL" if side < 0 else "ShoulderR"
		shoulder.position = Vector3(0.132 * side, 0.19, 0)
		_chest.add_child(shoulder)

		_add_mesh(shoulder, "UpperArm", _capsule_mesh(0.048, 0.26), _skin_mat, Vector3(0, -0.13, 0))

		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0, -0.26, 0)
		shoulder.add_child(elbow)
		_add_mesh(elbow, "Forearm", _capsule_mesh(0.036, 0.24), _skin_mat, Vector3(0, -0.12, 0))
		_add_mesh(elbow, "Hand", _sphere_mesh(Vector3(0.075, 0.09, 0.05)), _skin_mat, Vector3(0, -0.26, 0))

		shoulder.rotation.z = -0.10 * side
		elbow.rotation.x = -0.12

		if side < 0:
			_arm_l = shoulder
			_forearm_l = elbow
		else:
			_arm_r = shoulder
			_forearm_r = elbow


func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.12, 0)
	_neck.add_child(_head)

	_add_mesh(_head, "Skull", _sphere_mesh(Vector3(0.20, 0.24, 0.20)), _skin_mat, Vector3.ZERO)
	_add_mesh(_head, "Jaw", _sphere_mesh(Vector3(0.16, 0.13, 0.17)), _skin_mat, Vector3(0, -0.075, 0.008))
	_add_mesh(_head, "EarL", _sphere_mesh(Vector3(0.035, 0.06, 0.03)), _skin_mat, Vector3(-0.098, -0.01, 0))
	_add_mesh(_head, "EarR", _sphere_mesh(Vector3(0.035, 0.06, 0.03)), _skin_mat, Vector3(0.098, -0.01, 0))
	_add_mesh(_head, "Nose", _sphere_mesh(Vector3(0.026, 0.034, 0.03)), _skin_mat, Vector3(0, -0.035, 0.096))

	_build_hair()
	_build_eyes()
	_build_brows()
	_build_mouth()


func _build_hair() -> void:
	var style := profile.hair_style() if profile != null else "long"

	_add_mesh(_head, "HairCap", _sphere_mesh(Vector3(0.215, 0.19, 0.215)), _hair_mat, Vector3(0, 0.032, -0.008))
	_add_mesh(_head, "HairBack", _sphere_mesh(Vector3(0.205, 0.20, 0.16)), _hair_mat, Vector3(0, -0.02, -0.062))

	match style:
		"long":
			_add_mesh(_head, "HairLength", _capsule_mesh(0.105, 0.44), _hair_mat, Vector3(0, -0.20, -0.085))
			_add_mesh(_head, "Fringe", _sphere_mesh(Vector3(0.20, 0.085, 0.09)), _hair_mat, Vector3(0, 0.075, 0.105))
		"bob":
			_add_mesh(_head, "HairLength", _sphere_mesh(Vector3(0.215, 0.19, 0.20)), _hair_mat, Vector3(0, -0.075, -0.02))
			_add_mesh(_head, "Fringe", _sphere_mesh(Vector3(0.20, 0.075, 0.10)), _hair_mat, Vector3(0, 0.085, 0.10))
		"ponytail":
			_add_mesh(_head, "Ponytail", _capsule_mesh(0.062, 0.34), _hair_mat, Vector3(0, -0.10, -0.135))
			_add_mesh(_head, "Fringe", _sphere_mesh(Vector3(0.20, 0.08, 0.09)), _hair_mat, Vector3(0, 0.08, 0.10))
		"twin_tails":
			_add_mesh(_head, "TailL", _capsule_mesh(0.055, 0.32), _hair_mat, Vector3(-0.135, -0.10, -0.055))
			_add_mesh(_head, "TailR", _capsule_mesh(0.055, 0.32), _hair_mat, Vector3(0.135, -0.10, -0.055))
			_add_mesh(_head, "Fringe", _sphere_mesh(Vector3(0.20, 0.08, 0.10)), _hair_mat, Vector3(0, 0.082, 0.10))
		_:
			_add_mesh(_head, "Fringe", _sphere_mesh(Vector3(0.20, 0.07, 0.10)), _hair_mat, Vector3(0, 0.09, 0.10))


func _build_eyes() -> void:
	for side in [-1, 1]:
		var eye := Node3D.new()
		eye.name = "EyeL" if side < 0 else "EyeR"
		eye.position = Vector3(0.058 * side, 0.005, 0.086)
		_head.add_child(eye)
		_add_mesh(eye, "White", _sphere_mesh(Vector3(0.050, 0.047, 0.028)), _accent_mat, Vector3.ZERO)
		_add_mesh(eye, "Iris", _sphere_mesh(Vector3(0.031, 0.036, 0.026)), _eye_mat, Vector3(0, 0, 0.008))
		_add_mesh(eye, "Pupil", _sphere_mesh(Vector3(0.015, 0.018, 0.018)), _brow_mat, Vector3(0, 0, 0.013))
		_add_mesh(eye, "Glint", _sphere_mesh(Vector3(0.011, 0.013, 0.010)), _accent_mat, Vector3(-0.007 * side, 0.010, 0.016))

		# Skin-coloured lid that slides down over the eye when blinking.
		var lid := Node3D.new()
		lid.name = "LidL" if side < 0 else "LidR"
		lid.position = Vector3(0.058 * side, 0.030, 0.086)
		_head.add_child(lid)
		_add_mesh(lid, "LidMesh", _sphere_mesh(Vector3(0.054, 0.026, 0.030)), _skin_mat, Vector3.ZERO)

		if side < 0:
			_eye_l = eye
			_lid_l = lid
		else:
			_eye_r = eye
			_lid_r = lid


func _build_brows() -> void:
	for side in [-1, 1]:
		var brow := Node3D.new()
		brow.name = "BrowL" if side < 0 else "BrowR"
		brow.position = Vector3(0.058 * side, 0.058, 0.091)
		_head.add_child(brow)
		_add_mesh(brow, "BrowMesh", _sphere_mesh(Vector3(0.050, 0.011, 0.013)), _brow_mat, Vector3.ZERO)
		if side < 0:
			_brow_l = brow
		else:
			_brow_r = brow


func _build_mouth() -> void:
	_mouth = Node3D.new()
	_mouth.name = "Mouth"
	_mouth.position = Vector3(0, -0.072, 0.088)
	_head.add_child(_mouth)

	_add_mesh(_mouth, "InnerMouth", _sphere_mesh(Vector3(0.056, 0.024, 0.022)), _mouth_inner_mat, Vector3(0, 0, -0.004))
	_add_mesh(_mouth, "LipUpper", _sphere_mesh(Vector3(0.062, 0.013, 0.018)), _lip_mat, Vector3(0, 0.007, 0.002))
	_add_mesh(_mouth, "LipLower", _sphere_mesh(Vector3(0.056, 0.015, 0.018)), _lip_mat, Vector3(0, -0.009, 0.002))

	for side in [-1, 1]:
		var corner := Node3D.new()
		corner.name = "CornerL" if side < 0 else "CornerR"
		corner.position = Vector3(0.030 * side, 0, 0)
		_mouth.add_child(corner)
		_add_mesh(corner, "CornerMesh", _sphere_mesh(Vector3(0.016, 0.016, 0.016)), _lip_mat, Vector3.ZERO)
		if side < 0:
			_mouth_corner_l = corner
		else:
			_mouth_corner_r = corner


# --------------------------------------------------------------------------
# Animation
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _body == null:
		return

	_elapsed += delta
	_update_blink(delta)
	_update_gesture(delta)
	_update_look(delta)
	_update_face(delta)
	_update_idle()


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
	# 0.0 = eyes fully open, 1.0 = fully closed.
	if _blink_progress < 0.0:
		return 0.0
	var t := clampf(_blink_progress / 0.20, 0.0, 1.0)
	return sin(t * PI)


func _update_gesture(delta: float) -> void:
	if _gesture.is_empty():
		return
	_gesture_time += delta
	if _gesture_time >= _gesture_length:
		var finished := _gesture
		_gesture = ""
		_gesture_time = 0.0
		gesture_finished.emit(finished)


func _update_look(delta: float) -> void:
	if not _look_enabled or _head == null:
		_head_yaw = lerpf(_head_yaw, 0.0, minf(1.0, delta * 3.0))
		_head_pitch = lerpf(_head_pitch, 0.0, minf(1.0, delta * 3.0))
		return

	var anchor := _head.get_parent() as Node3D
	if anchor == null:
		return
	var target_local := anchor.to_local(_look_target)
	var offset := target_local - _head.position
	var flat := Vector2(offset.x, offset.z).length()
	var yaw := atan2(offset.x, maxf(offset.z, 0.05))
	var pitch := -atan2(offset.y, maxf(flat, 0.05))

	_head_yaw = lerpf(_head_yaw, clampf(yaw, -0.55, 0.55), minf(1.0, delta * 4.0))
	_head_pitch = lerpf(_head_pitch, clampf(pitch, -0.30, 0.28), minf(1.0, delta * 4.0))


func _update_face(delta: float) -> void:
	_talk_current = lerpf(_talk_current, _talk_target, minf(1.0, delta * 9.0))
	for key in _face_target.keys():
		var speed := 8.0
		if key == "open":
			speed = 14.0
		_face[key] = lerpf(float(_face.get(key, 0.0)), float(_face_target[key]), minf(1.0, delta * speed))

	# Speech overrides the expression's mouth opening while the avatar talks.
	if _expression == "speaking" or _talk_current > 0.01:
		var wobble := 0.85 + sin(_elapsed * 13.0) * 0.15
		_face["open"] = clampf(_talk_current * wobble, 0.0, 1.0)

	_apply_face(delta)


func _apply_face(delta: float) -> void:
	if _head == null:
		return
	var blink := _blink_amount()
	var eye_open := float(_face.get("eye", 1.0)) * (1.0 - blink * 0.95)
	var curve := float(_face.get("curve", 0.0))
	var open := clampf(float(_face.get("open", 0.0)), 0.0, 1.0)
	var brow := float(_face.get("brow", 0.0))
	var brow_inner := float(_face.get("brow_inner", 0.0))

	if _eye_l != null:
		_eye_l.scale = Vector3(1.0, maxf(eye_open, 0.06), 1.0)
	if _eye_r != null:
		_eye_r.scale = Vector3(1.0, maxf(eye_open, 0.06), 1.0)
	if _lid_l != null:
		_lid_l.position.y = 0.030 - blink * 0.034
	if _lid_r != null:
		_lid_r.position.y = 0.030 - blink * 0.034

	if _brow_l != null:
		_brow_l.position.y = 0.058 + brow * 0.012
		_brow_l.rotation.z = brow_inner * 0.30
	if _brow_r != null:
		_brow_r.position.y = 0.058 + brow * 0.012
		_brow_r.rotation.z = -brow_inner * 0.30

	if _mouth != null:
		_mouth.scale = Vector3(1.0 + curve * 0.26, 1.0 + open * 1.5, 1.0)
		_mouth.position.y = -0.072 - open * 0.004
	if _mouth_corner_l != null:
		_mouth_corner_l.position.y = curve * 0.009
	if _mouth_corner_r != null:
		_mouth_corner_r.position.y = curve * 0.009

	var tilt := float(_face.get("roll", 0.0))
	var pitch := float(_face.get("pitch", 0.0))
	var head_weight := clampf(delta * 12.0, 0.0, 1.0)
	_head.rotation = Vector3(
		lerpf(_head.rotation.x, _head_pitch + pitch, head_weight),
		lerpf(_head.rotation.y, _head_yaw, head_weight),
		lerpf(_head.rotation.z, tilt, head_weight)
	)


func _update_idle() -> void:
	var breath := sin(_elapsed * 1.5)
	if _chest != null:
		_chest.scale = Vector3(1.0, 1.0 + breath * 0.012, 1.0 + breath * 0.008)
	if _spine != null:
		_spine.rotation.x = 0.008 + breath * 0.006
	if _body != null:
		_body.rotation.y = sin(_elapsed * 0.45) * 0.035
		_body.position.y = breath * 0.006

	# Arms: rest pose plus any running gesture.
	var swing := sin(_elapsed * 0.7) * 0.03
	var right_z := -0.10
	var right_forearm_x := -0.12
	var left_z := 0.10

	if _gesture == "wave":
		var t := clampf(_gesture_time / 0.35, 0.0, 1.0)
		right_z = lerpf(-0.10, 2.05, t)
		right_forearm_x = -0.12 - sin(_gesture_time * 13.0) * 0.35 * t
	elif _gesture == "nod":
		if _head != null:
			_head.rotation.x += sin(_gesture_time * 9.0) * 0.12
	elif _gesture == "shake":
		if _head != null:
			_head.rotation.y += sin(_gesture_time * 10.0) * 0.18

	if _arm_r != null:
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, right_z, 0.18)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing, 0.15)
	if _forearm_r != null:
		_forearm_r.rotation.x = lerpf(_forearm_r.rotation.x, right_forearm_x, 0.25)
	if _arm_l != null:
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, left_z, 0.15)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -swing, 0.15)


# --------------------------------------------------------------------------
# Mesh helpers
# --------------------------------------------------------------------------

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	# Keeps low-end mobile GPUs cheap: no per-pixel specular lobes.
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if _detail <= 0 else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = node_name
	item.mesh = mesh
	item.position = pos
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _detail >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


func _segments() -> Vector2i:
	# radial, rings
	match _detail:
		0:
			return Vector2i(10, 5)
		1:
			return Vector2i(14, 7)
		2:
			return Vector2i(20, 10)
		_:
			return Vector2i(28, 14)


func _sphere_mesh(size: Vector3) -> Mesh:
	var seg := _segments()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = seg.x
	mesh.rings = seg.y
	mesh.is_hemisphere = false
	var wrapper := _ScaledMesh.new()
	wrapper.inner = mesh
	wrapper.scale = size
	return wrapper.build()


func _capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var seg := _segments()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = seg.x
	mesh.rings = maxi(3, seg.y / 2)
	return mesh


func _cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var seg := _segments()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = seg.x
	mesh.rings = maxi(1, seg.y / 3)
	return mesh


## Small helper that bakes a scale into a sphere mesh so each eye/brow/mouth
## piece can be scaled independently at runtime without fighting the mesh scale.
class _ScaledMesh extends RefCounted:
	var inner: SphereMesh
	var scale: Vector3 = Vector3.ONE

	func build() -> ArrayMesh:
		var arrays := inner.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] = vertices[index] * scale
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in normals.size():
			normals[index] = (normals[index] / scale).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
