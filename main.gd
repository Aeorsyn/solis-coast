extends Node3D

# --- Game State ---
var characters = [
	{"name": "VANCE", "role": "Driver", "shirt": Color(0.12, 0.72, 0.92), "alt_shirt": Color(0.92, 0.42, 0.14)},
	{"name": "NADIA", "role": "Tech", "shirt": Color(0.92, 0.20, 0.58), "alt_shirt": Color(0.20, 0.85, 0.52)}
]
var active_char_idx := 0
var using_alt_outfit := false

var player_hp := 100.0
var ammo := 12
var max_ammo := 12
var reload_timer := 0.0
var fire_cooldown := 0.0
var reputation := 0

var carried_cash := 0
var banked_cash := 500
var trunk_loot := 0
var heat_level := 0
var flag_cctv := false
var flag_outfit := false
var cctv_destroyed := false
var store_robbed := false
var docks_robbed := false
var pier_looted := false

var active_veh_idx := -1
var focus_active := false
var bust_timer := 0.0
var status_msg := "Walk into Solis Mart (Green), hijack any car (CAR), or explore the Pier & Docks!"
var msg_timer := 7.0

# --- Scene References ---
var player: CharacterBody3D
var player_rig: Node3D
var player_torso_mat: StandardMaterial3D
var player_duffel: MeshInstance3D
var muzzle_light: OmniLight3D
var muzzle_timer := 0.0
var player_col: CollisionShape3D

var cop: CharacterBody3D
var cop_light_l: MeshInstance3D
var cop_light_r: MeshInstance3D
var cop_officer: CharacterBody3D
var cop_officer_hp := 100.0
var cop_fire_cd := 0.0
var cop_respawn_timer := 0.0

var cctv_node: StaticBody3D
var water_mat: StandardMaterial3D
var cam: Camera3D

# --- Dynamic Entities ---
var vehicles: Array[Dictionary] = []
var peds: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var locked_target: Node3D = null

# --- Key Interactive Locations ---
var pos_store := Vector3(26, 0, -28)      # Inside Solis Mart (Downtown)
var pos_atm := Vector3(-24, 0, -24)       # Bank Plaza (Downtown)
var pos_garage := Vector3(-28, 0, 32)     # Inside Sunset Garage (Downtown)
var pos_motel := Vector3(-42, 0, -96)     # Inside Palm Motel Safehouse (North)
var pos_docks := Vector3(-18, 0, 108)     # Container Yard Heist (Harbor South)
var pos_pier := Vector3(114, 1.2, 0)      # Ocean Pier Stash (East)

# --- Interior Bounds for Camera Pull-In ---
var interiors := [
	{"name": "Solis Mart", "min": Vector3(17, -1, -36), "max": Vector3(35, 7, -21)},
	{"name": "Sunset Garage", "min": Vector3(-39, -1, 24), "max": Vector3(-17, 7, 40)},
	{"name": "Palm Motel", "min": Vector3(-50, -1, -104), "max": Vector3(-34, 7, -90)}
]

# --- HUD & Touch ---
var hud_stats: Label
var hud_heat: Label
var hud_prompt: Label
var hud_toast: Label
var touch_ui: TouchControls
var minimap: MiniMap
var reticle_ui: ReticleOverlay

# ==============================================================================
# MULTI-TOUCH CONTROLS
# ==============================================================================
class TouchControls extends Control:
	var joy_vec := Vector2.ZERO
	var joy_touch_idx := -1
	var joy_radius := 76.0
	var joy_knob_radius := 32.0

	var hold_focus := false
	var hold_brake := false
	var hold_fire := false
	var on_action: Callable

	var buttons := [
		{"id": "fire",  "label": "FIRE",  "ox": -105, "oy": -115, "r": 46.0, "col": Color(0.95, 0.22, 0.25, 0.78), "hold": true,  "idx": -1},
		{"id": "act",   "label": "ACT",   "ox": -105, "oy": -225, "r": 38.0, "col": Color(0.15, 0.85, 0.45, 0.72), "hold": false, "idx": -1},
		{"id": "car",   "label": "CAR",   "ox": -205, "oy": -175, "r": 38.0, "col": Color(0.15, 0.65, 0.95, 0.72), "hold": false, "idx": -1},
		{"id": "trunk", "label": "TRUNK", "ox": -205, "oy": -75,  "r": 35.0, "col": Color(0.95, 0.65, 0.15, 0.72), "hold": false, "idx": -1},
		{"id": "focus", "label": "FOCUS", "ox": -295, "oy": -115, "r": 36.0, "col": Color(0.70, 0.30, 0.95, 0.72), "hold": true,  "idx": -1},
		{"id": "brake", "label": "DRIFT", "ox": -295, "oy": -205, "r": 33.0, "col": Color(0.90, 0.45, 0.20, 0.70), "hold": true,  "idx": -1},
		{"id": "swap",  "label": "SWAP",  "ox": -105, "oy": -310, "r": 30.0, "col": Color(0.85, 0.25, 0.65, 0.68), "hold": false, "idx": -1}
	]

	func _joy_center() -> Vector2:
		var s = get_viewport_rect().size
		return Vector2(130.0, s.y - 135.0)

	func _btn_pos(b: Dictionary) -> Vector2:
		var s = get_viewport_rect().size
		return Vector2(s.x + b["ox"], s.y + b["oy"])

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var p: Vector2 = event.position
			if event.pressed:
				for b in buttons:
					if p.distance_to(_btn_pos(b)) <= b["r"] + 12.0:
						b["idx"] = event.index
						if b["hold"]: _sync_holds()
						elif on_action.is_valid(): on_action.call(b["id"])
						queue_redraw()
						return
				if p.x < get_viewport_rect().size.x * 0.45 and p.y > get_viewport_rect().size.y * 0.40:
					if joy_touch_idx == -1:
						joy_touch_idx = event.index
						_update_joy(p)
						queue_redraw()
			else:
				if event.index == joy_touch_idx:
					joy_touch_idx = -1
					joy_vec = Vector2.ZERO
					queue_redraw()
				for b in buttons:
					if b["idx"] == event.index:
						b["idx"] = -1
						_sync_holds()
						queue_redraw()
		elif event is InputEventScreenDrag:
			if event.index == joy_touch_idx:
				_update_joy(event.position)
				queue_redraw()

	func _update_joy(pos: Vector2) -> void:
		var delta = pos - _joy_center()
		if delta.length() > joy_radius: delta = delta.normalized() * joy_radius
		joy_vec = delta / joy_radius

	func _sync_holds() -> void:
		hold_focus = false; hold_brake = false; hold_fire = false
		for b in buttons:
			if b["id"] == "focus" and b["idx"] != -1: hold_focus = true
			if b["id"] == "brake" and b["idx"] != -1: hold_brake = true
			if b["id"] == "fire"  and b["idx"] != -1: hold_fire = true

	func _draw() -> void:
		var font = ThemeDB.fallback_font
		var jc = _joy_center()
		draw_circle(jc, joy_radius, Color(0.06, 0.08, 0.14, 0.48))
		draw_arc(jc, joy_radius, 0, TAU, 40, Color(0.35, 0.85, 1.0, 0.65), 2.5)
		var knob_pos = jc + joy_vec * (joy_radius - 14.0)
		draw_circle(knob_pos, joy_knob_radius, Color(0.25, 0.80, 0.98, 0.78))
		draw_arc(knob_pos, joy_knob_radius, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)

		for b in buttons:
			var bp = _btn_pos(b)
			var col: Color = b["col"]
			if b["idx"] != -1:
				col = col.lightened(0.28); col.a = 0.96
			draw_circle(bp, b["r"], col)
			draw_arc(bp, b["r"], 0, TAU, 32, Color(1, 1, 1, 0.78), 2.0)
			var txt: String = b["label"]
			var tsize = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			draw_string(font, bp + Vector2(-tsize.x * 0.5, 5.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

# ==============================================================================
# FOCUS RETICLE OVERLAY
# ==============================================================================
class ReticleOverlay extends Control:
	var host: Node3D
	func _draw() -> void:
		if host == null or host.active_veh_idx != -1: return
		var font = ThemeDB.fallback_font
		if host.focus_active:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.22, 0.38, 0.14), true)
		if host.locked_target != null and is_instance_valid(host.locked_target) and host.locked_target.visible:
			var world_pt = host.locked_target.global_position + Vector3(0, 0.45, 0)
			if not host.cam.is_position_behind(world_pt):
				var sp = host.cam.unproject_position(world_pt)
				var col = Color(0.25, 0.95, 1.0, 0.92) if host.focus_active else Color(1.0, 0.35, 0.30, 0.75)
				var r = 20.0 if host.focus_active else 14.0
				draw_arc(sp, r, 0, TAU, 24, col, 2.2)
				draw_line(sp + Vector2(-r - 6, 0), sp + Vector2(-r + 4, 0), col, 2.0)
				draw_line(sp + Vector2(r - 4, 0), sp + Vector2(r + 6, 0), col, 2.0)
				if host.focus_active:
					draw_string(font, sp + Vector2(-28, -r - 8), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

# ==============================================================================
# SCROLLING MULTI-DISTRICT RADAR
# ==============================================================================
class MiniMap extends Control:
	var host: Node3D
	func _draw() -> void:
		if host == null: return
		var font = ThemeDB.fallback_font
		var map_h = size.y - 22.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, map_h)), Color(0.05, 0.07, 0.12, 0.84), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, map_h)), Color(0.25, 0.85, 0.95, 0.75), false, 2.0)

		var ppos = host._get_player_pos()
		var center = Vector2(size.x * 0.5, map_h * 0.5)
		var sc = 0.82 # pixels per world unit

		var to_map = func(w: Vector3) -> Vector2:
			return center + Vector2(w.x - ppos.x, w.z - ppos.z) * sc

		# Draw Ocean & Pier
		var ocean_x = to_map.call(Vector3(64, 0, 0)).x
		if ocean_x < size.x:
			var ox = maxf(2.0, ocean_x)
			draw_rect(Rect2(ox, 2, size.x - ox - 2, map_h - 4), Color(0.08, 0.35, 0.55, 0.7), true)

		# Roads (N-S at x=0, E-W at z=0, North Blvd at z=-72, Harbor Rd at z=76)
		var rx = to_map.call(Vector3(0, 0, 0)).x
		if rx > -10 and rx < size.x + 10:
			draw_rect(Rect2(clampf(rx - 6, 2, size.x - 2), 2, 12, map_h - 4), Color(0.24, 0.26, 0.30), true)
		for rz_w in [0.0, -72.0, 76.0]:
			var ry = to_map.call(Vector3(0, 0, rz_w)).y
			if ry > 2 and ry < map_h - 2:
				draw_rect(Rect2(2, clampf(ry - 5, 2, map_h - 10), size.x - 4, 10), Color(0.24, 0.26, 0.30), true)

		# POIs
		var pois = [
			{"p": host.pos_store,  "c": Color(0.1, 0.95, 0.35)},
			{"p": host.pos_atm,    "c": Color(1.0, 0.82, 0.15)},
			{"p": host.pos_garage, "c": Color(0.1, 0.88, 0.98)},
			{"p": host.pos_motel,  "c": Color(0.95, 0.35, 0.90)},
			{"p": host.pos_docks,  "c": Color(1.0, 0.52, 0.12)},
			{"p": host.pos_pier,   "c": Color(0.95, 0.95, 0.25)}
		]
		for poi in pois:
			var mp: Vector2 = to_map.call(poi["p"])
			mp.x = clampf(mp.x, 6.0, size.x - 6.0)
			mp.y = clampf(mp.y, 6.0, map_h - 6.0)
			draw_circle(mp, 4.5, poi["c"])

		# Vehicles
		for v in host.vehicles:
			var vp: Vector2 = to_map.call(v["body"].global_position)
			if vp.x > 4 and vp.x < size.x - 4 and vp.y > 4 and vp.y < map_h - 4:
				var vc = Color(0.4, 0.4, 0.4) if v["hp"] <= 0 else (Color(0.95, 0.25, 0.4) if not v["is_ai"] else Color(0.7, 0.75, 0.85))
				draw_rect(Rect2(vp - Vector2(2, 2), Vector2(4, 4)), vc)

		# Police
		if host.cop.visible:
			var cp: Vector2 = to_map.call(host.cop.global_position)
			cp.x = clampf(cp.x, 6.0, size.x - 6.0); cp.y = clampf(cp.y, 6.0, map_h - 6.0)
			var fl = int(Time.get_ticks_msec() / 160) % 2 == 0
			draw_circle(cp, 5.0, Color(1, 0.15, 0.15) if fl else Color(0.2, 0.45, 1.0))

		# Player Center Arrow
		draw_circle(center, 4.5, Color.WHITE)

		# District Banner below Radar
		draw_rect(Rect2(0, map_h + 2, size.x, 20), Color(0.05, 0.07, 0.13, 0.85), true)
		var dname = host._get_district_name(ppos)
		draw_string(font, Vector2(6, map_h + 16), dname, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.92, 1.0))

# ==============================================================================
# PROCEDURAL TEXTURES
# ==============================================================================
func _gen_road_tex() -> ImageTexture:
	var img = Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new(); rng.seed = 42
	for y in 128:
		for x in 128:
			var n = rng.randf_range(-0.025, 0.025)
			var col = Color(0.11 + n, 0.115 + n, 0.13 + n)
			if (x >= 60 and x <= 62) or (x >= 65 and x <= 67): col = Color(0.88, 0.72, 0.15)
			elif x == 6 or x == 7 or x == 120 or x == 121: col = Color(0.75, 0.78, 0.82)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _gen_building_tex(base_col: Color, glow_col: Color, seed_val: int) -> ImageTexture:
	var img = Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new(); rng.seed = seed_val
	img.fill(base_col)
	for row in range(8):
		for col_i in range(8):
			var lit = rng.randf() < 0.42
			var wcol = glow_col.lerp(Color.WHITE, rng.randf_range(0.1, 0.45)) if lit else base_col.darkened(0.45)
			for yy in range(row * 16 + 3, row * 16 + 13):
				for xx in range(col_i * 16 + 3, col_i * 16 + 13):
					img.set_pixel(xx, yy, wcol)
	return ImageTexture.create_from_image(img)

func _gen_sidewalk_tex() -> ImageTexture:
	var img = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var seam = (x % 32 == 0) or (y % 32 == 0)
			img.set_pixel(x, y, Color(0.24, 0.25, 0.28) if seam else Color(0.32, 0.33, 0.36))
	return ImageTexture.create_from_image(img)

# ==============================================================================
# WORLD & EXPLORABLE INTERIORS
# ==============================================================================
func _ready() -> void:
	_setup_environment()
	_build_city()
	_build_player()
	_build_vehicles()
	_build_cop()
	_build_pedestrians()
	_build_camera()
	_build_hud()

func _setup_environment() -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.06, 0.22)
	sky_mat.sky_horizon_color = Color(0.95, 0.38, 0.45)
	sky_mat.ground_bottom_color = Color(0.10, 0.08, 0.16)
	sky_mat.ground_horizon_color = Color(0.35, 0.20, 0.35)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.68
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.22, 0.38)
	env.fog_density = 0.0028
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.22
	env_node.environment = env
	add_child(env_node)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 48, 0)
	sun.light_color = Color(1.0, 0.78, 0.62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)

func _make_box(size: Vector3, pos: Vector3, col: Color, emissive := false, solid := true, tex: Texture2D = null, uv_scale := Vector3.ONE) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.position = pos
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	var mat = StandardMaterial3D.new(); mat.albedo_color = col
	if tex != null:
		mat.albedo_texture = tex; mat.uv1_scale = uv_scale; mat.uv1_triplanar = true
	if emissive:
		mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 2.0
	bm.material = mat; mi.mesh = bm
	body.add_child(mi)
	if solid:
		var cs = CollisionShape3D.new()
		var bs = BoxShape3D.new(); bs.size = size
		cs.shape = bs; body.add_child(cs)
	add_child(body)
	return body

func _add_palm_tree(pos: Vector3) -> void:
	var root = Node3D.new(); root.position = pos
	var trunk_mat = StandardMaterial3D.new(); trunk_mat.albedo_color = Color(0.36, 0.25, 0.17)
	var leaf_mat = StandardMaterial3D.new(); leaf_mat.albedo_color = Color(0.12, 0.48, 0.22)
	var cur = Vector3.ZERO
	for i in range(5):
		var seg = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = 0.20 - i * 0.02; cm.bottom_radius = 0.24 - i * 0.02; cm.height = 1.5; cm.material = trunk_mat
		seg.mesh = cm; seg.position = cur + Vector3(i * 0.12, 0.75, 0); seg.rotation_degrees.z = -5.0 * i
		root.add_child(seg)
		cur.y += 1.4; cur.x += i * 0.08
	var crown = Node3D.new(); crown.position = cur + Vector3(0.3, 0.2, 0)
	for f in range(7):
		var frond = MeshInstance3D.new()
		var bm = BoxMesh.new(); bm.size = Vector3(0.45, 0.08, 3.2); bm.material = leaf_mat
		frond.mesh = bm; frond.rotation_degrees = Vector3(-24, f * (360.0 / 7.0), 0)
		frond.position = Vector3(0, 0, -1.4).rotated(Vector3.UP, deg_to_rad(f * (360.0 / 7.0)))
		crown.add_child(frond)
	root.add_child(crown); add_child(root)

func _add_detailed_building(pos: Vector3, size: Vector3, base_col: Color, neon_col: Color, seed_val: int) -> void:
	var tex = _gen_building_tex(base_col, neon_col, seed_val)
	_make_box(size, pos, Color.WHITE, false, true, tex, Vector3(0.14, 0.14, 0.14))
	_make_box(Vector3(size.x + 0.6, 0.6, size.z + 0.6), pos + Vector3(0, size.y * 0.5 + 0.3, 0), base_col.darkened(0.3), false, false)
	_make_box(Vector3(size.x + 0.8, 0.35, size.z + 0.8), pos + Vector3(0, size.y * 0.5 - 0.5, 0), neon_col, true, false)

# Builds a true walk-in / drive-in building with an open front doorway & interior lighting
func _build_walkin_building(center: Vector3, w: float, h: float, d: float, wall_col: Color, neon_col: Color, door_width: float, door_side := "south") -> void:
	var t := 0.6
	# Floor & Ceiling
	_make_box(Vector3(w, 0.14, d), Vector3(center.x, 0.07, center.z), wall_col.lightened(0.25), false, false)
	_make_box(Vector3(w + 0.6, 0.5, d + 0.6), Vector3(center.x, h + 0.25, center.z), wall_col.darkened(0.2), false, true)
	_make_box(Vector3(w + 0.9, 0.32, d + 0.9), Vector3(center.x, h + 0.05, center.z), neon_col, true, false)

	# Side Walls (East & West)
	_make_box(Vector3(t, h, d), Vector3(center.x - w * 0.5, h * 0.5, center.z), wall_col, false, true)
	_make_box(Vector3(t, h, d), Vector3(center.x + w * 0.5, h * 0.5, center.z), wall_col, false, true)

	# Back Wall + Split Front Wall (Doorway)
	var side_w = maxf(0.5, (w - door_width) * 0.5)
	if door_side == "south":
		_make_box(Vector3(w, h, t), Vector3(center.x, h * 0.5, center.z - d * 0.5), wall_col, false, true)
		_make_box(Vector3(side_w, h, t), Vector3(center.x - w * 0.5 + side_w * 0.5, h * 0.5, center.z + d * 0.5), wall_col, false, true)
		_make_box(Vector3(side_w, h, t), Vector3(center.x + w * 0.5 - side_w * 0.5, h * 0.5, center.z + d * 0.5), wall_col, false, true)
		_make_box(Vector3(door_width, 1.2, t), Vector3(center.x, h - 0.6, center.z + d * 0.5), wall_col, false, false)
	else: # north opening
		_make_box(Vector3(w, h, t), Vector3(center.x, h * 0.5, center.z + d * 0.5), wall_col, false, true)
		_make_box(Vector3(side_w, h, t), Vector3(center.x - w * 0.5 + side_w * 0.5, h * 0.5, center.z - d * 0.5), wall_col, false, true)
		_make_box(Vector3(side_w, h, t), Vector3(center.x + w * 0.5 - side_w * 0.5, h * 0.5, center.z - d * 0.5), wall_col, false, true)
		_make_box(Vector3(door_width, 1.2, t), Vector3(center.x, h - 0.6, center.z - d * 0.5), wall_col, false, false)

	# Interior warm light
	var il = OmniLight3D.new()
	il.position = Vector3(center.x, h - 1.0, center.z)
	il.light_color = neon_col.lerp(Color.WHITE, 0.65)
	il.light_energy = 2.4
	il.omni_range = maxf(w, d) * 1.2
	add_child(il)

func _build_city() -> void:
	var sidewalk_tex = _gen_sidewalk_tex()
	var road_tex = _gen_road_tex()

	# Massive Multi-District Ground (X: -145..55, Z: -145..145)
	_make_box(Vector3(200, 1, 290), Vector3(-45, -0.5, 0), Color.WHITE, false, true, sidewalk_tex, Vector3(0.25, 0.25, 0.25))

	# Beach Sand & Shimmering Ocean (East District)
	_make_box(Vector3(22, 0.9, 290), Vector3(64, -0.55, 0), Color(0.84, 0.74, 0.56), false, true)
	var water_mesh = MeshInstance3D.new()
	var pm = PlaneMesh.new(); pm.size = Vector2(180, 360)
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.06, 0.36, 0.52, 0.92)
	water_mat.metallic = 0.45; water_mat.roughness = 0.15
	water_mat.emission_enabled = true; water_mat.emission = Color(0.04, 0.18, 0.30)
	pm.material = water_mat; water_mesh.mesh = pm
	water_mesh.position = Vector3(155, -0.35, 0)
	add_child(water_mesh)

	# Ocean Pier (Walk/Drive out to X=122)
	_make_box(Vector3(58, 0.4, 10), Vector3(93, 0.6, 0), Color(0.42, 0.28, 0.18), false, true)
	# Ramp from beach to pier
	var ramp = _make_box(Vector3(8, 0.4, 10), Vector3(61, 0.25, 0), Color(0.42, 0.28, 0.18), false, true)
	ramp.rotation_degrees.z = 5.5
	# Pier Neon Pavilion & Stash Ring
	_make_box(Vector3(10, 0.4, 12), Vector3(116, 4.4, 0), Color(0.95, 0.22, 0.72), true, false)
	for px in [112, 120]:
		for pz in [-5, 5]:
			_make_box(Vector3(0.4, 4.0, 0.4), Vector3(px, 2.4, pz), Color(0.85, 0.88, 0.92), false, true)
	_make_box(Vector3(4.5, 0.14, 4.5), pos_pier + Vector3(0, -0.3, 0), Color(1.0, 0.92, 0.20), true, false)

	# Road Network (Main N-S, Central E-W, North Motel Blvd, South Harbor Hwy)
	var add_road = func(size: Vector3, pos: Vector3, rot_y: float, tiles: float):
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new(); bm.size = size
		var rm = StandardMaterial3D.new(); rm.albedo_texture = road_tex; rm.uv1_scale = Vector3(1, tiles, 1)
		bm.material = rm; mi.mesh = bm; mi.position = pos; mi.rotation_degrees.y = rot_y
		add_child(mi)

	add_road.call(Vector3(16, 0.08, 270), Vector3(0, 0.04, 0), 0.0, 22.0)
	add_road.call(Vector3(16, 0.08, 195), Vector3(-42, 0.035, 0), 90.0, 16.0)
	add_road.call(Vector3(16, 0.08, 185), Vector3(-40, 0.035, -72), 90.0, 15.0)
	add_road.call(Vector3(16, 0.08, 185), Vector3(-40, 0.035, 76), 90.0, 15.0)
	for iz in [0.0, -72.0, 76.0]:
		_make_box(Vector3(16.4, 0.09, 16.4), Vector3(0, 0.045, iz), Color(0.11, 0.115, 0.13), false, false)

	# === EXPLORABLE INTERIOR 1: SOLIS MART (Downtown NE) ===
	_build_walkin_building(Vector3(26, 0, -29), 18.0, 5.2, 14.0, Color(0.22, 0.28, 0.32), Color(0.15, 0.95, 0.45), 5.5, "south")
	# Interior shelves & checkout counter
	_make_box(Vector3(1.2, 1.8, 6.0), Vector3(21.5, 0.9, -28.5), Color(0.35, 0.40, 0.48), false, true)
	_make_box(Vector3(1.2, 1.8, 6.0), Vector3(30.5, 0.9, -28.5), Color(0.35, 0.40, 0.48), false, true)
	_make_box(Vector3(5.0, 1.1, 1.2), Vector3(26, 0.55, -32.5), Color(0.16, 0.52, 0.32), false, true)
	_make_box(Vector3(4.5, 0.12, 4.5), pos_store + Vector3(0, 0.09, 0), Color(0.1, 0.95, 0.35), true, false)
	# Shootable CCTV Camera above door
	cctv_node = _make_box(Vector3(0.55, 0.45, 0.75), Vector3(26, 4.4, -21.5), Color(0.18, 0.20, 0.24), false, true)
	var led = MeshInstance3D.new()
	var lm = SphereMesh.new(); lm.radius = 0.17
	var lmat = StandardMaterial3D.new(); lmat.albedo_color = Color(1, 0.1, 0.1); lmat.emission_enabled = true; lmat.emission = Color(1, 0.1, 0.1); lmat.emission_energy_multiplier = 4.0
	lm.material = lmat; led.mesh = lm; led.position = Vector3(0, 0, 0.4)
	cctv_node.add_child(led)

	# === EXPLORABLE INTERIOR 2: SUNSET GARAGE (Drive-In Chop Shop, Downtown SW) ===
	_build_walkin_building(Vector3(-28, 0, 32), 20.0, 5.5, 16.0, Color(0.20, 0.24, 0.26), Color(0.10, 0.88, 0.98), 8.5, "north")
	_make_box(Vector3(2.0, 1.2, 10.0), Vector3(-36.5, 0.6, 32), Color(0.75, 0.20, 0.18), false, true) # Tool chests
	_make_box(Vector3(7.5, 0.12, 7.5), pos_garage + Vector3(0, 0.09, 0), Color(0.1, 0.88, 0.98), true, false)

	# === EXPLORABLE INTERIOR 3: PALM MOTEL SAFEHOUSE (North Hills) ===
	_build_walkin_building(Vector3(-42, 0, -97), 16.0, 4.8, 12.0, Color(0.32, 0.20, 0.34), Color(0.95, 0.28, 0.85), 5.0, "south")
	_make_box(Vector3(3.2, 0.8, 4.4), Vector3(-46.5, 0.4, -99.0), Color(0.85, 0.85, 0.92), false, true) # Bed
	_make_box(Vector3(1.4, 1.4, 1.4), Vector3(-37.0, 0.7, -101.0), Color(0.18, 0.20, 0.24), false, true) # Stash Safe
	_make_box(Vector3(4.5, 0.12, 4.5), pos_motel + Vector3(0, 0.09, 0), Color(0.95, 0.32, 0.88), true, false)

	# Downtown Skyline & ATM Plaza
	_add_detailed_building(Vector3(-28, 12, -38), Vector3(22, 24, 20), Color(0.24, 0.18, 0.32), Color(1.0, 0.80, 0.18), 22)
	_make_box(Vector3(4.5, 0.12, 4.5), pos_atm + Vector3(0, 0.06, 0), Color(1.0, 0.82, 0.15), true, false)
	_add_detailed_building(Vector3(30, 16, 32), Vector3(24, 32, 24), Color(0.28, 0.16, 0.28), Color(0.98, 0.18, 0.68), 44)
	_add_detailed_building(Vector3(-68, 15, -24), Vector3(22, 30, 24), Color(0.20, 0.18, 0.28), Color(0.45, 0.65, 1.0), 55)
	_add_detailed_building(Vector3(30, 11, -102), Vector3(24, 22, 18), Color(0.22, 0.20, 0.30), Color(0.95, 0.45, 0.20), 66)
	_add_detailed_building(Vector3(-88, 10, -100), Vector3(22, 20, 22), Color(0.26, 0.22, 0.34), Color(0.25, 0.90, 0.70), 77)

	# Industrial Harbor District (South: Z > 85) — Shipping Containers & Dock Heist
	var cont_cols = [Color(0.78, 0.18, 0.18), Color(0.16, 0.42, 0.78), Color(0.85, 0.68, 0.14), Color(0.18, 0.58, 0.32)]
	var cont_pos = [
		Vector3(-34, 2.0, 100), Vector3(-34, 2.0, 114), Vector3(-48, 2.0, 106),
		Vector3(24, 2.0, 98), Vector3(24, 2.0, 112), Vector3(36, 2.0, 105)
	]
	for i in range(cont_pos.size()):
		_make_box(Vector3(4.5, 4.0, 10.5), cont_pos[i], cont_cols[i % cont_cols.size()], false, true)
	_make_box(Vector3(6.5, 0.14, 6.5), pos_docks + Vector3(0, 0.08, 0), Color(1.0, 0.52, 0.12), true, false)

	# Palm Trees along Coast & Boulevards
	for z in [-115, -90, -52, -32, -14, 14, 32, 52, 95, 120]:
		_add_palm_tree(Vector3(50, 0, z))
		_add_palm_tree(Vector3(11.5, 0, z))
		_add_palm_tree(Vector3(-11.5, 0, z))

	# Outer Map Bounds
	_make_box(Vector3(290, 6, 2), Vector3(-20, 3, -140), Color(0.1, 0.1, 0.14), false, true)
	_make_box(Vector3(290, 6, 2), Vector3(-20, 3, 140), Color(0.1, 0.1, 0.14), false, true)
	_make_box(Vector3(2, 6, 290), Vector3(-140, 3, 0), Color(0.1, 0.1, 0.14), false, true)

# ==============================================================================
# VEHICLES (CARJACKABLE + HEALTH + SMOKE/FIRE)
# ==============================================================================
func _spawn_vehicle(v_name: String, pos: Vector3, yaw_deg: float, paint_col: Color, max_hp: float, is_ai: bool, axis := "z", sign_dir := -1.0, spd := 13.0) -> Dictionary:
	var body = CharacterBody3D.new()
	body.position = pos
	body.rotation_degrees.y = yaw_deg

	var paint = StandardMaterial3D.new()
	paint.albedo_color = paint_col; paint.metallic = 0.65; paint.roughness = 0.22

	var ch = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = Vector3(2.15, 0.70, 4.50); bm.material = paint
	ch.mesh = bm; ch.position = Vector3(0, 0.15, 0); body.add_child(ch)

	var cab = MeshInstance3D.new()
	var cm = BoxMesh.new(); cm.size = Vector3(1.78, 0.56, 2.05)
	var glass = StandardMaterial3D.new(); glass.albedo_color = Color(0.06, 0.08, 0.14); glass.metallic = 0.85; glass.roughness = 0.08
	cm.material = glass; cab.mesh = cm; cab.position = Vector3(0, 0.72, 0.18); body.add_child(cab)

	# Headlights
	var hl_mat = StandardMaterial3D.new(); hl_mat.albedo_color = Color(0.95, 0.98, 1.0); hl_mat.emission_enabled = true; hl_mat.emission = Color(0.85, 0.95, 1.0); hl_mat.emission_energy_multiplier = 3.0
	for hx in [-0.72, 0.72]:
		var hl = MeshInstance3D.new(); var hm = BoxMesh.new(); hm.size = Vector3(0.45, 0.16, 0.12); hm.material = hl_mat
		hl.mesh = hm; hl.position = Vector3(hx, 0.22, -2.24); body.add_child(hl)

	# Brake Lights
	var brake_mat = StandardMaterial3D.new(); brake_mat.albedo_color = Color(0.95, 0.08, 0.12); brake_mat.emission_enabled = true; brake_mat.emission = Color(1.0, 0.08, 0.10); brake_mat.emission_energy_multiplier = 1.6
	var tl = MeshInstance3D.new(); var tlm = BoxMesh.new(); tlm.size = Vector3(1.85, 0.15, 0.10); tlm.material = brake_mat
	tl.mesh = tlm; tl.position = Vector3(0, 0.28, 2.24); body.add_child(tl)

	# Damage Smoke / Fire Plume on Hood
	var smoke = MeshInstance3D.new()
	var sm = SphereMesh.new(); sm.radius = 0.55
	var smat = StandardMaterial3D.new(); smat.albedo_color = Color(0.35, 0.35, 0.38, 0.85); smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat; smoke.mesh = sm; smoke.position = Vector3(0, 0.95, -1.45); smoke.visible = false
	body.add_child(smoke)

	# Wheels
	var wheels: Array[Node3D] = []
	var front_pivots: Array[Node3D] = []
	var tire_mat = StandardMaterial3D.new(); tire_mat.albedo_color = Color(0.08, 0.08, 0.10)
	var rim_mat = StandardMaterial3D.new(); rim_mat.albedo_color = Color(0.82, 0.85, 0.90); rim_mat.metallic = 0.85
	var w_offsets = [Vector3(-1.05, -0.22, -1.40), Vector3(1.05, -0.22, -1.40), Vector3(-1.05, -0.22, 1.40), Vector3(1.05, -0.22, 1.40)]
	for i in range(4):
		var piv = Node3D.new(); piv.position = w_offsets[i]; body.add_child(piv)
		if i < 2: front_pivots.append(piv)
		var wh = Node3D.new(); piv.add_child(wh); wheels.append(wh)
		var tire = MeshInstance3D.new(); var tm = CylinderMesh.new(); tm.top_radius = 0.36; tm.bottom_radius = 0.36; tm.height = 0.28; tm.material = tire_mat
		tire.mesh = tm; tire.rotation_degrees.z = 90; wh.add_child(tire)
		var rim = MeshInstance3D.new(); var rm = CylinderMesh.new(); rm.top_radius = 0.20; rm.bottom_radius = 0.20; rm.height = 0.30; rm.material = rim_mat
		rim.mesh = rm; rim.rotation_degrees.z = 90; wh.add_child(rim)

	var col = CollisionShape3D.new(); var bs = BoxShape3D.new(); bs.size = Vector3(2.2, 1.25, 4.55); col.shape = bs
	body.add_child(col)
	add_child(body)

	var v = {
		"name": v_name, "body": body, "paint_mat": paint, "orig_color": paint_col,
		"brake_mat": brake_mat, "smoke": smoke, "smoke_mat": smat,
		"wheels": wheels, "front_pivots": front_pivots,
		"hp": max_hp, "max_hp": max_hp, "speed": spd if is_ai else 0.0,
		"yaw": deg_to_rad(yaw_deg), "steer_vis": 0.0,
		"is_ai": is_ai, "axis": axis, "sign": sign_dir, "ai_max": spd, "top_speed": 36.0 if max_hp <= 115 else 30.0
	}
	vehicles.append(v)
	return v

func _build_vehicles() -> void:
	# Player Starter Sports Coupe
	_spawn_vehicle("Solis GT", Vector3(-11.5, 0.65, 16), 0.0, Color(0.92, 0.14, 0.36), 110.0, false)
	# Parked Pier Exotic
	_spawn_vehicle("Coastal Spyder", Vector3(104, 1.25, -2.2), 90.0, Color(0.98, 0.82, 0.12), 100.0, false)
	# Ambient Traffic Cars (All Carjackable!)
	_spawn_vehicle("Neon Coupe",   Vector3( 4.2, 0.65,  55),   0.0, Color(0.18, 0.55, 0.88), 100.0, true, "z", -1.0, 14.0)
	_spawn_vehicle("Bay Sedan",    Vector3( 4.2, 0.65, -45),   0.0, Color(0.84, 0.86, 0.90), 120.0, true, "z", -1.0, 12.5)
	_spawn_vehicle("Palm Cruiser", Vector3(-4.2, 0.65, -60), 180.0, Color(0.20, 0.78, 0.48), 115.0, true, "z",  1.0, 13.5)
	_spawn_vehicle("Harbor SUV",   Vector3(-4.2, 0.65,  38), 180.0, Color(0.62, 0.30, 0.85), 145.0, true, "z",  1.0, 11.5)
	_spawn_vehicle("Sunset Taxi",  Vector3(-55,  0.65,  4.2), -90.0, Color(0.95, 0.76, 0.12), 110.0, true, "x",  1.0, 13.0)
	_spawn_vehicle("Coast Runner", Vector3( 36,  0.65, -4.2),  90.0, Color(0.94, 0.44, 0.16), 105.0, true, "x", -1.0, 13.5)
	_spawn_vehicle("Hills GT",     Vector3(-48,  0.65, -68),  -90.0, Color(0.25, 0.82, 0.92), 110.0, true, "x",  1.0, 14.0)
	_spawn_vehicle("Dock Truck",   Vector3( 30,  0.65,  72),   90.0, Color(0.76, 0.24, 0.24), 150.0, true, "x", -1.0, 11.0)

func _damage_vehicle(v: Dictionary, amount: float) -> void:
	if v["hp"] <= 0.0: return
	v["hp"] = maxf(0.0, v["hp"] - amount)
	if v["hp"] <= 0.0:
		v["is_ai"] = false
		v["speed"] = 0.0
		v["paint_mat"].albedo_color = Color(0.12, 0.12, 0.14)
		v["smoke"].visible = true
		v["smoke_mat"].albedo_color = Color(1.0, 0.32, 0.05, 0.9)
		v["smoke_mat"].emission_enabled = true
		v["smoke_mat"].emission = Color(1.0, 0.35, 0.05)
		v["smoke_mat"].emission_energy_multiplier = 3.5
		if active_veh_idx != -1 and vehicles[active_veh_idx] == v:
			_exit_vehicle()
			player_hp = maxf(10.0, player_hp - 20.0)
			_toast(v["name"] + " WRECKED! Bailed out (-20 HP).")
	elif v["hp"] < v["max_hp"] * 0.28:
		v["smoke"].visible = true
		v["smoke_mat"].albedo_color = Color(1.0, 0.42, 0.08, 0.88)
		v["smoke_mat"].emission_enabled = true
		v["smoke_mat"].emission = Color(1.0, 0.35, 0.05)
		v["smoke_mat"].emission_energy_multiplier = 2.5
	elif v["hp"] < v["max_hp"] * 0.58:
		v["smoke"].visible = true
		v["smoke_mat"].albedo_color = Color(0.45, 0.45, 0.48, 0.72)
		v["smoke_mat"].emission_enabled = false

# ==============================================================================
# HUMANOIDS, PLAYER, POLICE & PEDESTRIANS
# ==============================================================================
func _build_humanoid_rig(shirt_col: Color, pants_col: Color, with_shades := false) -> Dictionary:
	var rig = Node3D.new()
	var leg_mat = StandardMaterial3D.new(); leg_mat.albedo_color = pants_col
	for lx in [-0.14, 0.14]:
		var leg = MeshInstance3D.new(); var lm = CapsuleMesh.new(); lm.radius = 0.105; lm.height = 0.80; lm.material = leg_mat
		leg.mesh = lm; leg.position = Vector3(lx, -0.45, 0); rig.add_child(leg)
	var torso = MeshInstance3D.new(); var tm = BoxMesh.new(); tm.size = Vector3(0.52, 0.66, 0.28)
	var tmat = StandardMaterial3D.new(); tmat.albedo_color = shirt_col; tm.material = tmat
	torso.mesh = tm; torso.position = Vector3(0, 0.18, 0); rig.add_child(torso)
	var head = MeshInstance3D.new(); var hm = SphereMesh.new(); hm.radius = 0.19
	var hmat = StandardMaterial3D.new(); hmat.albedo_color = Color(0.84, 0.66, 0.54); hm.material = hmat
	head.mesh = hm; head.position = Vector3(0, 0.71, 0); rig.add_child(head)
	if with_shades:
		var sh = MeshInstance3D.new(); var sm = BoxMesh.new(); sm.size = Vector3(0.32, 0.08, 0.12)
		var smat = StandardMaterial3D.new(); smat.albedo_color = Color(0.05, 0.05, 0.08); smat.metallic = 0.8; sm.material = smat
		sh.mesh = sm; sh.position = Vector3(0, 0.73, 0.16); rig.add_child(sh)
	return {"rig": rig, "torso_mat": tmat}

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(-9.5, 1.0, 12)
	var built = _build_humanoid_rig(characters[0]["shirt"], Color(0.14, 0.16, 0.22), true)
	player_rig = built["rig"]; player_torso_mat = built["torso_mat"]
	player.add_child(player_rig)

	var gun = MeshInstance3D.new(); var gm = BoxMesh.new(); gm.size = Vector3(0.10, 0.14, 0.42)
	var gmat = StandardMaterial3D.new(); gmat.albedo_color = Color(0.12, 0.13, 0.16); gmat.metallic = 0.85; gm.material = gmat
	gun.mesh = gm; gun.position = Vector3(0.32, 0.24, 0.34); player_rig.add_child(gun)

	muzzle_light = OmniLight3D.new(); muzzle_light.position = Vector3(0.32, 0.28, 0.65)
	muzzle_light.light_color = Color(1.0, 0.82, 0.35); muzzle_light.light_energy = 5.0; muzzle_light.omni_range = 7.0; muzzle_light.visible = false
	player_rig.add_child(muzzle_light)

	player_duffel = MeshInstance3D.new(); var dm = BoxMesh.new(); dm.size = Vector3(0.46, 0.36, 0.24)
	var dmat = StandardMaterial3D.new(); dmat.albedo_color = Color(0.12, 0.32, 0.16); dm.material = dmat
	player_duffel.mesh = dm; player_duffel.position = Vector3(0, 0.20, -0.26); player_duffel.visible = false
	player_rig.add_child(player_duffel)

	player_col = CollisionShape3D.new(); var cs = CapsuleShape3D.new(); cs.radius = 0.38; cs.height = 1.75; player_col.shape = cs
	player.add_child(player_col); add_child(player)

func _build_cop() -> void:
	cop = CharacterBody3D.new(); cop.position = Vector3(50, 0.65, -50); cop.visible = false
	var body = MeshInstance3D.new(); var bm = BoxMesh.new(); bm.size = Vector3(2.15, 0.78, 4.6)
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.08, 0.10, 0.15); mat.metallic = 0.45; bm.material = mat
	body.mesh = bm; body.position = Vector3(0, 0.15, 0); cop.add_child(body)
	var cab = MeshInstance3D.new(); var cm = BoxMesh.new(); cm.size = Vector3(1.85, 0.58, 2.1)
	var wmat = StandardMaterial3D.new(); wmat.albedo_color = Color(0.92, 0.94, 0.96); cm.material = wmat
	cab.mesh = cm; cab.position = Vector3(0, 0.72, 0.1); cop.add_child(cab)

	cop_light_l = MeshInstance3D.new(); var lm1 = BoxMesh.new(); lm1.size = Vector3(0.65, 0.20, 0.32)
	var m1 = StandardMaterial3D.new(); m1.albedo_color = Color(1, 0.1, 0.1); m1.emission_enabled = true; m1.emission = Color(1, 0.1, 0.1); m1.emission_energy_multiplier = 4.0
	lm1.material = m1; cop_light_l.mesh = lm1; cop_light_l.position = Vector3(-0.36, 1.12, 0.1); cop.add_child(cop_light_l)

	cop_light_r = MeshInstance3D.new(); var lm2 = BoxMesh.new(); lm2.size = Vector3(0.65, 0.20, 0.32)
	var m2 = StandardMaterial3D.new(); m2.albedo_color = Color(0.1, 0.35, 1.0); m2.emission_enabled = true; m2.emission = Color(0.1, 0.35, 1.0); m2.emission_energy_multiplier = 4.0
	lm2.material = m2; cop_light_r.mesh = lm2; cop_light_r.position = Vector3(0.36, 1.12, 0.1); cop.add_child(cop_light_r)

	var col = CollisionShape3D.new(); var bs = BoxShape3D.new(); bs.size = Vector3(2.2, 1.25, 4.6); col.shape = bs
	cop.add_child(col); add_child(cop)

	cop_officer = CharacterBody3D.new(); cop_officer.position = Vector3(46, 1.0, -46); cop_officer.visible = false
	var ob = _build_humanoid_rig(Color(0.10, 0.18, 0.42), Color(0.08, 0.10, 0.16), true)
	cop_officer.add_child(ob["rig"])
	var ocol = CollisionShape3D.new(); var ocs = CapsuleShape3D.new(); ocs.radius = 0.40; ocs.height = 1.75; ocol.shape = ocs
	cop_officer.add_child(ocol); add_child(cop_officer)

func _spawn_ped(pos: Vector3, dir: Vector3, shirt: Color, fleeing := false) -> void:
	var body = CharacterBody3D.new(); body.position = pos
	var built = _build_humanoid_rig(shirt, Color(0.20, 0.22, 0.28), false)
	body.add_child(built["rig"])
	var col = CollisionShape3D.new(); var cs = CapsuleShape3D.new(); cs.radius = 0.36; cs.height = 1.7; col.shape = cs
	body.add_child(col); add_child(body)
	peds.append({
		"body": body, "rig": built["rig"], "dir": dir,
		"state": "flee" if fleeing else "walk", "speed": 2.7, "hp": 50.0, "flee_timer": 8.0 if fleeing else 0.0
	})

func _build_pedestrians() -> void:
	var pal = [Color(0.95, 0.62, 0.20), Color(0.25, 0.82, 0.65), Color(0.85, 0.35, 0.78), Color(0.92, 0.88, 0.35), Color(0.35, 0.60, 0.95)]
	var spawns = [
		[Vector3(10, 1, -40), Vector3(0, 0, 1)], [Vector3(10, 1, 20), Vector3(0, 0, -1)],
		[Vector3(-10, 1, -25), Vector3(0, 0, 1)], [Vector3(-10, 1, 35), Vector3(0, 0, -1)],
		[Vector3(24, 1, 10), Vector3(-1, 0, 0)], [Vector3(-30, 1, 10), Vector3(1, 0, 0)],
		[Vector3(44, 1, -18), Vector3(0, 0, 1)], [Vector3(82, 1.5, 0), Vector3(1, 0, 0)],
		[Vector3(-24, 1, -84), Vector3(1, 0, 0)], [Vector3(-12, 1, 96), Vector3(0, 0, 1)]
	]
	for i in range(spawns.size()):
		_spawn_ped(spawns[i][0], spawns[i][1], pal[i % pal.size()], false)

func _build_camera() -> void:
	cam = Camera3D.new(); cam.position = Vector3(0, 8, 16); add_child(cam)

func _build_hud() -> void:
	var layer = CanvasLayer.new(); add_child(layer)

	reticle_ui = ReticleOverlay.new(); reticle_ui.host = self
	reticle_ui.set_anchors_preset(Control.PRESET_FULL_RECT); reticle_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(reticle_ui)

	var panel = PanelContainer.new(); panel.position = Vector2(16, 14)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.13, 0.78); sb.border_color = Color(0.25, 0.85, 0.98, 0.65)
	sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb); layer.add_child(panel)

	var vbox = VBoxContainer.new(); panel.add_child(vbox)
	hud_stats = Label.new(); hud_stats.add_theme_font_size_override("font_size", 16); vbox.add_child(hud_stats)
	hud_heat = Label.new(); hud_heat.add_theme_font_size_override("font_size", 15); hud_heat.modulate = Color(1.0, 0.45, 0.38); vbox.add_child(hud_heat)

	hud_prompt = Label.new()
	hud_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_prompt.position = Vector2(-260, 18); hud_prompt.custom_minimum_size = Vector2(520, 32)
	hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_prompt.add_theme_font_size_override("font_size", 18); hud_prompt.modulate = Color(0.35, 1.0, 0.72)
	layer.add_child(hud_prompt)

	hud_toast = Label.new()
	hud_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_toast.position = Vector2(-340, 50); hud_toast.custom_minimum_size = Vector2(680, 32)
	hud_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_toast.add_theme_font_size_override("font_size", 16); hud_toast.modulate = Color(1.0, 0.94, 0.62)
	layer.add_child(hud_toast)

	minimap = MiniMap.new(); minimap.host = self
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -168; minimap.offset_top = 14; minimap.offset_right = -16; minimap.offset_bottom = 186
	layer.add_child(minimap)

	touch_ui = TouchControls.new(); touch_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_ui.on_action = Callable(self, "_on_touch_action")
	layer.add_child(touch_ui)

# ==============================================================================
# HELPERS, CARJACKING & ACTIONS
# ==============================================================================
func _get_player_pos() -> Vector3:
	return vehicles[active_veh_idx]["body"].global_position if active_veh_idx != -1 else player.global_position

func _get_district_name(p: Vector3) -> String:
	for intr in interiors:
		if p.x >= intr["min"].x and p.x <= intr["max"].x and p.z >= intr["min"].z and p.z <= intr["max"].z:
			return "IN: " + intr["name"]
	if p.x > 55.0: return "SOLIS BEACH & PIER"
	if p.z > 65.0: return "INDUSTRIAL HARBOR"
	if p.z < -62.0: return "PALM HILLS MOTEL"
	return "DOWNTOWN STRIP"

func _is_inside_interior(p: Vector3) -> bool:
	for intr in interiors:
		if p.x >= intr["min"].x and p.x <= intr["max"].x and p.z >= intr["min"].z and p.z <= intr["max"].z:
			return true
	return false

func _find_nearest_vehicle(max_dist: float) -> int:
	var best_idx := -1
	var best_d := max_dist
	for i in range(vehicles.size()):
		if vehicles[i]["hp"] <= 0.0: continue
		var d = player.global_position.distance_to(vehicles[i]["body"].global_position)
		if d < best_d:
			best_d = d; best_idx = i
	return best_idx

func _toggle_vehicle() -> void:
	if active_veh_idx != -1:
		_exit_vehicle()
		return
	var idx = _find_nearest_vehicle(6.0)
	if idx == -1:
		_toast("No drivable vehicle nearby.")
		return
	var v = vehicles[idx]
	if v["is_ai"]:
		# CARJACKING!
		v["is_ai"] = false
		v["speed"] = 0.0
		var eject_pos = v["body"].global_position + v["body"].global_transform.basis.x * 2.4 + Vector3(0, 0.4, 0)
		_spawn_ped(eject_pos, Vector3(1, 0, 0), Color(0.88, 0.45, 0.25), true)
		_alert_pedestrians(v["body"].global_position, 18.0)
		_trigger_heat(1, "CARJACKED " + v["name"] + "! Driver fled & called patrol!")
	else:
		_toast("Entered " + v["name"] + " (" + str(int(v["hp"])) + "% HP)")
	active_veh_idx = idx
	player.visible = false
	player_col.disabled = true

func _exit_vehicle() -> void:
	if active_veh_idx == -1: return
	var v = vehicles[active_veh_idx]
	v["speed"] = 0.0
	player.global_position = v["body"].global_position + v["body"].global_transform.basis.x * 2.5 + Vector3(0, 0.5, 0)
	active_veh_idx = -1
	player.visible = true
	player_col.disabled = false

func _try_zone_action() -> void:
	var pos = _get_player_pos()
	if pos.distance_to(pos_store) < 5.5:
		if not store_robbed:
			store_robbed = true; carried_cash += 2500
			if cctv_destroyed:
				reputation += 1
				_trigger_heat(1, "SOLIS MART ROBBED (+$2,500)! CCTV disabled — light patrol!")
			else:
				flag_cctv = true
				_trigger_heat(2, "SOLIS MART ROBBED (+$2,500)! CCTV + Outfit Flagged!")
		else: _toast("Register empty. Bank loot at ATM or Palm Motel.")
	elif pos.distance_to(pos_docks) < 7.0:
		if not docks_robbed:
			docks_robbed = true; carried_cash += 4000
			_trigger_heat(2, "HARBOR CRATE HEIST (+$4,000)! High-speed patrol inbound!")
		else: _toast("Harbor containers already cleared.")
	elif pos.distance_to(pos_pier) < 6.0:
		if not pier_looted:
			pier_looted = true; carried_cash += 1500
			_toast("Grabbed hidden Pier Stash (+$1,500)!")
		else: _toast("Pier stash already claimed.")
	elif pos.distance_to(pos_atm) < 5.5:
		if carried_cash > 0:
			banked_cash += carried_cash; _toast("Banked $" + str(carried_cash) + " at Coastal ATM.")
			carried_cash = 0; store_robbed = false; docks_robbed = false
		else: _toast("No carried cash to deposit.")
	elif pos.distance_to(pos_garage) < 8.0:
		var repaired := false
		if active_veh_idx != -1:
			var v = vehicles[active_veh_idx]
			v["hp"] = v["max_hp"]; v["smoke"].visible = false; v["paint_mat"].albedo_color = v["orig_color"]
			repaired = true
		if heat_level > 0 or repaired:
			_clear_all_heat("Sunset Garage: Vehicle repaired to 100% & heat wiped!")
		else: _toast("Vehicle is mint & heat is clear.")
	elif pos.distance_to(pos_motel) < 5.5:
		player_hp = 100.0; ammo = max_ammo
		if carried_cash > 0:
			banked_cash += carried_cash; carried_cash = 0; store_robbed = false; docks_robbed = false
		_clear_all_heat("Palm Motel Safehouse: Healed, cash banked & heat cleared!")

func _try_trunk_action() -> void:
	if active_veh_idx != -1:
		_toast("Exit car (CAR) to open trunk.")
		return
	var idx = _find_nearest_vehicle(5.5)
	if idx == -1: return
	using_alt_outfit = not using_alt_outfit
	var c = characters[active_char_idx]
	player_torso_mat.albedo_color = c["alt_shirt"] if using_alt_outfit else c["shirt"]
	if flag_outfit:
		flag_outfit = false
		if cop.global_position.distance_to(player.global_position) > 32.0:
			_clear_all_heat("Changed outfit at trunk out of sight — HEAT CLEARED!")
		else: _toast("Outfit flag cleared, but patrol still has visual!")
	elif carried_cash > 0:
		trunk_loot += carried_cash; carried_cash = 0; _toast("Stashed duffel cash in trunk.")
	elif trunk_loot > 0:
		carried_cash += trunk_loot; trunk_loot = 0; _toast("Grabbed duffel cash from trunk.")
	else: _toast("Swapped outfit at vehicle trunk.")

func _on_touch_action(action_id: String) -> void:
	match action_id:
		"car": _toggle_vehicle()
		"act": _try_zone_action()
		"trunk": _try_trunk_action()
		"swap":
			active_char_idx = (active_char_idx + 1) % characters.size()
			using_alt_outfit = false
			player_torso_mat.albedo_color = characters[active_char_idx]["shirt"]
			_toast("Switched to " + characters[active_char_idx]["name"])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _toggle_vehicle()
			KEY_TAB: _on_touch_action("swap")
			KEY_F: _try_zone_action()
			KEY_T: _try_trunk_action()
			KEY_R:
				if active_veh_idx == -1 and ammo < max_ammo and reload_timer <= 0.0:
					reload_timer = 1.15; _toast("Reloading sidearm...")

func _toast(txt: String) -> void:
	status_msg = txt; msg_timer = 5.0

func _clear_all_heat(msg: String) -> void:
	heat_level = 0; flag_cctv = false; flag_outfit = false
	cop.visible = false; cop_officer.visible = false
	_toast(msg)

func _trigger_heat(level: int, msg: String) -> void:
	heat_level = max(heat_level, level); flag_outfit = true
	var p = _get_player_pos()
	if not cop.visible:
		cop.visible = true; cop.global_position = Vector3(clampf(p.x + 42, -120, 48), 0.65, clampf(p.z - 42, -120, 120))
	if not cop_officer.visible and cop_respawn_timer <= 0.0:
		cop_officer.visible = true; cop_officer_hp = 100.0; cop_officer.global_position = cop.global_position + Vector3(3, 0.4, 0)
	_toast(msg)

# ==============================================================================
# COMBAT & FOCUS LOCK
# ==============================================================================
func _spawn_tracer(from_pos: Vector3, to_pos: Vector3, col: Color) -> void:
	var dist = from_pos.distance_to(to_pos)
	if dist < 0.2: return
	var mi = MeshInstance3D.new(); var bm = BoxMesh.new(); bm.size = Vector3(0.055, 0.055, dist)
	var mat = StandardMaterial3D.new(); mat.albedo_color = col; mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 4.5
	bm.material = mat; mi.mesh = bm; add_child(mi)
	mi.global_position = (from_pos + to_pos) * 0.5; mi.look_at(to_pos, Vector3.UP)
	tracers.append({"mesh": mi, "life": 0.11})

func _find_focus_target() -> Node3D:
	if active_veh_idx != -1: return null
	var ppos = player.global_position
	var best: Node3D = null; var best_score := 999.0
	if cop_officer.visible and cop_officer_hp > 0:
		var d = ppos.distance_to(cop_officer.global_position)
		if d < 38.0: best = cop_officer; best_score = d * 0.6
	if not cctv_destroyed and is_instance_valid(cctv_node):
		var d = ppos.distance_to(cctv_node.global_position)
		if d < 28.0 and d < best_score: best = cctv_node; best_score = d
	if focus_active and best == null:
		for p in peds:
			if p["state"] != "down":
				var d = ppos.distance_to(p["body"].global_position)
				if d < 22.0 and d < best_score: best = p["body"]; best_score = d
	return best

func _fire_weapon() -> void:
	if active_veh_idx != -1 or reload_timer > 0.0 or fire_cooldown > 0.0: return
	if ammo <= 0:
		reload_timer = 1.15; _toast("Reloading sidearm..."); return
	ammo -= 1; fire_cooldown = 0.14 if focus_active else 0.22
	muzzle_light.visible = true; muzzle_timer = 0.06

	var origin = player.global_position + Vector3(0, 0.35, 0) + player_rig.global_transform.basis.z * 0.55
	var aim_dir = player_rig.global_transform.basis.z.normalized()
	if locked_target != null and is_instance_valid(locked_target):
		aim_dir = (locked_target.global_position + Vector3(0, 0.35, 0) - origin).normalized()
		player_rig.rotation.y = atan2(aim_dir.x, aim_dir.z)

	var end_pt = origin + aim_dir * 45.0
	var q = PhysicsRayQueryParameters3D.create(origin, end_pt)
	q.exclude = [player.get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		end_pt = hit["position"]
		_handle_bullet_hit(hit["collider"])
	_spawn_tracer(origin, end_pt, Color(0.25, 0.95, 1.0) if focus_active else Color(1.0, 0.85, 0.30))
	_alert_pedestrians(player.global_position, 24.0)
	if ammo == 0: reload_timer = 1.15

func _handle_bullet_hit(collider: Object) -> void:
	var dmg = 45.0 if focus_active else 28.0
	if collider == cctv_node and not cctv_destroyed:
		cctv_destroyed = true; cctv_node.visible = false; cctv_node.process_mode = Node.PROCESS_MODE_DISABLED
		reputation += 1; _toast("CCTV Camera disabled! Solis Mart won't flag your face."); return
	if collider == cop_officer and cop_officer.visible:
		cop_officer_hp -= dmg
		if cop_officer_hp <= 0:
			cop_officer.visible = false; cop_respawn_timer = 9.0; _toast("Officer down! Move before backup arrives.")
		return
	for v in vehicles:
		if collider == v["body"]:
			_damage_vehicle(v, 22.0)
			if v["is_ai"]: v["speed"] = 0.0
			return
	for p in peds:
		if collider == p["body"] and p["state"] != "down":
			p["hp"] -= dmg
			if p["hp"] <= 0:
				p["state"] = "down"; p["rig"].rotation_degrees.x = 90; p["rig"].position.y = -0.65
				reputation -= 2; _trigger_heat(1, "Civilian hit! Witnesses called patrol.")
			else: p["state"] = "flee"; p["flee_timer"] = 8.0
			return

func _alert_pedestrians(center: Vector3, radius: float) -> void:
	for p in peds:
		if p["state"] != "down" and p["body"].global_position.distance_to(center) < radius:
			p["state"] = "flee"; p["flee_timer"] = 7.0

# ==============================================================================
# MAIN PHYSICS LOOP
# ==============================================================================
func _physics_process(delta: float) -> void:
	focus_active = Input.is_key_pressed(KEY_Q) or touch_ui.hold_focus
	Engine.time_scale = lerpf(Engine.time_scale, 0.30 if focus_active else 1.0, 0.22)

	water_mat.emission_energy_multiplier = 0.65 + sin(Time.get_ticks_msec() * 0.002) * 0.2
	player_duffel.visible = carried_cash > 0

	if muzzle_timer > 0.0:
		muzzle_timer -= delta
		if muzzle_timer <= 0.0: muzzle_light.visible = false
	if fire_cooldown > 0.0: fire_cooldown -= delta
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0: ammo = max_ammo; _toast("Sidearm reloaded (12/12).")
	if heat_level == 0 and player_hp < 100.0:
		player_hp = minf(100.0, player_hp + 5.0 * delta)

	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["life"] -= delta
		if tracers[i]["life"] <= 0.0:
			tracers[i]["mesh"].queue_free(); tracers.remove_at(i)

	locked_target = _find_focus_target()
	if touch_ui.hold_fire or Input.is_key_pressed(KEY_J) or (active_veh_idx == -1 and Input.is_key_pressed(KEY_SPACE)):
		_fire_weapon()

	if active_veh_idx != -1:
		_drive_active_vehicle(delta)
	else:
		_move_player(delta)

	_update_ai_vehicles(delta)
	_update_pedestrians(delta)
	if heat_level > 0: _update_police(delta)

	_update_camera(delta)
	_update_hud(delta)
	minimap.queue_redraw()
	reticle_ui.queue_redraw()

func _move_player(delta: float) -> void:
	var dir = Vector3(touch_ui.joy_vec.x, 0, touch_ui.joy_vec.y)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir.length() > 1.0: dir = dir.normalized()
	var spd = 11.5 if (Input.is_key_pressed(KEY_SHIFT) or touch_ui.hold_brake) else 7.2
	player.velocity.x = dir.x * spd; player.velocity.z = dir.z * spd
	player.velocity.y = 0 if player.is_on_floor() else player.velocity.y - 20.0 * delta
	player.move_and_slide()
	if dir.length() > 0.1:
		player_rig.rotation.y = lerp_angle(player_rig.rotation.y, atan2(dir.x, dir.z), clampf(delta * 12.0, 0.0, 1.0))

func _drive_active_vehicle(delta: float) -> void:
	var v = vehicles[active_veh_idx]
	var body: CharacterBody3D = v["body"]
	var throttle := -touch_ui.joy_vec.y
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): throttle += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): throttle -= 1.0
	throttle = clampf(throttle, -1.0, 1.0)

	var steer := -touch_ui.joy_vec.x
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): steer += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): steer -= 1.0
	steer = clampf(steer, -1.0, 1.0)

	var braking = Input.is_key_pressed(KEY_SPACE) or touch_ui.hold_brake or throttle < -0.1
	v["brake_mat"].emission_energy_multiplier = 4.2 if braking else 1.4

	if abs(throttle) > 0.08:
		v["speed"] = clampf(v["speed"] + throttle * 27.0 * delta, -12.0, v["top_speed"])
	else:
		v["speed"] = move_toward(v["speed"], 0.0, 14.0 * delta)
	if Input.is_key_pressed(KEY_SPACE) or touch_ui.hold_brake:
		v["speed"] = move_toward(v["speed"], 0.0, 38.0 * delta)

	if abs(v["speed"]) > 0.5:
		v["yaw"] += steer * 2.4 * (1.0 if v["speed"] > 0 else -1.0) * delta

	body.rotation.y = v["yaw"]
	var prev_spd = abs(v["speed"])
	body.velocity = -body.global_transform.basis.z * v["speed"]
	body.velocity.y = -5.0
	body.move_and_slide()

	# High-speed collision damage
	if prev_spd > 13.0 and body.get_slide_collision_count() > 0:
		for c_i in range(body.get_slide_collision_count()):
			var n = body.get_slide_collision(c_i).get_normal()
			if abs(n.y) < 0.5:
				_damage_vehicle(v, prev_spd * 0.75)
				v["speed"] *= -0.25
				break

	v["steer_vis"] = lerpf(v["steer_vis"], steer * 0.45, clampf(delta * 10.0, 0.0, 1.0))
	for fp in v["front_pivots"]: fp.rotation.y = v["steer_vis"]
	for w in v["wheels"]: w.rotate_x(-v["speed"] * delta * 1.8)

func _update_ai_vehicles(delta: float) -> void:
	var ppos = _get_player_pos()
	for i in range(vehicles.size()):
		var v = vehicles[i]
		# Animate smoke pulse if damaged
		if v["smoke"].visible:
			var sc = 0.85 + sin(Time.get_ticks_msec() * 0.012 + i) * 0.25
			v["smoke"].scale = Vector3(sc, sc * 1.2, sc)
		if not v["is_ai"] or v["hp"] <= 0.0: continue
		var body: CharacterBody3D = v["body"]
		var fwd = -body.global_transform.basis.z
		var blocked := false

		var to_p = ppos - body.global_position; to_p.y = 0
		if to_p.length() < 11.0 and fwd.dot(to_p.normalized()) > 0.65: blocked = true
		if not blocked:
			for other in vehicles:
				if other == v: continue
				var to_o = other["body"].global_position - body.global_position; to_o.y = 0
				if to_o.length() < 9.8 and fwd.dot(to_o.normalized()) > 0.70:
					blocked = true; break

		v["speed"] = move_toward(v["speed"], 0.0 if blocked else v["ai_max"], 24.0 * delta)
		body.velocity = fwd * v["speed"]; body.velocity.y = -4.0
		body.move_and_slide()
		for w in v["wheels"]: w.rotate_x(-v["speed"] * delta * 1.8)

		if v["axis"] == "z":
			if body.position.z < -128.0: body.position.z = 128.0
			elif body.position.z > 128.0: body.position.z = -128.0
		else:
			if body.position.x > 46.0: body.position.x = -125.0
			elif body.position.x < -125.0: body.position.x = 46.0

func _update_pedestrians(delta: float) -> void:
	var ppos = _get_player_pos()
	for p in peds:
		if p["state"] == "down": continue
		var body: CharacterBody3D = p["body"]
		var move_dir: Vector3 = p["dir"]; var spd: float = p["speed"]
		if p["state"] == "flee":
			p["flee_timer"] -= delta
			var away = body.global_position - ppos; away.y = 0
			move_dir = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
			spd = 6.2
			if p["flee_timer"] <= 0.0: p["state"] = "walk"
		else:
			if abs(body.position.x) > 120.0 or abs(body.position.z) > 120.0:
				p["dir"] = -p["dir"]; move_dir = p["dir"]
		body.velocity.x = move_dir.x * spd; body.velocity.z = move_dir.z * spd
		body.velocity.y = 0 if body.is_on_floor() else body.velocity.y - 20.0 * delta
		body.move_and_slide()
		if move_dir.length() > 0.1:
			p["rig"].rotation.y = lerp_angle(p["rig"].rotation.y, atan2(move_dir.x, move_dir.z), clampf(delta * 8.0, 0.0, 1.0))

func _update_police(delta: float) -> void:
	var target = _get_player_pos()
	if cop.visible:
		var to_t = target - cop.global_position; to_t.y = 0
		var dist = to_t.length()
		var flash = int(Time.get_ticks_msec() / 160) % 2 == 0
		cop_light_l.visible = flash; cop_light_r.visible = not flash
		if dist > 4.4:
			var dir = to_t.normalized()
			cop.look_at(cop.global_position + dir, Vector3.UP)
			cop.velocity = dir * 19.0; cop.velocity.y = -4.0; cop.move_and_slide()
			bust_timer = maxf(0.0, bust_timer - delta)
		else:
			bust_timer += delta
			if bust_timer > 1.8:
				_player_busted_or_wasted("BUSTED! Lost unbanked cash. Released downtown."); return

	if cop_respawn_timer > 0.0:
		cop_respawn_timer -= delta
		if cop_respawn_timer <= 0.0 and heat_level > 0:
			cop_officer.visible = true; cop_officer_hp = 100.0; cop_officer.global_position = cop.global_position + Vector3(3, 0.4, 0)

	if cop_officer.visible:
		var to_p = target - cop_officer.global_position; to_p.y = 0; var d = to_p.length()
		cop_officer.velocity.x = to_p.normalized().x * 6.5 if d > 12.0 else 0.0
		cop_officer.velocity.z = to_p.normalized().z * 6.5 if d > 12.0 else 0.0
		cop_officer.velocity.y = 0 if cop_officer.is_on_floor() else cop_officer.velocity.y - 20.0 * delta
		cop_officer.move_and_slide()
		if d > 0.2: cop_officer.look_at(Vector3(target.x, cop_officer.global_position.y, target.z), Vector3.UP)

		cop_fire_cd -= delta
		if d < 26.0 and cop_fire_cd <= 0.0:
			cop_fire_cd = 1.25
			_spawn_tracer(cop_officer.global_position + Vector3(0, 0.5, 0), target + Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6)), Color(1.0, 0.22, 0.22))
			if active_veh_idx != -1:
				_damage_vehicle(vehicles[active_veh_idx], 8.0)
			if randf() < (0.30 if active_veh_idx != -1 else 0.58):
				player_hp -= 11.0
				if player_hp <= 0.0:
					banked_cash = max(0, banked_cash - 250)
					_player_busted_or_wasted("WASTED! Hospital bill -$250 & lost unbanked cash.")

func _player_busted_or_wasted(msg: String) -> void:
	carried_cash = 0; player_hp = 100.0; bust_timer = 0.0
	if active_veh_idx != -1: _exit_vehicle()
	player.global_position = Vector3(-9.5, 1.0, 12)
	_clear_all_heat(msg)

func _update_camera(delta: float) -> void:
	var target = vehicles[active_veh_idx]["body"] if active_veh_idx != -1 else player
	var inside = _is_inside_interior(target.global_position)
	var offset = Vector3(0, 3.0, 5.8) if inside else Vector3(0, 6.8, 12.2)
	if active_veh_idx != -1:
		offset = target.global_transform.basis.z * (7.2 if inside else 10.2) + Vector3(0, 3.0 if inside else 4.6, 0)
	cam.global_position = cam.global_position.lerp(target.global_position + offset, clampf(delta * 7.0, 0.0, 1.0))
	cam.look_at(target.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 56.0 if focus_active else 74.0, 0.16)

func _update_hud(delta: float) -> void:
	if msg_timer > 0: msg_timer -= delta
	var c = characters[active_char_idx]
	var ammo_str = "RELOAD" if reload_timer > 0.0 else ("%d/%d" % [ammo, max_ammo])
	var veh_str = ""
	if active_veh_idx != -1:
		var v = vehicles[active_veh_idx]
		veh_str = "  |  %s: %d%% HP" % [v["name"], int(v["hp"] / v["max_hp"] * 100.0)]
	hud_stats.text = "%s  |  HP: %d%%  |  Ammo: %s  |  Bank: $%d  |  Cash: $%d%s" % [
		c["name"], int(player_hp), ammo_str, banked_cash, carried_cash, veh_str
	]
	if heat_level > 0:
		hud_heat.text = "WANTED %s  |  CCTV: %s  |  OUTFIT: %s" % [
			"★ ★" if heat_level >= 2 else "★", "YES" if flag_cctv else "NO", "FLAGGED" if flag_outfit else "CLEAR"
		]
	else:
		hud_heat.text = "CLEAR • Green: Mart | Cyan: Garage | Pink: Motel | Orange: Docks | Yellow: Pier"

	var pos = _get_player_pos()
	if pos.distance_to(pos_store) < 5.5: hud_prompt.text = "Tap [ACT] to Rob Solis Mart Register (+$2,500)"
	elif pos.distance_to(pos_docks) < 7.0: hud_prompt.text = "Tap [ACT] for Harbor Crate Heist (+$4,000)"
	elif pos.distance_to(pos_pier) < 6.0: hud_prompt.text = "Tap [ACT] to Grab Pier Cash Stash (+$1,500)"
	elif pos.distance_to(pos_atm) < 5.5: hud_prompt.text = "Tap [ACT] to Deposit Cash at ATM"
	elif pos.distance_to(pos_garage) < 8.0: hud_prompt.text = "Tap [ACT] at Sunset Garage (Repair Car & Wipe Heat)"
	elif pos.distance_to(pos_motel) < 5.5: hud_prompt.text = "Tap [ACT] at Palm Motel (Heal, Bank & Clear Heat)"
	elif active_veh_idx == -1:
		var ni = _find_nearest_vehicle(6.0)
		if ni != -1:
			var nv = vehicles[ni]
			hud_prompt.text = ("Tap [CAR] to HIJACK " if nv["is_ai"] else "Tap [CAR] to Drive ") + nv["name"] + "  •  [TRUNK] Disguise"
		else: hud_prompt.text = ""
	else: hud_prompt.text = ""
	hud_toast.text = status_msg if msg_timer > 0 else ""
