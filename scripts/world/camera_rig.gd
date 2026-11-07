class_name CameraRig
extends Node3D
## Smooth mobile camera for the companion room.
##
## Drag to orbit, pinch (or mouse wheel) to zoom, everything eased so the view
## never snaps. The rig owns a Camera3D child, so no other code has to worry
## about transforms.
##
## The camera never dips below the floor and never rotates behind the character's
## back by more than ~55 degrees, which keeps the room readable in portrait.

signal zoom_changed(distance: float)

const MIN_PITCH := -0.32
const MAX_PITCH := 0.55
const MIN_DISTANCE := 2.6
const MAX_DISTANCE := 6.0
const MAX_YAW := 0.95

var camera: Camera3D
var target: Vector3 = Vector3(0.0, 1.25, 0.0)
var yaw: float = 0.0
var pitch: float = 0.04
var distance: float = 3.8
var smoothing: float = 7.0
var allow_input: bool = true
var idle_drift: bool = true

var _target_yaw: float = 0.0
var _target_pitch: float = 0.04
var _target_distance: float = 3.8
var _target_look_at: Vector3 = Vector3(0.0, 1.25, 0.0)
var _touches: Dictionary = {}
var _dragging: bool = false
var _last_pinch: float = 0.0
var _drift_phase: float = 0.0
var _user_interacted: bool = false


func _ready() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = 46.0
		camera.near = 0.08
		camera.far = 60.0
		add_child(camera)
	camera.current = true
	_apply_transform(true)


## Sets where the camera looks (usually the companion's head).
func focus_on(world_position: Vector3, head_offset: float = 0.0) -> void:
	_target_look_at = world_position + Vector3(0, head_offset, 0)
	target = _target_look_at if not is_inside_tree() else target


func set_distance(value: float, instant: bool = false) -> void:
	_target_distance = clampf(value, MIN_DISTANCE, MAX_DISTANCE)
	if instant:
		distance = _target_distance
		_apply_transform(true)
	zoom_changed.emit(_target_distance)


func get_distance() -> float:
	return _target_distance


func set_yaw(value: float) -> void:
	_target_yaw = clampf(value, -MAX_YAW, MAX_YAW)
	if not is_inside_tree():
		yaw = _target_yaw


func reset_view() -> void:
	_target_yaw = 0.0
	_target_pitch = 0.04
	_target_distance = 3.8
	_drift_phase = 0.0


func _process(delta: float) -> void:
	if idle_drift and not _user_interacted:
		_drift_phase += delta * 0.35
		_target_yaw = sin(_drift_phase) * 0.05

	var weight := clampf(delta * smoothing, 0.0, 1.0)
	yaw = lerpf(yaw, _target_yaw, weight)
	pitch = lerpf(pitch, _target_pitch, weight)
	distance = lerpf(distance, _target_distance, weight)
	target = target.lerp(_target_look_at, weight)
	_apply_transform(false)


func _apply_transform(_instant: bool) -> void:
	if camera == null or not is_inside_tree():
		return
	var horizontal := cos(pitch) * distance
	var offset := Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
	var eye := target + offset
	eye.y = maxf(eye.y, 0.35)
	global_position = eye
	var look := target
	if absf(look.y - eye.y) < 0.001 and Vector2(look.x - eye.x, look.z - eye.z).length() < 0.001:
		return
	look_at(look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not allow_input:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		if _touches.size() == 1:
			_dragging = true
		elif _touches.size() == 2:
			_dragging = false
			_last_pinch = _pinch_distance()
		else:
			_dragging = false
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var pinch := _pinch_distance()
			if _last_pinch > 0.0 and pinch > 0.0:
				_zoom_by((_last_pinch - pinch) * 0.012)
			_last_pinch = pinch
			_user_interacted = true
		elif _dragging:
			_orbit(drag.relative)
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = mouse.pressed
				_user_interacted = true
			MOUSE_BUTTON_WHEEL_UP:
				if mouse.pressed:
					_zoom_by(-0.18)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse.pressed:
					_zoom_by(0.18)
		return

	if event is InputEventMouseMotion:
		if _dragging:
			_orbit((event as InputEventMouseMotion).relative)
		return

	if event is InputEventMagnifyGesture:
		_zoom_by((1.0 - (event as InputEventMagnifyGesture).factor) * 2.0)


func _orbit(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	_target_yaw = clampf(_target_yaw - relative.x * 0.006, -MAX_YAW, MAX_YAW)
	_target_pitch = clampf(_target_pitch + relative.y * 0.005, MIN_PITCH, MAX_PITCH)
	_user_interacted = true


func _zoom_by(amount: float) -> void:
	set_distance(_target_distance + amount)
	_user_interacted = true


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
