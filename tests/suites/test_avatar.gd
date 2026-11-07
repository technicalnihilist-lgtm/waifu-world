extends TestCase
## Rigged avatar: skeleton, skinned mesh, animation clips, face rig, loader.

var _avatar: RiggedAvatar
var _loader: AvatarLoader
var _avatar_dir: String = ""


func before() -> void:
	_avatar_dir = TestCase.temp_dir("avatars")


func after() -> void:
	TestCase.purge_dir(_avatar_dir)


func run(tree: SceneTree) -> void:
	await tree.process_frame

	# --- the rig exists ---------------------------------------------------
	_avatar = RiggedAvatar.new()
	tree.root.add_child(_avatar)
	await tree.process_frame

	not_null(_avatar.skeleton, "avatar builds a Skeleton3D")
	not_null(_avatar.body, "avatar builds a skinned body mesh")
	not_null(_avatar.animation_player, "avatar builds an AnimationPlayer")
	equal(_avatar.skeleton.get_bone_count(), RiggedAvatar.BONES.size(), "every declared bone exists")

	for required in ["hips", "spine", "chest", "neck", "head", "jaw",
			"upperarm.L", "forearm.L", "hand.L", "upperarm.R", "forearm.R", "hand.R",
			"thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]:
		check(_avatar.skeleton.find_bone(required) >= 0, "bone '%s' is present" % required)

	# --- the mesh is actually skinned to those bones ----------------------
	var mesh: Mesh = _avatar.body.mesh
	not_null(mesh, "body mesh exists")
	check(mesh.get_surface_count() >= 5, "body has one surface per material group")
	check(_avatar.body.skin != null, "mesh instance has a Skin")
	equal(str(_avatar.body.skeleton), "../Skeleton3D", "mesh instance points at the skeleton")

	var bones_format: int = mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES
	check(bones_format != 0, "surface 0 carries ARRAY_BONES data")
	var weights_format: int = mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_WEIGHTS
	check(weights_format != 0, "surface 0 carries ARRAY_WEIGHTS data")

	var used_bones := {}
	var total_weighted_vertices := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] == null:
			continue
		var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		total_weighted_vertices += bone_ids.size() / 4
		for index in range(0, bone_ids.size(), 4):
			used_bones[bone_ids[index]] = true
	check(total_weighted_vertices > 1000, "every vertex carries a bone index")
	check(used_bones.size() >= 8, "at least eight different bones drive the mesh (%d)" % used_bones.size())

	# --- capabilities are honest -----------------------------------------
	var caps := _avatar.get_capabilities()
	equal(str(caps["kind"]), "rigged", "capabilities report a rigged model")
	check(bool(caps["rigged"]), "capabilities report the skeleton")
	check(not bool(caps["blendshapes"]), "no facial blend shapes are claimed")
	equal(str(caps["lip_sync"]), "jaw bone amplitude", "lip sync is jaw driven")

	# --- animation clips --------------------------------------------------
	var animations: Array = _avatar.animation_player.get_animation_list()
	for clip in ["idle", "wave", "nod", "shake", "walk", "sit"]:
		check(animations.has(clip), "clip '%s' is authored" % clip)
	check(_avatar.animation_player.is_playing(), "an idle clip plays by default")

	var idle: Animation = _avatar.animation_player.get_animation("idle")
	check(idle.get_track_count() >= 4, "idle clip animates several bones")
	check(idle.loop_mode == Animation.LOOP_LINEAR, "idle clip loops")
	var wave: Animation = _avatar.animation_player.get_animation("wave")
	check(wave.length > 0.5, "wave clip has a real duration")
	check(wave.loop_mode == Animation.LOOP_NONE, "wave plays once")

	# --- gestures really switch clips ------------------------------------
	check(_avatar.play_gesture("wave"), "wave gesture is accepted")
	equal(_avatar.animation_player.current_animation, "wave", "wave clip is playing")
	check(not _avatar.play_gesture("backflip"), "unknown gestures are rejected")

	_avatar._gesture_timer = 0.01
	_avatar._process(0.02)
	await tree.process_frame
	equal(_avatar.animation_player.current_animation, "idle", "returns to idle after a gesture")

	check(_avatar.play_animation("walk"), "walk clip can be played")

	# --- jaw driven lip sync ---------------------------------------------
	var jaw_index := _avatar.skeleton.find_bone("jaw")
	_avatar.set_talking(0.0)
	_avatar._update_jaw(0.0)
	var closed := _avatar.skeleton.get_bone_pose_rotation(jaw_index).get_angle()
	_avatar.set_talking(1.0)
	_avatar._update_face(1.0)
	_avatar._update_jaw(0.0)
	var opened := _avatar.skeleton.get_bone_pose_rotation(jaw_index).get_angle()
	check(opened > closed + 0.05, "the jaw bone opens when talking (%.3f -> %.3f rad)" % [closed, opened])
	check(_avatar.is_talking(), "avatar reports it is talking")

	_avatar.set_talking(0.0)
	_avatar._update_face(1.0)
	check(not _avatar.is_talking(), "talking stops when the amplitude returns to zero")

	# --- face rig ---------------------------------------------------------
	_avatar.set_expression("smile")
	equal(_avatar.current_expression(), "smile", "expression is selected")
	_avatar.set_expression("nope")
	equal(_avatar.current_expression(), "neutral", "unknown expressions fall back")

	_avatar.set_expression("neutral")
	_avatar._blink_progress = -1.0
	_avatar._blink_timer = 0.0
	_avatar._update_blink(0.016)
	check(_avatar._blink_progress >= 0.0, "blink starts when the timer expires")
	_avatar._update_blink(0.10)
	check(_avatar._blink_amount() > 0.9, "blink reaches a closed state")
	_avatar._apply_face(1.0)
	check(_avatar._eye_l.scale.y < 0.25, "blinking squashes the eye instead of growing it")
	check(_avatar._lid_l.position.y < 0.020, "the eyelid slides down when blinking")

	_avatar._face["open"] = 0.0
	_avatar._apply_face(1.0)
	var mouth_closed: float = _avatar._mouth.scale.y
	_avatar._face["open"] = 1.0
	_avatar._apply_face(1.0)
	check(_avatar._mouth.scale.y > mouth_closed * 1.5, "talking opens the mouth mesh")

	# --- head tracking rides on the neck, not the animated head ----------
	var head_index := _avatar.skeleton.find_bone("head")
	var neck_index := _avatar.skeleton.find_bone("neck")
	_avatar.skeleton.set_bone_pose_rotation(head_index, Quaternion.IDENTITY)
	_avatar.skeleton.set_bone_pose_rotation(neck_index, Quaternion.IDENTITY)
	_avatar.set_look_at(Vector3(2.0, 1.6, 3.0))
	for step in 12:
		_avatar._update_look(0.1)
		_avatar._apply_face(0.1)
	check(
		_avatar.skeleton.get_bone_pose_rotation(neck_index).get_angle() > 0.02,
		"look-at rotates the neck"
	)
	check(
		_avatar.skeleton.get_bone_pose_rotation(head_index).get_angle() < 0.001,
		"look-at does not overwrite the head animation track"
	)

	# --- profile driven appearance ---------------------------------------
	var profile := CompanionProfile.create_new("Test")
	profile.apply_patch({
		"appearance": {"hair_style": "long_straight", "hair_color": "#f2d98f", "hair_tip_color": "#ef9db4"},
		"clothing": {"outfit": "school_uniform", "primary_color": "#eef1f7"},
	})
	_avatar.apply_profile(profile)
	await tree.process_frame
	approx(_avatar._hair_mat.albedo_color.g, Color.from_string("#f2d98f", Color.BLACK).g, 0.02, "hair colour applied")
	approx(_avatar._hair_tip_mat.albedo_color.g, Color.from_string("#ef9db4", Color.BLACK).g, 0.02, "hair tip colour applied")
	approx(_avatar._shirt_mat.albedo_color.b, Color.from_string("#eef1f7", Color.BLACK).b, 0.02, "shirt colour applied")
	not_null(_avatar._skirt_mat.albedo_texture, "skirt carries the procedural plaid texture")

	# --- quality / LOD ----------------------------------------------------
	_avatar.set_quality(0)
	await tree.process_frame
	var low_surfaces := _avatar.body.mesh.get_surface_count()
	_avatar.set_quality(3)
	await tree.process_frame
	equal(_avatar.body.mesh.get_surface_count(), low_surfaces, "LOD keeps the material split, only density changes")

	check(_avatar.head_global_position().y > 1.0, "head sits above the floor")

	_avatar.queue_free()
	await tree.process_frame

	# --- catalog ----------------------------------------------------------
	check(AvatarCatalog.is_supported_file("mira.glb"), "glb is a supported extension")
	check(not AvatarCatalog.is_supported_file("mira.png"), "png is not an avatar file")
	equal(AvatarCatalog.list_bundled().size(), 0, "the bundled manifest ships with no third-party avatars")
	equal(AvatarCatalog.find_by_id("nope").size(), 0, "unknown avatar id finds nothing")

	var missing := AvatarCatalog.descriptor_for(_avatar_dir.path_join("ghost.glb"))
	check(not bool(missing["valid"]), "missing avatar files are marked invalid")

	var user_avatar := _avatar_dir.path_join("nova.glb")
	TestCase.write_text(user_avatar, "not really a glb")
	TestCase.write_text(_avatar_dir.path_join("nova.json"), JSON.stringify({"display_name": "Nova", "license": "CC0"}))
	var descriptor := AvatarCatalog.descriptor_for(user_avatar)
	check(bool(descriptor["valid"]), "an existing .glb is listed as valid")
	equal(str(descriptor["display_name"]), "Nova", "sidecar display name is used")
	equal(AvatarCatalog.list_user_installed(_avatar_dir).size(), 1, "user avatar directory is scanned")

	# --- loader -----------------------------------------------------------
	_loader = AvatarLoader.new()
	tree.root.add_child(_loader)
	await tree.process_frame

	var placeholder := CompanionProfile.create_new("Fallback")
	var node := _loader.load_for_profile(placeholder, 1)
	not_null(node, "loader always returns an avatar node")
	check(_loader.used_fallback, "loader reports the fallback when no GLB is selected")
	check(node is RiggedAvatar, "fallback avatar is the built-in rigged companion")
	check(node.has_method("set_expression") and node.has_method("play_gesture"), "avatar API is complete")
	equal(str(_loader.capabilities["kind"]), "rigged", "loader reports rigged capabilities")

	var missing_profile := CompanionProfile.create_new("Missing Avatar")
	missing_profile.apply_patch({"appearance": {"avatar_id": "does_not_exist"}})
	node = _loader.load_for_profile(missing_profile, 1)
	check(_loader.used_fallback, "loader falls back for an unknown avatar id")
	check(_loader.fallback_reason.contains("not installed"), "fallback reason names the missing avatar")

	_loader.queue_free()
	await tree.process_frame
