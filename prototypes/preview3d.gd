extends SceneTree
## A 3D proof of concept: the same generated map as the game, drawn with real
## geometry (splines for waterways and roads, low-poly models for buildings and
## trees) and photographed from three camera angles. Not part of the game.
##
## Run: xvfb-run godot -s prototypes/preview3d.gd -- <output dir> [level number]

const World := preload("res://scripts/world.gd")
const MapGen := preload("res://scripts/mapgen.gd")
const AutoBuild := preload("res://scripts/autobuild.gd")
const Levels := preload("res://scripts/levels.gd")
const WorldView := preload("res://scripts/world_view.gd")
const Art := preload("res://scripts/art.gd")
const Sprites := preload("res://scripts/sprites.gd")
const L := World.L
const T := World.T
const B := World.B

const MIST := Color("dde2c9")
const MARGIN := 12                 # cells of countryside around the map
const ROAD_STYLE := {
	"carriageway": [0.22, 0.18, Color("8f9a6a"), Color("7f7d79")],
	"lane": [0.15, 0.115, Color("8f9a6a"), Color("a29e95")],
	"gravel": [0.085, 0.06, Color("c2ab7c"), Color("e2cfa3")],
	"tarmac": [0.08, 0.062, Color("a7a39a"), Color("8b8882")],
	"dirt": [0.095, 0.075, Color("8f7656"), Color("b39672")],
}

var world: World
var view: WorldView
var scene: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "."
	var level: int = int(args[1]) - 1 if args.size() > 1 else 6
	world = MapGen.generate(Levels.JOURNEY[level])
	world.unlimited = true
	AutoBuild.run(world)
	var kinds := [World.Tool.PUB, World.Tool.COTTAGE, World.Tool.SHOP, World.Tool.TERRACE, World.Tool.CAFE, World.Tool.WINDMILL]
	var placed := 0
	for y in world.h:
		for x in world.w:
			if placed < 9 and (x * 5 + y * 3) % 11 == 0 and world.place(kinds[placed % kinds.size()], Vector2i(x, y)) == "":
				placed += 1
	# Borrow the 2D view for what it already works out: where bridges go.
	Sprites.ensure_loaded()
	view = WorldView.new()
	root.add_child(view)
	view.visible = false
	view.set_world(world)

	scene = Node3D.new()
	root.add_child(scene)
	_environment()
	_ground()
	_waterways()
	_roads()
	for br in view._bridges:
		_bridge(br)
	_buildings()
	_trees()
	_boats_and_cars()

	var cam := Camera3D.new()
	cam.fov = 24
	cam.far = 400
	scene.add_child(cam)
	cam.current = true
	var target := Vector3(world.w * 0.5, 0, world.h * 0.5)
	for pitch in [32, 55, 78]:
		var p := deg_to_rad(float(pitch))
		var yaw := deg_to_rad(45.0)
		var dir := Vector3(cos(p) * sin(yaw), sin(p), cos(p) * cos(yaw))
		cam.position = target + dir * 42.0
		cam.look_at(target, Vector3.UP)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/p3d_%d.png" % [out, pitch])
		print("saved pitch ", pitch)
	# A close view of a bridge, from a moderate angle.
	if view._bridges.size() > 0:
		var br: Dictionary = view._bridges[0]
		var m: Vector2 = ((br.a as Vector2) + (br.b as Vector2)) * 0.5
		var tgt := Vector3(m.x, 0, m.y)
		for pitch in [40, 62]:
			var p := deg_to_rad(float(pitch))
			cam.fov = 24
			cam.position = tgt + Vector3(cos(p) * 0.707, sin(p), cos(p) * 0.707) * 9.0
			cam.look_at(tgt, Vector3.UP)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/p3d_bridge%d.png" % [out, pitch])
	quit()


# --- Scene ------------------------------------------------------------------------

func _mat(col: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic_specular = 0.0
	m.vertex_color_use_as_albedo = true
	return m


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = MIST
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9efe0")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = MIST
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.55
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	scene.add_child(sun)


# Ground: one plane carrying a painted texture of fields and hedges, so the
# countryside has organic edges without any geometry.
func _ground() -> void:
	var ppc := 12
	var gw := (world.w + 2 * MARGIN) * ppc
	var gh := (world.h + 2 * MARGIN) * ppc
	var img := Image.create(gw, gh, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.title)
	var seeds: Array[Vector2] = []
	var cols: Array[Color] = []
	var count := int((world.w + 2 * MARGIN) * (world.h + 2 * MARGIN) / 14.0)
	for i in count:
		seeds.append(Vector2(rng.randf_range(-MARGIN, world.w + MARGIN), rng.randf_range(-MARGIN, world.h + MARGIN)))
		var pick := rng.randf()
		var kind := 0 if pick < 0.46 else (1 if pick < 0.66 else (2 if pick < 0.8 else (3 if pick < 0.92 else 4)))
		cols.append(Art.FIELD[kind])
	for py in gh:
		for px in gw:
			var p := Vector2(float(px) / ppc - MARGIN, float(py) / ppc - MARGIN)
			var d1 := INF
			var d2 := INF
			var best := 0
			for i in count:
				var d := p.distance_squared_to(seeds[i])
				if d < d1:
					d2 = d1
					d1 = d
					best = i
				elif d < d2:
					d2 = d
			var col := cols[best]
			if sqrt(d2) - sqrt(d1) < 0.045:
				col = Art.HEDGE
			img.set_pixel(px, py, col)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(world.w + 2 * MARGIN, world.h + 2 * MARGIN)
	plane.mesh = pm
	var m := _mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plane.material_override = m
	plane.position = Vector3(world.w * 0.5, 0, world.h * 0.5)
	scene.add_child(plane)
	# Receives the sun's shadows; the texture plane stays the visible ground.


# --- Ribbons along splines ---------------------------------------------------------

# Walks the link graph into chains: runs of cells between junctions and ends.
func _chains(types: Array) -> Array:
	var nbrs := {}
	for k in world.links:
		if world.links[k] in types:
			var cells := world.key_cells(k)
			for i in 2:
				if not nbrs.has(cells[i]):
					nbrs[cells[i]] = []
				nbrs[cells[i]].append(cells[1 - i])
	var used := {}
	var out := []
	var starts := []
	for c in nbrs:
		if nbrs[c].size() != 2:
			starts.append(c)
	for c in nbrs:
		if nbrs[c].size() == 2 and not starts.has(c):
			pass
	for s: Vector2i in starts:
		for n: Vector2i in nbrs[s]:
			if used.has([s, n]):
				continue
			var chain: Array[Vector2i] = [s]
			var prev := s
			var cur := n
			used[[s, n]] = true
			used[[n, s]] = true
			while true:
				chain.append(cur)
				if nbrs[cur].size() != 2:
					break
				var nxt: Vector2i = nbrs[cur][0] if nbrs[cur][0] != prev else nbrs[cur][1]
				if used.has([cur, nxt]):
					break
				used[[cur, nxt]] = true
				used[[nxt, cur]] = true
				prev = cur
				cur = nxt
			out.append(chain)
	return out


# Catmull-Rom spline through points, sampled `n` times per segment.
func _spline(pts: Array[Vector2], n := 6) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if pts.size() < 2:
		return pts
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


func _ribbon(pts: Array[Vector2], half: float, y: float, col: Color) -> void:
	if pts.size() < 2:
		return
	var verts := PackedVector3Array()
	var cs := PackedColorArray()
	var idx := PackedInt32Array()
	for i in pts.size():
		var t := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		if t.length() < 0.0001:
			t = Vector2(1, 0)
		var n := Vector2(-t.y, t.x).normalized() * half
		verts.append(Vector3(pts[i].x + n.x, y, pts[i].y + n.y))
		verts.append(Vector3(pts[i].x - n.x, y, pts[i].y - n.y))
		cs.append(col)
		cs.append(col)
		if i > 0:
			var b := (i - 1) * 2
			idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(Color.WHITE)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)


func _extend(pts: Array[Vector2], cell_a: Vector2i, cell_b: Vector2i) -> Array[Vector2]:
	# Carry a waterway or road that leaves the map straight on into the distance.
	var out := pts.duplicate()
	for end in [[cell_a, 0], [cell_b, 1]]:
		var c: Vector2i = end[0]
		var d := Vector2i.ZERO
		for p in world.portals:
			if p.cell == c:
				d = p.dir
		if world.open_ends.has(c):
			d = world.open_ends[c]
		if d != Vector2i.ZERO:
			var base: Vector2 = out[0] if end[1] == 0 else out[out.size() - 1]
			for k in range(1, 12):
				var q := base + Vector2(d) * k
				if end[1] == 0:
					out.insert(0, q)
				else:
					out.append(q)
	return out


func _chain_points(chain: Array[Vector2i]) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for c in chain:
		pts.append(world.node(c))
	return _spline(_extend(pts, chain[0], chain[chain.size() - 1]))


func _waterways() -> void:
	# Rivers: wide and light.
	for course in world.rivers:
		var cells: Array[Vector2i] = []
		cells.assign(course)
		var pts := _chain_points(cells)
		_ribbon(pts, 0.40, 0.004, Art.RIVER_BANK)
		_ribbon(pts, 0.35, 0.008, Art.RIVER)
	# Canals: narrower, darker, with a towpath and coping.
	for chain in _chains([L.CANAL]):
		var pts := _chain_points(chain)
		_ribbon(pts, 0.34, 0.006, Color("cfc3a6"))
		_ribbon(pts, 0.27, 0.010, Color("9a6a55") if world.is_old(chain[0], chain[1]) else Color("e2dccb"))
		_ribbon(pts, 0.20, 0.014, Art.WATER)
	for chain in _chains([L.DERELICT]):
		var pts := _chain_points(chain)
		_ribbon(pts, 0.27, 0.006, Color("857a5c"))
		_ribbon(pts, 0.2, 0.010, Art.MURK)


func _roads() -> void:
	for chain in _chains([L.ROAD, L.PATH]):
		# Leave out cells under bridges; the bridge carries the road there.
		var runs: Array = [[]]
		for c in chain:
			if view._bridge_of.has(c):
				if not (runs[runs.size() - 1] as Array).is_empty():
					runs.append([])
			else:
				(runs[runs.size() - 1] as Array).append(c)
		var style_name: String = "lane"
		var t := world.link(chain[0], chain[1])
		style_name = world.link_style.get(world.key(chain[0], chain[1]), "lane" if t == L.ROAD else "gravel")
		var st: Array = ROAD_STYLE[style_name]
		for run in runs:
			if run.size() < 2:
				continue
			var cells: Array[Vector2i] = []
			cells.assign(run)
			var pts := _chain_points(cells)
			_ribbon(pts, st[0], 0.016, st[2])
			_ribbon(pts, st[1], 0.020, st[3])
			if style_name == "carriageway":
				var dash: Array[Vector2] = []
				for i in pts.size():
					dash.append(pts[i])
					if dash.size() == 2:
						if (i / 2) % 2 == 0:
							_ribbon(dash, 0.012, 0.024, Color("f1ece0"))
						dash = [pts[i]]
	# The approaches to each bridge.
	for br in view._bridges:
		var st: Array = ROAD_STYLE[br.line_style]
		for app in [br.app1, br.app2]:
			var pts: Array[Vector2] = []
			for q: Vector2 in app:
				pts.append(q)
			_ribbon(pts, st[0], 0.016, st[2])
			_ribbon(pts, st[1], 0.020, st[3])


# A bridge swept along its deck: arch or beam, with an open space under it.
func _bridge(br: Dictionary) -> void:
	var a: Vector2 = br.a
	var b: Vector2 = br.b
	var style: String = br.style
	var wall := {"brick": Art.BRICK, "stone": Color("c3b8a0"), "concrete": Color("bdbcb6")}[style] as Color
	var hw: float = 0.18 if br.is_road else 0.12
	var along := (b - a).normalized()
	var side := Vector2(-along.y, along.x) * hw
	var steps := 14
	var open_frac: float = br.open_frac
	var lo := int(round(steps * (1.0 - open_frac) * 0.5))
	var hi := steps - lo
	var clear := 0.20            # crown height above the water, in cells
	var verts := PackedVector3Array()
	var cs := PackedColorArray()
	var idx := PackedInt32Array()
	var add_quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
		var base := verts.size()
		verts.append_array([p0, p1, p2, p3])
		for k in 4:
			cs.append(col)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var deck_h := func(i: int) -> float:
		var t := float(i) / steps
		if style == "concrete":
			return clear * smoothstep(0.0, 0.18, minf(t, 1.0 - t)) * 0.8
		return clear * sin(t * PI)
	for i in steps:
		var p0 := a.lerp(b, float(i) / steps)
		var p1 := a.lerp(b, float(i + 1) / steps)
		var h0: float = deck_h.call(i)
		var h1: float = deck_h.call(i + 1)
		# Deck.
		add_quad.call(Vector3(p0.x - side.x, h0 + 0.02, p0.y - side.y), Vector3(p0.x + side.x, h0 + 0.02, p0.y + side.y),
			Vector3(p1.x + side.x, h1 + 0.02, p1.y + side.y), Vector3(p1.x - side.x, h1 + 0.02, p1.y - side.y), Color("7f7d79"))
		for sd: float in [-1.0, 1.0]:
			var q0 := p0 + side * sd
			var q1 := p1 + side * sd
			var r0 := 0.0
			var r1 := 0.0
			if i >= lo and i < hi:
				r0 = maxf(h0 - 0.05, 0.0) if style == "concrete" else deck_h_arch(clear, i - lo, hi - lo) 
				r1 = maxf(h1 - 0.05, 0.0) if style == "concrete" else deck_h_arch(clear, i + 1 - lo, hi - lo)
			# Outer face with the opening, and a parapet on top.
			add_quad.call(Vector3(q0.x, r0, q0.y), Vector3(q1.x, r1, q1.y), Vector3(q1.x, h1 + 0.06, q1.y), Vector3(q0.x, h0 + 0.06, q0.y), wall)
			add_quad.call(Vector3(q0.x, h0 + 0.06, q0.y), Vector3(q1.x, h1 + 0.06, q1.y),
				Vector3(q1.x - side.x * sd * 0.18, h1 + 0.06, q1.y - side.y * sd * 0.18), Vector3(q0.x - side.x * sd * 0.18, h0 + 0.06, q0.y - side.y * sd * 0.18), wall.lightened(0.2))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(Color.WHITE)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	scene.add_child(mi)


func deck_h_arch(clear: float, i: int, n: int) -> float:
	return clear * 0.78 * sin(float(i) / n * PI)


# --- Models: low-poly stand-ins. A real game would load glTF models here. ---------

func _mesh_node(mesh: Mesh, col: Color, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation.y = rot_y
	scene.add_child(mi)
	return mi


func _house(pos: Vector2, size: Vector3, wall: Color, roof: Color, rot: float, ridge := 0.34) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh_node(box, wall, Vector3(pos.x, size.y * 0.5, pos.y), rot)
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x * 1.08, ridge, size.z * 1.1)
	# The prism's ridge runs along its depth; turn it to run along the long side.
	var r := _mesh_node(prism, roof, Vector3(pos.x, size.y + ridge * 0.5, pos.y), rot + PI * 0.5 if size.x > size.z else rot)
	if size.x > size.z:
		prism.size = Vector3(size.z * 1.1, ridge, size.x * 1.08)
	var ch := BoxMesh.new()
	ch.size = Vector3(0.05, 0.12, 0.05)
	_mesh_node(ch, Art.BRICK, Vector3(pos.x + 0.08, size.y + ridge * 0.7, pos.y - 0.05), rot)


func _buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			var kind := world.building(c)
			if kind == B.NONE:
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var rot := rng.randi_range(0, 3) * PI * 0.5
			var plot := BoxMesh.new()
			plot.size = Vector3(0.9, 0.012, 0.9)
			_mesh_node(plot, Color("a9c97b") if kind != B.FARM else Color("cfc39f"), Vector3(p.x, 0.012, p.y))
			match kind:
				B.COTTAGE:
					_house(p, Vector3(0.5, 0.2, 0.34), Color("dcc79a"), Color("c2a05c"), rot)
				B.TERRACE:
					_house(p, Vector3(0.8, 0.24, 0.3), Color("b96a52"), Color("5b6470"), rot, 0.22)
				B.SHOP:
					_house(p, Vector3(0.5, 0.26, 0.4), Color("efe8d8"), Color("5b6470"), rot)
				B.CAFE:
					_house(p, Vector3(0.45, 0.18, 0.36), Color("f3ead2"), Color("4d9a90"), rot, 0.2)
				B.PUB:
					_house(p, Vector3(0.7, 0.28, 0.4), Color("efe8d8"), Color("5b6470"), rot)
				B.MANOR:
					_house(p, Vector3(0.75, 0.34, 0.42), Color("dcc79a"), Color("5b6470"), rot, 0.22)
				B.FARM:
					_house(p, Vector3(0.5, 0.26, 0.34), Color("4a3f38"), Color("a2533d"), rot)
				B.BOATYARD:
					_house(p, Vector3(0.55, 0.22, 0.34), Color("3d3632"), Color("9a5a3f"), rot, 0.18)
				B.WINDMILL:
					var cone := CylinderMesh.new()
					cone.top_radius = 0.1
					cone.bottom_radius = 0.17
					cone.height = 0.6
					_mesh_node(cone, Color("efe7d4"), Vector3(p.x, 0.3, p.y))
					var cap := CylinderMesh.new()
					cap.top_radius = 0.0
					cap.bottom_radius = 0.12
					cap.height = 0.16
					_mesh_node(cap, Color("3d3632"), Vector3(p.x, 0.68, p.y))
					for k in 4:
						var sail := BoxMesh.new()
						sail.size = Vector3(0.05, 0.42, 0.012)
						var n := _mesh_node(sail, Color("f3ecd8"), Vector3(p.x + 0.1, 0.62, p.y))
						n.position += Vector3(0, 0, 0)
						n.rotation.z = k * PI * 0.5 + 0.5
				B.CHURCH:
					_house(p + Vector2(0.12, 0), Vector3(0.5, 0.24, 0.3), Color("cdbf9f"), Color("5b6470"), 0.0)
					var tower := BoxMesh.new()
					tower.size = Vector3(0.2, 0.55, 0.2)
					_mesh_node(tower, Color("cdbf9f"), Vector3(p.x - 0.22, 0.275, p.y))
				B.CARPARK:
					plot.size = Vector3(0.9, 0.014, 0.9)
					_mesh_node(plot, Color("8b8882"), Vector3(p.x, 0.014, p.y))
				B.GARDEN:
					pass


func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if world.terrain_at(c) != T.WOOD:
				continue
			for k in 3:
				var p := Vector2(x + rng.randf_range(0.15, 0.85), y + rng.randf_range(0.15, 0.85))
				var s := rng.randf_range(0.8, 1.25)
				var trunk := CylinderMesh.new()
				trunk.top_radius = 0.015 * s
				trunk.bottom_radius = 0.022 * s
				trunk.height = 0.14 * s
				_mesh_node(trunk, Color("6b5138"), Vector3(p.x, 0.07 * s, p.y))
				if rng.randf() < 0.3:
					var cone := CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.1 * s
					cone.height = 0.32 * s
					_mesh_node(cone, Color("3f6b47"), Vector3(p.x, 0.28 * s, p.y))
				else:
					var ball := SphereMesh.new()
					ball.radius = 0.12 * s
					ball.height = 0.24 * s
					_mesh_node(ball, Color("6a9a52").lerp(Color("8ab868"), rng.randf()), Vector3(p.x, 0.24 * s, p.y))
	for c in world.rivers:
		pass


func _boats_and_cars() -> void:
	if world.portals.size() >= 2:
		var path := world.path_between(world.portals[0].cell, world.portals[1].cell)
		for f in [0.3, 0.62]:
			var i: int = clampi(int(path.size() * f), 1, path.size() - 2)
			var p := world.node(path[i])
			var d := world.node(path[i + 1]) - world.node(path[i - 1])
			var rot := atan2(-d.y, d.x)
			var hull := BoxMesh.new()
			hull.size = Vector3(0.7, 0.045, 0.1)
			_mesh_node(hull, Color("23392f"), Vector3(p.x, 0.04, p.y), rot)
			var cabin := BoxMesh.new()
			cabin.size = Vector3(0.46, 0.07, 0.085)
			_mesh_node(cabin, [Color("2f5a48"), Color("2c4466")][int(f * 10) % 2], Vector3(p.x, 0.09, p.y), rot)
	for chain in _chains([L.ROAD]):
		if chain.size() < 4:
			continue
		var i: int = chain.size() / 2
		var p := world.node(chain[i])
		var d := world.node(chain[i + 1]) - world.node(chain[i - 1])
		var car := BoxMesh.new()
		car.size = Vector3(0.11, 0.045, 0.06)
		_mesh_node(car, Color("c0392b"), Vector3(p.x, 0.04, p.y), atan2(-d.y, d.x))
