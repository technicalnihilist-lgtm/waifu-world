class_name AnimeFace
extends RefCounted
## Generates anime-style face textures at runtime.
##
## This is how stylised anime avatars actually work: the face is painted into a
## texture mapped onto the head, not modelled as 3D spheres. Big eyes, lashes,
## brows and mouth all read correctly at any distance because they are drawn,
## not approximated with geometry.
##
## Textures are drawn at 2x and downsampled, which is the cheap way to get
## anti-aliased edges without a real vector rasteriser.
##
## UV layout matches RiggedAvatar's head loft:
##   u = 0.5 is straight ahead, u wraps 0..1 around the head
##   v = 0 is the crown, v = 1 is the chin
##
## Expression set: neutral, blink, happy, talk, surprised.

const SIZE := 512
const SUPERSAMPLE := 2

const EYE_V := 0.545
const EYE_U := 0.556
const EYE_SPACING := 0.088


## Builds one face texture for an expression.
static func make(expression: String, skin: Color, iris: Color, hair: Color) -> ImageTexture:
	var size := SIZE * SUPERSAMPLE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(skin)

	var blush := skin.lerp(Color(0.96, 0.55, 0.60), 0.35)
	var line := Color(0.16, 0.10, 0.13)

	# Soft blush on the cheeks.
	_soft_ellipse(image, _u(0.5 - 0.105), _v(0.63), 34.0, 17.0, blush.lerp(skin, 0.35))
	_soft_ellipse(image, _u(0.5 + 0.105), _v(0.63), 34.0, 17.0, blush.lerp(skin, 0.35))

	match expression:
		"blink":
			_eye_closed(image, _u(0.5 - EYE_SPACING), _v(EYE_V), iris, line)
			_eye_closed(image, _u(0.5 + EYE_SPACING), _v(EYE_V), iris, line)
		"happy":
			_eye_happy(image, _u(0.5 - EYE_SPACING), _v(EYE_V), iris, line)
			_eye_happy(image, _u(0.5 + EYE_SPACING), _v(EYE_V), iris, line)
		_:
			_eye_open(image, _u(0.5 - EYE_SPACING), _v(EYE_V), iris, line)
			_eye_open(image, _u(0.5 + EYE_SPACING), _v(EYE_V), iris, line)

	# Brows.
	var brow_y := _v(EYE_V - 0.105)
	_brow(image, _u(0.5 - EYE_SPACING), brow_y, hair.darkened(0.25))
	_brow(image, _u(0.5 + EYE_SPACING), brow_y, hair.darkened(0.25))

	# Nose: a tiny shadow, anime style.
	_soft_ellipse(image, _u(0.5), _v(0.645), 6.0, 4.0, skin.darkened(0.16))

	match expression:
		"talk":
			_mouth_open(image, _u(0.5), _v(0.70), line, 1.0)
		"surprised":
			_mouth_open(image, _u(0.5), _v(0.70), line, 0.7)
		"happy":
			_mouth_smile(image, _u(0.5), _v(0.695), line, 1.15)
		"blink":
			_mouth_smile(image, _u(0.5), _v(0.70), line, 0.7)
		_:
			_mouth_smile(image, _u(0.5), _v(0.70), line, 0.85)

	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


## Mouth-open variant used for lip-sync while the neutral texture is showing.
static func make_talking(skin: Color, iris: Color, hair: Color, openness: float) -> ImageTexture:
	return make("talk" if openness > 0.35 else "neutral", skin, iris, hair)


static func _u(value: float) -> float:
	return value * SIZE * SUPERSAMPLE


static func _v(value: float) -> float:
	return value * SIZE * SUPERSAMPLE


# --------------------------------------------------------------------------
# Features
# --------------------------------------------------------------------------

static func _eye_open(image: Image, cx: float, cy: float, iris: Color, line: Color) -> void:
	var w := 30.0 * SUPERSAMPLE
	var h := 36.0 * SUPERSAMPLE

	# Eye socket shadow, then the sclera.
	_ellipse(image, cx, cy, w * 1.06, h * 1.06, Color(0.98, 0.95, 0.95))
	_ellipse(image, cx, cy, w, h, Color(0.99, 0.98, 0.99))

	# Iris with a darker rim, then the pupil.
	_ellipse(image, cx, cy + h * 0.06, w * 0.72, h * 0.80, iris.darkened(0.25))
	_ellipse(image, cx, cy + h * 0.04, w * 0.62, h * 0.70, iris)
	_ellipse(image, cx, cy + h * 0.02, w * 0.34, h * 0.42, line.lerp(iris, 0.15))

	# Highlights: one big, one small, upper left.
	_ellipse(image, cx - w * 0.26, cy - h * 0.28, w * 0.22, h * 0.20, Color(1, 1, 1, 0.95))
	_ellipse(image, cx + w * 0.24, cy + h * 0.30, w * 0.12, h * 0.10, Color(1, 1, 1, 0.75))

	# Upper lash line: thick dark arc.
	for i in 9:
		var t := float(i) / 8.0
		var x := cx + lerpf(-w, w, t)
		var y := cy - h * (0.92 - 0.30 * sin(t * PI))
		_ellipse(image, x, y, w * 0.17, h * 0.11, line)
	# Outer corner flick.
	_ellipse(image, cx - w * 1.02, cy - h * 0.55, w * 0.20, h * 0.09, line)


static func _eye_closed(image: Image, cx: float, cy: float, _iris: Color, line: Color) -> void:
	var w := 30.0 * SUPERSAMPLE
	var h := 36.0 * SUPERSAMPLE
	for i in 9:
		var t := float(i) / 8.0
		var x := cx + lerpf(-w, w, t)
		var y := cy + h * (0.12 - 0.22 * sin(t * PI))
		_ellipse(image, x, y, w * 0.16, h * 0.075, line)


static func _eye_happy(image: Image, cx: float, cy: float, _iris: Color, line: Color) -> void:
	var w := 30.0 * SUPERSAMPLE
	var h := 36.0 * SUPERSAMPLE
	for i in 9:
		var t := float(i) / 8.0
		var x := cx + lerpf(-w, w, t)
		var y := cy - h * 0.18 + h * 0.55 * sin(t * PI)
		_ellipse(image, x, y, w * 0.16, h * 0.08, line)


static func _brow(image: Image, cx: float, cy: float, colour: Color) -> void:
	var w := 28.0 * SUPERSAMPLE
	for i in 7:
		var t := float(i) / 6.0
		var x := cx + lerpf(-w, w, t)
		var y := cy - (8.0 * SUPERSAMPLE) * sin(t * PI)
		_ellipse(image, x, y, w * 0.13, 3.2 * SUPERSAMPLE, colour)


static func _mouth_smile(image: Image, cx: float, cy: float, line: Color, width: float) -> void:
	var w := 22.0 * SUPERSAMPLE * width
	for i in 9:
		var t := float(i) / 8.0
		var x := cx + lerpf(-w, w, t)
		var y := cy + (7.0 * SUPERSAMPLE) * sin(t * PI)
		_ellipse(image, x, y, w * 0.14, 3.0 * SUPERSAMPLE, line)


static func _mouth_open(image: Image, cx: float, cy: float, line: Color, scale_value: float) -> void:
	var w := 20.0 * SUPERSAMPLE * scale_value
	var h := 16.0 * SUPERSAMPLE * scale_value
	_ellipse(image, cx, cy + h * 0.25, w, h, Color(0.45, 0.16, 0.20))
	_ellipse(image, cx, cy + h * 0.75, w * 0.55, h * 0.35, Color(0.72, 0.34, 0.36))
	for i in 9:
		var t := float(i) / 8.0
		var x := cx + lerpf(-w, w, t)
		var y := cy - h * 0.55 + h * 0.30 * sin(t * PI)
		_ellipse(image, x, y, w * 0.13, 3.0 * SUPERSAMPLE, line)


# --------------------------------------------------------------------------
# Raster helpers
# --------------------------------------------------------------------------

static func _ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, colour: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0 := int(maxf(0.0, floorf(cx - rx)))
	var x1 := int(minf(float(image.get_width() - 1), ceilf(cx + rx)))
	var y0 := int(maxf(0.0, floorf(cy - ry)))
	var y1 := int(minf(float(image.get_height() - 1), ceilf(cy + ry)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(x, y, colour)


## Soft-edged ellipse for blush and shading.
static func _soft_ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, colour: Color) -> void:
	var reach := 1.6
	var x0 := int(maxf(0.0, floorf(cx - rx * reach)))
	var x1 := int(minf(float(image.get_width() - 1), ceilf(cx + rx * reach)))
	var y0 := int(maxf(0.0, floorf(cy - ry * reach)))
	var y1 := int(minf(float(image.get_height() - 1), ceilf(cy + ry * reach)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var distance := sqrt(dx * dx + dy * dy)
			if distance > reach:
				continue
			var alpha := clampf(1.0 - (distance - 1.0) / (reach - 1.0), 0.0, 1.0) * 0.85
			if distance <= 1.0:
				alpha = 0.85
			var base := image.get_pixel(x, y)
			image.set_pixel(x, y, base.lerp(colour, alpha))
