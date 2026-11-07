class_name RoomPresets
extends RefCounted
## Data-driven room definitions.
##
## A room is a dictionary of colours plus a flat list of primitive items. The
## RoomBuilder turns that list into real 3D nodes (with collision shapes), so
## adding furniture never requires touching code — and a future room editor can
## save exactly this structure.
##
## Item keys (all optional except name/pos/size):
##   name      String   unique node name
##   pos       Vector3  centre position in metres
##   size      Vector3  full size in metres
##   color     String   hex colour
##   shape     String   "box" (default) | "sphere" | "cylinder"
##   roughness float    0..1
##   metallic  float    0..1
##   emission  float    0..4   emissive strength (glowing screens, lamps)
##   collide   bool     false for rugs, pictures and other walk-through decor
##   window    bool     marks the main window (lighting controller aims at it)
##   lamp      bool     marks a practical light (room builder may add an OmniLight3D)

const ROOM_IDS := ["bedroom", "living_room", "apartment"]

const ROOMS := {
	"bedroom": {
		"display_name": "Modern Bedroom",
		"description": "Warm bedroom with a double bed, desk, window and night lamp.",
		"companion_position": Vector3(0.0, 0.0, 0.35),
		"camera_height": 1.55,
		"camera_distance": 3.8,
		"items": [
			{"name": "Floor", "pos": Vector3(0, -0.1, 0), "size": Vector3(5.0, 0.2, 5.0), "color": "#2b2233", "roughness": 0.92},
			{"name": "Ceiling", "pos": Vector3(0, 2.8, 0), "size": Vector3(5.0, 0.12, 5.0), "color": "#33293d", "roughness": 0.95},
			{"name": "BackWall", "pos": Vector3(0, 1.35, -2.5), "size": Vector3(5.0, 2.8, 0.15), "color": "#3a2d45", "roughness": 0.88},
			{"name": "LeftWall", "pos": Vector3(-2.5, 1.35, 0), "size": Vector3(0.15, 2.8, 5.0), "color": "#40334c", "roughness": 0.88},
			{"name": "RightWall", "pos": Vector3(2.5, 1.35, 0), "size": Vector3(0.15, 2.8, 5.0), "color": "#332a3e", "roughness": 0.88},

			{"name": "Window", "pos": Vector3(-1.05, 1.62, -2.40), "size": Vector3(1.55, 1.35, 0.06), "color": "#9fc4e8", "emission": 0.55, "collide": false, "window": true},
			{"name": "WindowFrameTop", "pos": Vector3(-1.05, 2.32, -2.39), "size": Vector3(1.7, 0.07, 0.1), "color": "#57405f", "collide": false},
			{"name": "WindowFrameBottom", "pos": Vector3(-1.05, 0.92, -2.39), "size": Vector3(1.7, 0.07, 0.1), "color": "#57405f", "collide": false},

			{"name": "Rug", "pos": Vector3(0.15, 0.012, 0.45), "size": Vector3(3.3, 0.03, 2.5), "color": "#4a3358", "roughness": 0.98, "collide": false},

			{"name": "BedBase", "pos": Vector3(-1.55, 0.30, -1.62), "size": Vector3(2.0, 0.46, 1.95), "color": "#3b2a4a", "roughness": 0.7},
			{"name": "Mattress", "pos": Vector3(-1.55, 0.62, -1.62), "size": Vector3(1.94, 0.2, 1.88), "color": "#cbb8d8", "roughness": 0.85},
			{"name": "Pillow", "pos": Vector3(-1.95, 0.78, -2.16), "size": Vector3(0.7, 0.16, 0.46), "color": "#efe6f6", "roughness": 0.9},
			{"name": "Blanket", "pos": Vector3(-1.32, 0.71, -1.35), "size": Vector3(1.15, 0.1, 1.72), "color": "#7a4d95", "roughness": 0.9},

			{"name": "Nightstand", "pos": Vector3(-0.42, 0.28, -2.16), "size": Vector3(0.5, 0.56, 0.5), "color": "#4a3556", "roughness": 0.7},
			{"name": "LampShade", "pos": Vector3(-0.42, 0.72, -2.16), "size": Vector3(0.26, 0.26, 0.26), "color": "#f3e2c8", "emission": 1.4, "shape": "cylinder", "collide": false, "lamp": true},

			{"name": "DeskTop", "pos": Vector3(1.62, 0.74, -2.05), "size": Vector3(1.45, 0.07, 0.66), "color": "#5a3f68", "roughness": 0.6},
			{"name": "DeskLegL", "pos": Vector3(0.98, 0.37, -2.05), "size": Vector3(0.07, 0.74, 0.07), "color": "#4a3556"},
			{"name": "DeskLegR", "pos": Vector3(2.26, 0.37, -2.05), "size": Vector3(0.07, 0.74, 0.07), "color": "#4a3556"},
			{"name": "DeskLamp", "pos": Vector3(1.15, 0.86, -2.20), "size": Vector3(0.14, 0.2, 0.14), "color": "#9f7fc0", "emission": 0.8, "shape": "cylinder", "collide": false},

			{"name": "ChairSeat", "pos": Vector3(1.62, 0.46, -1.42), "size": Vector3(0.46, 0.07, 0.44), "color": "#6b4a80"},
			{"name": "ChairBack", "pos": Vector3(1.62, 0.72, -1.63), "size": Vector3(0.46, 0.44, 0.06), "color": "#6b4a80"},

			{"name": "Shelf", "pos": Vector3(2.20, 1.62, -2.40), "size": Vector3(0.9, 0.06, 0.3), "color": "#4a3556"},
			{"name": "BookA", "pos": Vector3(1.95, 1.73, -2.40), "size": Vector3(0.06, 0.2, 0.2), "color": "#b15d7a", "collide": false},
			{"name": "BookB", "pos": Vector3(2.05, 1.71, -2.40), "size": Vector3(0.05, 0.16, 0.19), "color": "#5d87b1", "collide": false},
			{"name": "BookC", "pos": Vector3(2.14, 1.72, -2.40), "size": Vector3(0.05, 0.18, 0.18), "color": "#c8b25d", "collide": false},

			{"name": "PlantPot", "pos": Vector3(2.15, 0.16, 1.35), "size": Vector3(0.34, 0.32, 0.34), "color": "#7c5a48", "shape": "cylinder", "roughness": 0.9},
			{"name": "PlantLeaves", "pos": Vector3(2.15, 0.62, 1.35), "size": Vector3(0.6, 0.7, 0.6), "color": "#4f7d4a", "shape": "sphere", "roughness": 0.95, "collide": false},

			{"name": "WallPicture", "pos": Vector3(-1.75, 2.05, -2.41), "size": Vector3(0.72, 0.52, 0.05), "color": "#6b4a80", "collide": false},
			{"name": "WallPictureArt", "pos": Vector3(-1.75, 2.05, -2.38), "size": Vector3(0.56, 0.36, 0.02), "color": "#d9a5c9", "emission": 0.25, "collide": false},
		],
	},

	"living_room": {
		"display_name": "Cosy Living Room",
		"description": "Sofa, coffee table, TV wall and a big window.",
		"companion_position": Vector3(0.0, 0.0, 0.55),
		"camera_height": 1.55,
		"camera_distance": 4.0,
		"items": [
			{"name": "Floor", "pos": Vector3(0, -0.1, 0), "size": Vector3(5.4, 0.2, 5.4), "color": "#33291f", "roughness": 0.9},
			{"name": "Ceiling", "pos": Vector3(0, 2.85, 0), "size": Vector3(5.4, 0.12, 5.4), "color": "#3a2f24"},
			{"name": "BackWall", "pos": Vector3(0, 1.4, -2.7), "size": Vector3(5.4, 2.85, 0.15), "color": "#4a3b2c"},
			{"name": "LeftWall", "pos": Vector3(-2.7, 1.4, 0), "size": Vector3(0.15, 2.85, 5.4), "color": "#544433"},
			{"name": "RightWall", "pos": Vector3(2.7, 1.4, 0), "size": Vector3(0.15, 2.85, 5.4), "color": "#3d3124"},

			{"name": "Window", "pos": Vector3(1.7, 1.7, -2.6), "size": Vector3(1.9, 1.5, 0.06), "color": "#a8cbe8", "emission": 0.6, "collide": false, "window": true},

			{"name": "Rug", "pos": Vector3(0, 0.012, 0.3), "size": Vector3(3.6, 0.03, 2.8), "color": "#5c4636", "collide": false},

			{"name": "SofaBase", "pos": Vector3(-1.85, 0.34, -0.2), "size": Vector3(1.0, 0.44, 2.6), "color": "#6d4a4a"},
			{"name": "SofaBack", "pos": Vector3(-2.28, 0.72, -0.2), "size": Vector3(0.3, 0.8, 2.6), "color": "#7c5555"},
			{"name": "SofaCushionA", "pos": Vector3(-1.8, 0.62, -0.95), "size": Vector3(0.85, 0.18, 0.75), "color": "#8a6060", "collide": false},
			{"name": "SofaCushionB", "pos": Vector3(-1.8, 0.62, 0.35), "size": Vector3(0.85, 0.18, 0.75), "color": "#8a6060", "collide": false},

			{"name": "TableTop", "pos": Vector3(0.55, 0.42, 0.1), "size": Vector3(1.2, 0.08, 0.8), "color": "#6b4f36"},
			{"name": "TableLegA", "pos": Vector3(0.05, 0.21, -0.25), "size": Vector3(0.07, 0.42, 0.07), "color": "#5a412c"},
			{"name": "TableLegB", "pos": Vector3(1.05, 0.21, -0.25), "size": Vector3(0.07, 0.42, 0.07), "color": "#5a412c"},

			{"name": "TvStand", "pos": Vector3(0.55, 0.3, -2.35), "size": Vector3(1.8, 0.5, 0.42), "color": "#3f3226"},
			{"name": "TvScreen", "pos": Vector3(0.55, 1.15, -2.42), "size": Vector3(1.5, 0.85, 0.06), "color": "#22303f", "emission": 0.55, "collide": false},

			{"name": "FloorLampPole", "pos": Vector3(2.15, 0.9, 1.5), "size": Vector3(0.08, 1.8, 0.08), "color": "#4a3b2c", "shape": "cylinder"},
			{"name": "FloorLampShade", "pos": Vector3(2.15, 1.85, 1.5), "size": Vector3(0.42, 0.34, 0.42), "color": "#f6e6c8", "emission": 1.3, "shape": "cylinder", "collide": false, "lamp": true},

			{"name": "PlantPot", "pos": Vector3(-2.25, 0.18, 1.75), "size": Vector3(0.38, 0.36, 0.38), "color": "#7c5a48", "shape": "cylinder"},
			{"name": "PlantLeaves", "pos": Vector3(-2.25, 0.78, 1.75), "size": Vector3(0.75, 0.9, 0.75), "color": "#46703f", "shape": "sphere", "collide": false},
		],
	},

	"apartment": {
		"display_name": "Modern Apartment",
		"description": "Compact studio: bed, kitchenette, window wall.",
		"companion_position": Vector3(0.1, 0.0, 0.5),
		"camera_height": 1.55,
		"camera_distance": 3.9,
		"items": [
			{"name": "Floor", "pos": Vector3(0, -0.1, 0), "size": Vector3(5.0, 0.2, 5.0), "color": "#2e2c33", "roughness": 0.7},
			{"name": "Ceiling", "pos": Vector3(0, 2.75, 0), "size": Vector3(5.0, 0.12, 5.0), "color": "#31313a"},
			{"name": "BackWall", "pos": Vector3(0, 1.35, -2.5), "size": Vector3(5.0, 2.75, 0.15), "color": "#3c3a45"},
			{"name": "LeftWall", "pos": Vector3(-2.5, 1.35, 0), "size": Vector3(0.15, 2.75, 5.0), "color": "#44424d"},
			{"name": "RightWall", "pos": Vector3(2.5, 1.35, 0), "size": Vector3(0.15, 2.75, 5.0), "color": "#36343e"},

			{"name": "WindowWall", "pos": Vector3(-2.40, 1.55, 0.2), "size": Vector3(0.06, 1.7, 3.2), "color": "#a8cbe8", "emission": 0.7, "collide": false, "window": true},

			{"name": "Rug", "pos": Vector3(0.3, 0.012, 0.6), "size": Vector3(2.8, 0.03, 2.2), "color": "#3f4550", "collide": false},

			{"name": "BedBase", "pos": Vector3(1.55, 0.28, -1.6), "size": Vector3(1.7, 0.42, 1.9), "color": "#3a3f4a"},
			{"name": "Mattress", "pos": Vector3(1.55, 0.58, -1.6), "size": Vector3(1.66, 0.18, 1.86), "color": "#d3d8e2"},
			{"name": "Pillow", "pos": Vector3(1.55, 0.73, -2.2), "size": Vector3(0.9, 0.15, 0.4), "color": "#eef1f7"},

			{"name": "Counter", "pos": Vector3(-1.35, 0.44, -2.2), "size": Vector3(1.8, 0.88, 0.6), "color": "#4b4a52"},
			{"name": "CounterTop", "pos": Vector3(-1.35, 0.9, -2.2), "size": Vector3(1.9, 0.06, 0.66), "color": "#9aa0aa", "roughness": 0.35},
			{"name": "Kettle", "pos": Vector3(-1.85, 1.0, -2.2), "size": Vector3(0.2, 0.2, 0.2), "color": "#c9ced8", "shape": "cylinder", "collide": false},
			{"name": "StoolSeat", "pos": Vector3(-0.55, 0.6, -1.85), "size": Vector3(0.4, 0.08, 0.4), "color": "#6b6f7a", "shape": "cylinder"},
			{"name": "StoolLeg", "pos": Vector3(-0.55, 0.3, -1.85), "size": Vector3(0.07, 0.6, 0.07), "color": "#5a5e68", "shape": "cylinder"},

			{"name": "CeilingLamp", "pos": Vector3(0, 2.55, 0.2), "size": Vector3(0.5, 0.18, 0.5), "color": "#fdf3d9", "emission": 1.6, "shape": "cylinder", "collide": false, "lamp": true},

			{"name": "PlantPot", "pos": Vector3(2.1, 0.16, 1.6), "size": Vector3(0.34, 0.32, 0.34), "color": "#7c5a48", "shape": "cylinder"},
			{"name": "PlantLeaves", "pos": Vector3(2.1, 0.7, 1.6), "size": Vector3(0.7, 0.8, 0.7), "color": "#4f7d4a", "shape": "sphere", "collide": false},
		],
	},
}


static func has_room(room_id: String) -> bool:
	return ROOMS.has(room_id)


## Returns a deep copy so callers can never mutate the shared preset data.
static func get_room(room_id: String) -> Dictionary:
	if not ROOMS.has(room_id):
		return (ROOMS["bedroom"] as Dictionary).duplicate(true)
	return (ROOMS[room_id] as Dictionary).duplicate(true)


static func room_ids() -> Array:
	return ROOM_IDS.duplicate()


static func display_name(room_id: String) -> String:
	return str(get_room(room_id).get("display_name", "Room"))
