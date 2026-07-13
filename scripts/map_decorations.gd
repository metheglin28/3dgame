extends Node3D
## Hand-authored static map layout. Every position here is a fixed literal --
## no randomness, no generation -- so the map is identical every run and on
## every peer, and it can be tuned by editing coordinates directly. It's built
## from code rather than hundreds of .tscn nodes purely for maintainability.
##
## Layout (120x120, town in the middle, one biome per quadrant):
##
##            north (+z)
##     +---------+---------+
##     |  FARM   | FOREST  |
##     |  (NW)   |  (NE)   |
##     +----[ TOWN ]-------+
##     | SNOWY   | CANYON  |
##     | HILLS   |  MAZE   |
##     |  (SW)   |  (SE)   |
##     +---------+---------+
##            south (-z)

const SNOWMAN_SCENE := preload("res://scenes/snowman.tscn")
const SWORD_STONE_SCENE := preload("res://scenes/sword_stone.tscn")
const POND_RIPPLES := preload("res://scripts/pond_ripples.gd")
const COAT_RACK_SCENE := preload("res://scenes/coat_rack.tscn")
const SIGN_LABEL_SCRIPT := preload("res://scripts/faded_label.gd")

const MAP_HALF := 60.0

const FOREST_CANOPY := Color(0.2, 0.5, 0.22, 1)
const FOREST_FLOOR := Color(0.35, 0.58, 0.3, 1)
const TRUNK_BROWN := Color(0.4, 0.25, 0.12, 1)
const PINE_GREEN := Color(0.15, 0.35, 0.22, 1)
const FARM_FIELD := Color(0.75, 0.68, 0.35, 1)
const FENCE_WOOD := Color(0.5, 0.36, 0.2, 1)
const BARN_RED := Color(0.65, 0.15, 0.12, 1)
const BARN_ROOF := Color(0.4, 0.1, 0.08, 1)
const CANYON_ROCK := Color(0.55, 0.33, 0.24, 1)
const CANYON_FLOOR := Color(0.68, 0.45, 0.32, 1)
const SNOW_WHITE := Color(0.92, 0.94, 0.98, 1)
const STONE_GRAY := Color(0.55, 0.53, 0.5, 1)
const BOUNDARY_GRAY := Color(0.5, 0.48, 0.46, 1)
const PATH_GRAY := Color(0.6, 0.58, 0.55, 1)
const GRASS_GREEN := Color(0.45, 0.7, 0.4, 1)

## The farm's duck pond: a shallow square basin (mitered corners come free
## from overlapping full-width shore ramps) sunk into a matching hole in the
## ground. Shin-deep at most -- you wade, you never swim.
const POND_CENTER := Vector2(-25.5, 48.2)
const POND_HALF := 5.6          # hole half-size; shores start here
const POND_FLOOR_HALF := 3.4    # flat mud floor half-size (2.2m of shore slope)
const POND_DEPTH := 0.45
const POND_WATER_Y := -0.12     # water surface; ~0.33 of water over the floor
const POND_MUD := Color(0.4, 0.33, 0.22, 1)
const WATER_COLOR := Color(0.25, 0.5, 0.72, 0.55)

## Canyon maze, hand-drawn: '#' is a solid 5m rock block, '.' is walkable.
## Entrance is on the north edge (row 0, facing the town); the far dead end
## holds a pickup item and Dave, who is lost (see world.tscn).
const MAZE_ROWS: Array[String] = [
	"#.#######",
	"#...#...#",
	"###.#.#.#",
	"#.....#.#",
	"#.###.#.#",
	"#.#...#.#",
	"#.#.###.#",
	"#...#...#",
	"#########",
]
const MAZE_CELL := 5.0
const MAZE_WALL_HEIGHT := 6.0
const MAZE_ORIGIN_X := 12.0   # west edge of the maze
const MAZE_ORIGIN_Z := -12.0  # north edge of the maze (extends toward -z)

## --- underground tunnel network ------------------------------------------
##
## Two levels under the whole map, one circular entrance shaft per quadrant
## (drop in from the surface), three vertical connector shafts between the
## levels, and everywhere climbable via straight switchback ramps -- no
## ladders, no dead ends. Layout below was generated offline with a recursive-backtracker +
## extra-edges pass (see the maze algorithm in scripts/map_decorations.gd's
## history) to GUARANTEE every room has at least two connections, then baked
## here as a literal grid: no randomness at runtime, identical every game.
## '#' = solid rock pillar, '.' = open floor. Odd-indexed rows/columns are the
## connectors between the "room" cells at even indices (standard doubled-grid
## maze representation), so both wide rooms and narrow passages show up
## naturally in the same grid.
const TUNNEL_CELL := 5.0
const LEVEL_A_Y := -6.0
const LEVEL_B_Y := -15.0
const TUNNEL_WALL_HEIGHT := 4.0
const TUNNEL_ROCK := Color(0.3, 0.28, 0.27, 1)
const TUNNEL_FLOOR_COLOR := Color(0.24, 0.22, 0.21, 1)
const TUNNEL_CEILING_COLOR := Color(0.18, 0.17, 0.16, 1)
## Level B, the gem caverns: darker and grayer than Level A's warm brown,
## so the glowing crystals carry the color instead of the rock.
const DEEP_ROCK := Color(0.16, 0.16, 0.19, 1)
const DEEP_FLOOR_COLOR := Color(0.12, 0.12, 0.14, 1)
const DEEP_CEILING_COLOR := Color(0.09, 0.09, 0.11, 1)
const GEM_COLORS: Array[Color] = [
	Color(1.0, 0.3, 0.5),   # rose
	Color(0.3, 0.9, 1.0),   # ice blue
	Color(1.0, 0.8, 0.25),  # gold
	Color(0.4, 1.0, 0.5),   # emerald
	Color(0.8, 0.4, 1.0),   # amethyst
	Color(0.35, 0.5, 1.0),  # sapphire
	Color(1.0, 0.55, 0.2),  # amber
]
const SHAFT_RADIUS := 2.2
const TORCH_COLOR := Color(1.0, 0.65, 0.3, 1)

## The wizard-less tower: a tall stone cylinder with a cone roof standing in
## the void west of the farm, past the map's edge. Its ONLY entrance is a
## corridor from tunnel Level A -- the gate cell below is a Level A rock cell
## the tunnel builder leaves empty so the corridor can pass through it.
## Interior deliberately undesigned for now: one big empty room, sized for
## elbow room (15m across, ~28m of open height) to build into later.
const TOWER_CENTER := Vector2(-76, 40)
const TOWER_INNER_R := 7.5
const TOWER_WALL_T := 1.2
const TOWER_TOP := 22.0    # wall top above grade; cone roof sits on this
const TOWER_BASE := -6.5   # buried foundation; interior floor is Level A depth
const TOWER_SEGMENTS := 16
const TOWER_GATE_CELL := Vector2i(0, 19) # Level A rock cell the corridor pierces
const TOWER_ROOF_COLOR := Color(0.3, 0.34, 0.45, 1)

const LEVEL_A_ORIGIN := Vector2(-57.5, -57.5)
const LEVEL_A_ROWS: Array[String] = [
	"#.#.#####.###.#.#.#.#.#",
	"#.....................#",
	"###.#.#.#.#.#.#.#.#.#.#",
	"#.............#.#.#...#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#...........#.........#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#...........#...#...#.#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#...........#...#.....#",
	"#.###.#.#.#.#.#.#.#.#.#",
	"#.......#.............#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#.....#...............#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#...........#.........#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#...#.............#...#",
	"#.#.#.#.#.#.#.#.#.#.#.#",
	"#.............#.#.....#",
	"#.###.#.#####.#.#.#.#.#",
	"#...............#.....#",
	"#.#.#.#.#.#.#.#.#.###.#",
]

const LEVEL_B_ORIGIN := Vector2(-37.5, -37.5)
const LEVEL_B_ROWS: Array[String] = [
	"#.#.#.#.#.#.#.#",
	"#.............#",
	"#.#.#.#.###.#.#",
	"#...#...#...#.#",
	"#.#.#.#.#.#.#.#",
	"#...#.........#",
	"#.#.#.#.#.#.#.#",
	"#...#.........#",
	"###.#.#.#.#.#.#",
	"#.........#...#",
	"#.#.#.#.#.#.#.#",
	"#.....#...#.#.#",
	"#########.#.#.#",
	"#...#.........#",
	"#.#.#.#.#.#.#.#",
]

## World-space (x, z) of each entrance/connector, snapped exactly onto a
## Level A room center so the shaft drops into open floor, not a pillar.
const ENTRANCE_SHAFTS := {
	"forest": Vector2(30, 40),
	"farm": Vector2(-30, 40),
	"canyon": Vector2(20, -20),
	"snow": Vector2(-30, -30),
}
## Vertical shafts linking Level A down to Level B. Each is also a valid room
## center in both grids (checked when the layout was authored).
const CONNECTOR_SHAFTS: Array[Vector2] = [Vector2(0, 0), Vector2(-20, -20), Vector2(20, 20)]


func _ready() -> void:
	_build_perimeter_walls()
	_build_quadrant_ground()
	_build_town()
	_build_forest()
	_build_cave()
	_build_farm()
	_build_canyon_maze()
	_build_snowy_hills()
	_build_ground_collision()
	_build_tunnels()
	_build_tower()


# --- primitive helpers --------------------------------------------------------

func _add_box(pos: Vector3, size: Vector3, color: Color, collide: bool = true, emissive: bool = false) -> void:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.position = pos
	if collide:
		body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _make_material(color, emissive)
	body.add_child(mesh)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)


func _add_ground_patch(center: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = center
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	# Double-sided: now that the tunnels exist, a player standing underneath
	# can genuinely look up at these, and a single-sided plane is invisible
	# from below by default (that's the "clear floor" bug -- these planes
	# were never reachable from underneath before there was an underneath).
	var mat := _make_material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)


func _add_cylinder(pos: Vector3, top_radius: float, bottom_radius: float, height: float, color: Color, collide: bool = true, emissive: bool = false) -> void:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.position = pos
	if collide:
		body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_radius
	cyl.bottom_radius = bottom_radius
	cyl.height = height
	cyl.radial_segments = 8
	mesh.mesh = cyl
	mesh.material_override = _make_material(color, emissive)
	body.add_child(mesh)
	if collide:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(top_radius, bottom_radius)
		shape.height = height
		col.shape = shape
		body.add_child(col)


func _add_sphere(pos: Vector3, radius: float, color: Color, collide: bool = true) -> void:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.position = pos
	if collide:
		body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	mesh.material_override = _make_material(color)
	body.add_child(mesh)
	if collide:
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		col.shape = shape
		body.add_child(col)


## A snow mound: the VISUAL is a sphere sunk into the ground, but the COLLIDER
## is a convex hull of only the above-ground dome (plus a short skirt below the
## rim so the hull meets the ground with a wall, not a knife edge). A plain
## sphere collider here would silently extend r*1.55 meters underground --
## straight into the tunnel network, blocking corridors with invisible round
## walls, and one mound reached right into the snow entrance shaft.
func _add_mound(x: float, z: float, r: float) -> void:
	var sink := r * 0.55
	_add_sphere(Vector3(x, -sink, z), r, SNOW_WHITE, false)
	var body := StaticBody3D.new()
	body.position = Vector3(x, -sink, z)
	body.collision_layer = 1
	add_child(body)
	var pts := PackedVector3Array()
	var lat0 := asin(sink / r) # latitude (in body-local space) of the ground plane
	var segs := 12
	for ring in range(4):
		var lat := lerpf(lat0, PI * 0.5, float(ring) / 4.0)
		for k in range(segs):
			var a := TAU * float(k) / segs
			pts.append(Vector3(cos(a) * r * cos(lat), r * sin(lat), sin(a) * r * cos(lat)))
	pts.append(Vector3(0, r, 0))
	for k in range(segs):
		var a := TAU * float(k) / segs
		pts.append(Vector3(cos(a) * r * cos(lat0), sink - 0.3, sin(a) * r * cos(lat0)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _make_material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
	return mat


## Round leafy tree: trunk collides, canopy doesn't.
func _add_tree(x: float, z: float, trunk_h: float = 2.5, canopy_r: float = 1.3) -> void:
	_add_cylinder(Vector3(x, trunk_h * 0.5, z), 0.22, 0.3, trunk_h, TRUNK_BROWN)
	_add_sphere(Vector3(x, trunk_h + canopy_r * 0.7, z), canopy_r, FOREST_CANOPY, false)


## Snowy pine: trunk + cone + snow cap.
func _add_pine(x: float, z: float) -> void:
	_add_cylinder(Vector3(x, 1.0, z), 0.2, 0.28, 2.0, TRUNK_BROWN)
	_add_cylinder(Vector3(x, 3.3, z), 0.0, 1.1, 2.6, PINE_GREEN, false)
	_add_sphere(Vector3(x, 4.5, z), 0.3, SNOW_WHITE, false)


func _add_rock(x: float, z: float, radius: float) -> void:
	_add_sphere(Vector3(x, radius * 0.5, z), radius, STONE_GRAY)


func _add_sign(pos: Vector3, text: String) -> void:
	_add_box(pos + Vector3(0, 1.0, 0), Vector3(0.15, 2.0, 0.15), FENCE_WOOD)
	var label := Label3D.new()
	label.set_script(SIGN_LABEL_SCRIPT) # fades the text in only when you're near
	label.position = pos + Vector3(0, 2.4, 0)
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 8
	add_child(label)


## Collision-only slab (no mesh) -- used for the ground tiles, since the
## visual plane already exists separately in world.tscn.
func _add_collision_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


## Visual-only tunnel ceiling (no collision): a single plane facing straight
## DOWN. The player is always underneath looking up, so a downward face is all
## that's ever needed -- and crucially, a third-person camera that rises up
## through the ceiling sees the culled (invisible) back face instead of the
## slab's underside filling the whole screen. A double-sided slab here used to
## blind the camera and hide the player whenever it clipped through. `size.y`
## (the old slab thickness) is ignored now; x/z give the plane extent.
func _add_visual_slab(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = pos
	mesh.rotation.x = PI # flip PlaneMesh's default +Y normal to point down
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	mesh.mesh = plane
	mesh.material_override = _make_material(color) # default CULL_BACK
	add_child(mesh)


## A straight walkable slope whose TOP surface runs exactly from `from` to
## `to` (both points on the walking surface). Anchoring the top face rather
## than the box center means ramp ends sit flush with whatever floor or
## landing they meet -- even a ~0.1m ledge at a seam reads as a wall to the
## capsule (steeper than the 45-degree floor limit) and would stop walkers dead.
func _add_ramp(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var thickness := 0.25
	var x_axis := (to - from).normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5 - y_axis * (thickness * 0.5))
	body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(from.distance_to(to), thickness, width)
	mesh.mesh = box
	mesh.material_override = _make_material(color)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)


func _add_torch(pos: Vector3) -> void:
	_add_sphere(pos, 0.12, TORCH_COLOR, false)
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = TORCH_COLOR
	light.light_energy = 1.3
	light.omni_range = 7.0
	add_child(light)


## Splits a list of Rect2 (XZ footprint) so that a square hole of the given
## half-size is cut out around `hole_center` -- used to punch the tunnel
## entrance/connector shafts through an otherwise solid slab. A single convex
## BoxShape3D can't have a hole in it, so a full slab is instead built as the
## smallest number of rectangular pieces that tile the area minus the holes.
func _rects_minus_holes(rects: Array, holes: Array, half: float) -> Array:
	var result: Array = rects
	for hole in holes:
		var next: Array = []
		for r in result:
			var rect: Rect2 = r
			var x0 := rect.position.x
			var z0 := rect.position.y
			var x1 := x0 + rect.size.x
			var z1 := z0 + rect.size.y
			var hx0: float = hole.x - half
			var hx1: float = hole.x + half
			var hz0: float = hole.y - half
			var hz1: float = hole.y + half
			if hx1 <= x0 or hx0 >= x1 or hz1 <= z0 or hz0 >= z1:
				next.append(rect)  # hole doesn't touch this piece at all
				continue
			# Clip the hole to this rect, then keep the four surrounding strips.
			var cx0 := maxf(hx0, x0)
			var cx1 := minf(hx1, x1)
			var cz0 := maxf(hz0, z0)
			var cz1 := minf(hz1, z1)
			if cz0 > z0:
				next.append(Rect2(Vector2(x0, z0), Vector2(x1 - x0, cz0 - z0)))
			if cz1 < z1:
				next.append(Rect2(Vector2(x0, cz1), Vector2(x1 - x0, z1 - cz1)))
			if cx0 > x0:
				next.append(Rect2(Vector2(x0, cz0), Vector2(cx0 - x0, cz1 - cz0)))
			if cx1 < x1:
				next.append(Rect2(Vector2(cx1, cz0), Vector2(x1 - cx1, cz1 - cz0)))
		result = next
	return result


# --- world edge ---------------------------------------------------------------

func _build_perimeter_walls() -> void:
	var h := MAP_HALF
	# North wall is split around x 44.5..48.5: the goblin cave's first hall
	# crosses the boundary there on its way down (see _build_cave). The hall's
	# own walls and roof seal the gap to the full height of the wall.
	_add_box(Vector3((-h + 44.5) * 0.5, 2, h), Vector3(44.5 + h, 4, 1), BOUNDARY_GRAY)
	_add_box(Vector3((48.5 + h) * 0.5, 2, h), Vector3(h - 48.5, 4, 1), BOUNDARY_GRAY)
	_add_box(Vector3(0, 2, -h), Vector3(h * 2.0, 4, 1), BOUNDARY_GRAY)
	_add_box(Vector3(h, 2, 0), Vector3(1, 4, h * 2.0), BOUNDARY_GRAY)
	_add_box(Vector3(-h, 2, 0), Vector3(1, 4, h * 2.0), BOUNDARY_GRAY)


func _build_quadrant_ground() -> void:
	# The base grass sheet (previously a single 120x120 plane in world.tscn)
	# is tiled here AROUND the duck pond's hole -- an uncut plane would roof
	# the sunken basin and hide the water. Same for the farm's color wash.
	for r in _rects_minus_holes([Rect2(Vector2(-MAP_HALF, -MAP_HALF), Vector2(MAP_HALF * 2.0, MAP_HALF * 2.0))], [POND_CENTER], POND_HALF):
		var rect: Rect2 = r
		_add_ground_patch(Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5), rect.size, GRASS_GREEN)
	# Flat color washes so each quadrant reads at a glance; lifted slightly
	# above the base ground sheet to avoid z-fighting.
	_add_ground_patch(Vector3(35, 0.01, 35), Vector2(46, 46), FOREST_FLOOR)
	for r in _rects_minus_holes([Rect2(Vector2(-58, 12), Vector2(46, 46))], [POND_CENTER], POND_HALF):
		var rect: Rect2 = r
		_add_ground_patch(Vector3(rect.position.x + rect.size.x * 0.5, 0.01, rect.position.y + rect.size.y * 0.5), rect.size, FARM_FIELD)
	_add_ground_patch(Vector3(35, 0.01, -35), Vector2(46, 46), CANYON_FLOOR)
	_add_ground_patch(Vector3(-35, 0.01, -35), Vector2(46, 46), SNOW_WHITE)


# --- center: town --------------------------------------------------------------

func _build_town() -> void:
	# Four houses around the plaza (the lever-door wall from world.tscn cuts
	# the town east-west through the middle and stays the interactive piece).
	_add_house(Vector3(14, 0, 8), Color(0.55, 0.65, 0.85))
	_add_house(Vector3(-14, 0, 8), Color(0.55, 0.8, 0.75))
	_add_house(Vector3(14, 0, -8), Color(0.85, 0.8, 0.5))
	_add_house(Vector3(-14, 0, -8), Color(0.75, 0.6, 0.8))

	# Open-fronted shop at the north end of the plaza, facing the spawn.
	_add_box(Vector3(0, 1.5, 18.2), Vector3(7, 3, 0.4), Color(0.8, 0.7, 0.55))   # back wall
	_add_box(Vector3(-3.3, 1.5, 16), Vector3(0.4, 3, 4.8), Color(0.8, 0.7, 0.55)) # left wall
	_add_box(Vector3(3.3, 1.5, 16), Vector3(0.4, 3, 4.8), Color(0.8, 0.7, 0.55))  # right wall
	_add_box(Vector3(0, 3.2, 16), Vector3(7.6, 0.4, 5.6), Color(0.5, 0.4, 0.3))   # roof
	_add_box(Vector3(0, 0.6, 17), Vector3(3, 1.2, 0.8), Color(0.5, 0.4, 0.3))     # counter

	# A well on the south plaza.
	_add_cylinder(Vector3(6, 0.5, -5), 1.2, 1.2, 1.0, STONE_GRAY)
	_add_box(Vector3(5.2, 1.5, -5), Vector3(0.15, 2.0, 0.15), FENCE_WOOD)
	_add_box(Vector3(6.8, 1.5, -5), Vector3(0.15, 2.0, 0.15), FENCE_WOOD)
	_add_cylinder(Vector3(6, 2.7, -5), 0.0, 1.6, 0.8, BARN_ROOF, false)

	# Lampposts at the plaza corners, with glowing tops.
	for corner in [Vector3(10, 0, 12), Vector3(-10, 0, 12), Vector3(10, 0, -12), Vector3(-10, 0, -12)]:
		_add_cylinder(corner + Vector3(0, 1.5, 0), 0.08, 0.1, 3.0, Color(0.25, 0.25, 0.28))
		_add_sphere(corner + Vector3(0, 3.2, 0), 0.28, Color(1.0, 0.9, 0.5), false)

	# Paths through the plaza (visual only, no collision). The north-south one
	# lines up with the doorway in the town wall.
	_add_ground_patch(Vector3(-0.6, 0.02, 0), Vector2(2, 24), PATH_GRAY)
	_add_ground_patch(Vector3(0, 0.02, 8), Vector2(24, 2), PATH_GRAY)

	# Signposts pointing into each biome, in keeping with the tone.
	_add_sign(Vector3(13, 0, 13), "WHISPERING WOODS")
	_add_sign(Vector3(-13, 0, 13), "OLD MACDONALD'S")
	_add_sign(Vector3(13, 0, -13), "THE LOST CANYONS")
	_add_sign(Vector3(-13, 0, -13), "CHILLY HILLS")


func _add_house(pos: Vector3, wall_color: Color) -> void:
	_add_box(pos + Vector3(0, 2, 0), Vector3(6, 4, 5), wall_color)
	_add_box(pos + Vector3(0, 4.75, 0), Vector3(6.6, 1.5, 5.6), BARN_ROOF)


# --- NE: forest -----------------------------------------------------------------

func _build_forest() -> void:
	# Hand-scattered: staggered so nothing lines up into obvious rows.
	# The NE corner (x>39, z>43-ish) is deliberately left clear of trees --
	# the goblin cave's knoll sits there (see _build_cave).
	var trees := [
		[16, 18, 2.4, 1.3], [21, 15, 2.8, 1.5], [27, 19, 2.2, 1.2], [33, 15, 3.0, 1.6],
		[40, 17, 2.5, 1.3], [47, 14, 2.7, 1.4], [53, 18, 2.3, 1.2],
		[15, 27, 2.9, 1.5], [22, 24, 2.4, 1.2], [29, 26, 2.6, 1.4], [36, 23, 2.2, 1.1],
		[44, 26, 3.1, 1.6], [51, 24, 2.5, 1.3],
		[18, 35, 2.3, 1.3], [26, 33, 2.8, 1.5], [34, 36, 2.4, 1.2], [42, 33, 2.6, 1.4],
		[50, 35, 2.9, 1.5], [56, 30, 2.2, 1.2],
		[15, 44, 2.7, 1.4], [23, 42, 2.3, 1.2], [31, 45, 3.0, 1.6], [39, 43, 2.5, 1.3],
		[37.5, 44, 2.4, 1.3], [56, 39.5, 2.8, 1.5],
		[19, 52, 2.5, 1.3], [28, 54, 2.2, 1.2], [37, 51, 2.7, 1.4], [37, 49.5, 2.4, 1.3],
		[58, 41, 2.6, 1.4],
	]
	for t in trees:
		_add_tree(t[0], t[1], t[2], t[3])
	_add_rock(25, 29, 0.7)
	_add_rock(43, 38, 0.9)
	_add_rock(57.9, 48, 0.6)
	# A stump in a small clearing, for sitting on and contemplating life.
	_add_cylinder(Vector3(33, 0.3, 30), 0.5, 0.55, 0.6, TRUNK_BROWN)

	# The sword in the stone, in the same clearing -- grants the sword-swinging
	# power (see sword_stone.gd).
	var sword_stone := SWORD_STONE_SCENE.instantiate()
	sword_stone.position = Vector3(30, 0, 29)
	add_child(sword_stone)


# --- NE: the goblin cave -----------------------------------------------------------

## An above-ground cave mouth in the forest's NE corner that burrows NORTH in
## one straight line of rooms -- mouth, entry tunnel, goblin warren, long
## snaking hall, main chamber, long snaking hall, loot room -- descending as
## it goes: the warren sits at the surface, the chamber ~4.5m down, the loot
## room ~8.5m down. Rooms are flat (better for goblin leashes and fights);
## all the descent happens on the halls' ramped straights, with flat landings
## at every turn, at ramp-walkable grades.
##
## The line deliberately runs OUT past the map's north edge (z=60): inside
## the map anything below grade would collide with the ground slab and the
## tunnel network, so the descent begins exactly at the boundary, where both
## end. The hall punches through a gap in the north perimeter wall (its own
## walls seal the gap) and everything beyond hangs in the void the future map
## expansion will fill in. Sized for tenants as before: halls and warren are
## goblin-scale in footprint but tall enough (4m+) that the camera
## never crowds in; the chamber has 6.5m of troll headroom.
##
##          [loot]           deepest (-8.5)
##            ~
##         hall 2 (long, snaking, ramped)
##            ~
##        [chamber]          -4.5, campfire, troll-tall
##            ~
##         hall 1 (long, snaking, ramped)
##   ==== map edge z=60 ====  descent starts here
##            |
##        [warren]           surface level
##         [entry]
##          mouth            faces the town
const CAVE_ROCK := Color(0.34, 0.3, 0.27, 1)
const CAVE_FLOOR := Color(0.28, 0.25, 0.22, 1)
const BONE_WHITE := Color(0.92, 0.9, 0.82, 1)
const GOLD := Color(0.95, 0.78, 0.2, 1)
const CHEST_BROWN := Color(0.45, 0.28, 0.12, 1)
const HALL_W := 1.8
const HALL_H := 4.0

func _build_cave() -> void:
	# Stone floor patches for the surface-level rooms (their walking surface
	# is the regular ground); the halls and sunken rooms get real floors.
	_add_ground_patch(Vector3(43.1, 0.03, 44.2), Vector2(3, 3.5), CAVE_FLOOR)  # entry tunnel
	_add_ground_patch(Vector3(42.75, 0.03, 48), Vector2(5.5, 4), CAVE_FLOOR)   # warren

	# Entry tunnel: 3 wide (x 41.6..44.6) x 3.5 high, mouth at z 42.5 facing
	# south toward the town, opening straight into the warren.
	_add_box(Vector3(41.1, 2.0, 44.25), Vector3(1, 4, 3.5), CAVE_ROCK)  # west cheek
	_add_box(Vector3(45.1, 2.0, 44.25), Vector3(1, 4, 3.5), CAVE_ROCK)  # east cheek
	_add_box(Vector3(43.1, 4.25, 44.25), Vector3(5, 0.5, 3.5), CAVE_ROCK)  # tunnel roof
	# A heavy rock brow over the mouth plus two half-buried boulders, so from
	# outside it reads as a proper cave entrance and not a doorway.
	_add_box(Vector3(43.1, 5.4, 43.7), Vector3(7, 2.4, 2.8), CAVE_ROCK)
	_add_sphere(Vector3(40.3, 0.9, 42.2), 1.3, CAVE_ROCK)
	_add_sphere(Vector3(46.3, 0.9, 42.4), 1.3, CAVE_ROCK)

	# Room 1, the goblin warren: interior x 40..45.5, z 46..50, ceiling 2.6,
	# at surface level. Hall 1 leaves through its NORTH wall (the line goes
	# straight through the room, south door to north door).
	_add_box(Vector3(39.5, 2.0, 48), Vector3(1, 4, 6), CAVE_ROCK)          # west wall
	_add_box(Vector3(46, 2.0, 48), Vector3(1, 4, 6), CAVE_ROCK)            # east wall
	_add_box(Vector3(40.3, 2.0, 45.5), Vector3(2.6, 4, 1), CAVE_ROCK)      # south wall, west of the entry
	_add_box(Vector3(45.55, 2.0, 45.5), Vector3(1.9, 4, 1), CAVE_ROCK)     # south wall, east of the entry
	_add_box(Vector3(40.425, 2.0, 50.5), Vector3(2.85, 4, 1), CAVE_ROCK)   # north wall, west of hall 1
	_add_box(Vector3(45.075, 2.0, 50.5), Vector3(2.85, 4, 1), CAVE_ROCK)   # north wall, east of hall 1
	_add_box(Vector3(42.75, 4.25, 48), Vector3(7.5, 0.5, 6), CAVE_ROCK)    # roof
	# A modest stepped knoll on top so the mouth reads as dug into a rock
	# rise (steps under jump height -- players will climb it, that's fine).
	_add_box(Vector3(42.75, 5.0, 48), Vector3(8.5, 1.0, 7), CAVE_ROCK)
	_add_box(Vector3(42.75, 5.75, 48.5), Vector3(5.5, 0.8, 4.5), CAVE_ROCK)

	# Hall 1 (warren -> chamber): ~29m of path. Flat until the map edge, then
	# ramps down 4.5m across three descending straights with flat landings at
	# every turn. Crosses the perimeter wall through a gap cut for it in
	# _build_perimeter_walls.
	_add_corridor([
		Vector3(42.75, 0.03, 51),    # warren north doorway
		Vector3(42.75, 0.03, 55.5),  # flat north, then turn E
		Vector3(46.5, 0.03, 55.5),   # flat east, then turn N
		Vector3(46.5, 0.03, 61),     # flat north across the map edge; descent starts
		Vector3(46.5, -2.4, 67.5),   # long ramp down, then turn W
		Vector3(42.2, -3.5, 67.5),   # ramp down west, then turn N
		Vector3(42.2, -4.5, 72),     # final ramp down to the chamber doorway
	])

	# Room 2, the main chamber: interior x 38.2..46.2, z 73..81, floor -4.5,
	# ceiling 5.5 (troll headroom). Doorways in the south (hall 1) and north
	# (hall 2) walls, with headers since the walls are taller than the halls.
	_add_box(Vector3(42.2, -4.65, 77), Vector3(9.8, 0.3, 9.8), CAVE_FLOOR)                # floor
	_add_box(Vector3(37.7, -1.25, 77), Vector3(1, 7.1, 10), CAVE_ROCK)                    # west wall
	_add_box(Vector3(46.7, -1.25, 77), Vector3(1, 7.1, 10), CAVE_ROCK)                    # east wall
	_add_box(Vector3(39.75, -1.25, 72.5), Vector3(3.1, 7.1, 1), CAVE_ROCK)                # south wall, west of doorway
	_add_box(Vector3(44.9, -1.25, 72.5), Vector3(3.6, 7.1, 1), CAVE_ROCK)                 # south wall, east of doorway
	_add_box(Vector3(42.2, 0.9, 72.5), Vector3(1.8, 2.8, 1), CAVE_ROCK)                   # header over hall 1
	_add_box(Vector3(40.85, -1.25, 81.5), Vector3(5.3, 7.1, 1), CAVE_ROCK)                # north wall, west of hall 2
	_add_box(Vector3(46.0, -1.25, 81.5), Vector3(1.4, 7.1, 1), CAVE_ROCK)                 # north wall, east of hall 2
	_add_box(Vector3(44.4, 0.9, 81.5), Vector3(1.8, 2.8, 1), CAVE_ROCK)                   # header over hall 2
	_add_box(Vector3(42.2, 2.25, 77), Vector3(9.8, 0.5, 10), CAVE_ROCK)                   # roof

	# Hall 2 (chamber -> loot room): ~16m of path, ramping down another 4m.
	_add_corridor([
		Vector3(44.4, -4.5, 82),     # chamber north doorway
		Vector3(44.4, -5.9, 87.3),   # ramp down north, then turn W
		Vector3(39.4, -6.9, 87.3),   # ramp down west, then turn N
		Vector3(39.4, -8.5, 92.5),   # final ramp down to the loot room
	])

	# Room 3, the loot room: interior x 37.4..41.4, z 93.5..97, floor -8.5,
	# ceiling 3.2 -- the deepest point of the cave.
	_add_box(Vector3(39.4, -8.65, 95.25), Vector3(6, 0.3, 4.5), CAVE_FLOOR)               # floor
	_add_box(Vector3(36.9, -6.05, 95.25), Vector3(1, 5.9, 4.5), CAVE_ROCK)                # west wall
	_add_box(Vector3(41.9, -6.05, 95.25), Vector3(1, 5.9, 4.5), CAVE_ROCK)                # east wall
	_add_box(Vector3(39.4, -6.05, 97.5), Vector3(6, 5.9, 1), CAVE_ROCK)                   # north wall
	_add_box(Vector3(37.95, -6.05, 93), Vector3(1.1, 5.9, 1), CAVE_ROCK)                  # south wall, west of doorway
	_add_box(Vector3(40.85, -6.05, 93), Vector3(1.1, 5.9, 1), CAVE_ROCK)                  # south wall, east of doorway
	_add_box(Vector3(39.4, -3.8, 93), Vector3(1.8, 1.4, 1), CAVE_ROCK)                    # header over the doorway
	_add_box(Vector3(39.4, -3.45, 95.25), Vector3(6, 0.5, 5.5), CAVE_ROCK)                # roof

	# --- decor ---
	_add_campfire(42.2, 77, -4.5)
	# Trophy skull pile in the chamber's NW corner...
	_add_skull(Vector3(38.7, -4.3, 80.1), 0.6)
	_add_skull(Vector3(39.3, -4.3, 80.4), -0.9)
	_add_skull(Vector3(38.9, -4.3, 79.6), 2.2)
	_add_skull(Vector3(38.9, -3.95, 80.05), 1.5)
	# ...a couple scattered around the fire...
	_add_skull(Vector3(40.5, -4.3, 75.6), 2.8)
	_add_skull(Vector3(43.9, -4.3, 78.4), -2.0)
	# ...two in the warren, one at a hall landing, one guarding the loot.
	_add_skull(Vector3(40.8, 0.2, 49.2), 1.1)
	_add_skull(Vector3(44.5, 0.2, 46.6), -2.6)
	_add_skull(Vector3(45.9, -2.2, 68.1), 2.4)
	_add_skull(Vector3(38.2, -8.3, 94), -0.4)
	# Skulls on stakes flanking the path to the mouth, facing arrivals.
	for sx: float in [42.0, 44.2]:
		_add_cylinder(Vector3(sx, 0.8, 41.6), 0.06, 0.08, 1.6, TRUNK_BROWN, false)
		_add_skull(Vector3(sx, 1.8, 41.6), 0.0)
	_add_sign(Vector3(46.8, 0, 40.6), "BEWARE: GOBLINS")

	# Torches: rooms plus every hall landing, so the long dark descent always
	# has the next light visible ahead.
	_add_torch(Vector3(42.7, 1.9, 48))        # warren
	_add_torch(Vector3(42.75, 1.9, 55.5))     # hall 1 landings...
	_add_torch(Vector3(46.5, 1.9, 61))
	_add_torch(Vector3(46.5, -0.5, 67.5))
	_add_torch(Vector3(42.2, -1.6, 67.5))
	_add_torch(Vector3(40, -2.4, 77))         # chamber (campfire lights the middle)
	_add_torch(Vector3(44.4, -4, 87.3))       # hall 2 landings...
	_add_torch(Vector3(39.4, -5, 87.3))
	_add_torch(Vector3(39.4, -6.1, 95.25))    # loot room

	# The treasure: a chest and a spill of gold. Not lootable (yet) -- it's
	# set dressing for the goblins to guard once they move in.
	# Chest against the far wall so it doesn't block the doorway.
	_add_box(Vector3(39.4, -8.15, 96.6), Vector3(1.0, 0.7, 0.7), CHEST_BROWN)
	_add_box(Vector3(39.4, -7.72, 96.6), Vector3(1.06, 0.16, 0.76), Color(0.3, 0.18, 0.08, 1), false)
	_add_sphere(Vector3(39.4, -7.55, 96.6), 0.12, GOLD, false)
	_add_cylinder(Vector3(40.4, -8.44, 95.2), 0.6, 0.6, 0.12, GOLD, false)
	_add_cylinder(Vector3(40.1, -8.32, 95.6), 0.4, 0.4, 0.12, GOLD, false)
	_add_cylinder(Vector3(40.8, -8.22, 94.9), 0.25, 0.25, 0.12, GOLD, false)
	_add_box(Vector3(38.6, -8.35, 94.7), Vector3(0.5, 0.3, 0.3), GOLD, false)
	_add_box(Vector3(38.4, -8.4, 95.9), Vector3(0.4, 0.2, 0.25), GOLD, false)


## Builds a fully enclosed corridor (HALL_W x HALL_H) along an axis-aligned 3D
## centerline: ramped-or-flat floors and roofs per straight, side walls tall
## enough to cover each straight's whole slope, and at every interior vertex a
## flat landing (floor, roof, and walls on whichever of its sides aren't
## openings). Each straight must change only x or only z -- y is free, that's
## the slope. The chain's two ends are left open as doorways; the rooms' own
## walls frame them. Landing walls sit 2cm proud of the segment walls' planes
## so overlapping coplanar faces don't z-fight.
func _add_corridor(points: Array, width: float = HALL_W, height: float = HALL_H) -> void:
	var hw := width * 0.5
	var wt := 1.0
	var axes: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		# Straights stop hw short of interior vertices (the landing covers the
		# rest). Chain ends get a short FLAT pad through the doorway before any
		# slope starts: if the ramp began sloping inside the doorway channel,
		# the room floor's edge would sit proud of it as a small ledge -- a
		# step the capsule walks down but reads as a wall when climbing back
		# out (anything much over 0.1m breaks the 45-degree floor limit).
		var fa := a + dir * (hw if i > 0 else 0.9)
		var fb := b - dir * (hw if i < points.size() - 2 else 0.9)
		fa.y = a.y
		fb.y = b.y
		if i == 0:
			_add_box(Vector3(a.x, a.y - 0.125, a.z) + dir * 0.275, _along(dir, 1.25, 0.25, width), CAVE_FLOOR)
			_add_box(Vector3(a.x, a.y + height - 0.125, a.z) + dir * 0.275, _along(dir, 1.25, 0.25, width + 0.4), CAVE_ROCK)
		if i == points.size() - 2:
			_add_box(Vector3(b.x, b.y - 0.125, b.z) - dir * 0.275, _along(dir, 1.25, 0.25, width), CAVE_FLOOR)
			_add_box(Vector3(b.x, b.y + height - 0.125, b.z) - dir * 0.275, _along(dir, 1.25, 0.25, width + 0.4), CAVE_ROCK)
		_add_ramp(fa, fb, width, CAVE_FLOOR)
		_add_ramp(fa + Vector3.UP * height, fb + Vector3.UP * height, width + 0.4, CAVE_ROCK)
		var side := Vector3(dir.z, 0, -dir.x)
		var y_lo := minf(a.y, b.y) - 0.5
		var y_hi := maxf(a.y, b.y) + height + 0.6
		var mid := (fa + fb) * 0.5
		var run := Vector2(fb.x - fa.x, fb.z - fa.z).length()
		for s: float in [-1.0, 1.0]:
			var c := mid + side * (s * (hw + wt * 0.5))
			var size := Vector3(run, y_hi - y_lo, wt) if absf(dir.x) > 0.5 else Vector3(wt, y_hi - y_lo, run)
			_add_box(Vector3(c.x, (y_lo + y_hi) * 0.5, c.z), size, CAVE_ROCK)
	for i in range(1, points.size() - 1):
		var v: Vector3 = points[i]
		var d_in := Vector3(v.x - points[i - 1].x, 0, v.z - points[i - 1].z).normalized()
		var d_out := Vector3(points[i + 1].x - v.x, 0, points[i + 1].z - v.z).normalized()
		_add_box(Vector3(v.x, v.y - 0.125, v.z), Vector3(width, 0.25, width), CAVE_FLOOR)
		_add_box(Vector3(v.x, v.y + height - 0.125, v.z), Vector3(width + 0.4, 0.25, width + 0.4), CAVE_ROCK)
		for axis in axes:
			if axis.is_equal_approx(-d_in) or axis.is_equal_approx(d_out):
				continue # the openings to the previous/next straight
			var c := Vector3(v.x, 0, v.z) + axis * (hw + wt * 0.5 + 0.02)
			var size := Vector3(wt, height + 1.1, width + 2.0 * wt) if absf(axis.x) > 0.5 else Vector3(width + 2.0 * wt, height + 1.1, wt)
			_add_box(Vector3(c.x, v.y + (height + 1.1) * 0.5 - 0.5, c.z), size, CAVE_ROCK)


## A box size whose long dimension runs along the (axis-aligned) direction.
func _along(dir: Vector3, length: float, height: float, width: float) -> Vector3:
	return Vector3(length, height, width) if absf(dir.x) > 0.5 else Vector3(width, height, length)


# --- the tower (west of the farm, past the map edge) ----------------------------

func _build_tower() -> void:
	var cx := TOWER_CENTER.x
	var cz := TOWER_CENTER.y
	var wall_r := TOWER_INNER_R + TOWER_WALL_T * 0.5
	var wall_h := TOWER_TOP - TOWER_BASE
	# The shell: a ring of thick box segments (a 16-gon reads as a cylinder in
	# this art style, and thick boxes can't blind a clipping camera the way a
	# thin tube could). Segment 0 faces east toward the corridor and is
	# skipped -- that's the doorway.
	var chord := 2.0 * wall_r * sin(PI / TOWER_SEGMENTS) + 0.2
	for i in range(TOWER_SEGMENTS):
		if i == 0:
			continue
		var ang := TAU * float(i) / TOWER_SEGMENTS
		var pos := Vector3(cx + cos(ang) * wall_r, (TOWER_BASE + TOWER_TOP) * 0.5, cz + sin(ang) * wall_r)
		_add_yaw_box(pos, Vector3(TOWER_WALL_T, wall_h, chord), -ang, STONE_GRAY)
	# Plug the doorway segment above the corridor's roof so the opening is a
	# door, not a floor-to-battlements slot.
	_add_box(Vector3(cx + wall_r, (TOWER_TOP - 2.2) * 0.5, cz), Vector3(TOWER_WALL_T, TOWER_TOP + 2.2, chord + 0.3), STONE_GRAY)
	# Interior floor: a flat stone disc at Level A depth, where the corridor
	# arrives. Everything above it is deliberately empty for now.
	_add_cylinder(Vector3(cx, -6.15, cz), TOWER_INNER_R + 0.4, TOWER_INNER_R + 0.4, 0.3, TUNNEL_FLOOR_COLOR)
	# Cone roof with a little gold finial. Visual only -- nothing can get up
	# there yet.
	_add_cylinder(Vector3(cx, TOWER_TOP + 3.5, cz), 0.0, TOWER_INNER_R + 2.1, 7.0, TOWER_ROOF_COLOR, false)
	_add_sphere(Vector3(cx, TOWER_TOP + 7.2, cz), 0.35, Color(0.9, 0.75, 0.3, 1), false)

	# The gate: refill the skipped Level A rock cell around a corridor-sized
	# hole (side strips + a header over the corridor roof), then run the
	# corridor from the neighboring tunnel room straight west into the tower.
	var gx := LEVEL_A_ORIGIN.x + TOWER_GATE_CELL.x * TUNNEL_CELL
	var gz := LEVEL_A_ORIGIN.y + TOWER_GATE_CELL.y * TUNNEL_CELL
	_add_box(Vector3(gx + 2.5, LEVEL_A_Y + 2.0, gz + 0.7), Vector3(5, 4, 1.4), TUNNEL_ROCK)
	_add_box(Vector3(gx + 2.5, LEVEL_A_Y + 2.0, gz + 4.3), Vector3(5, 4, 1.4), TUNNEL_ROCK)
	_add_box(Vector3(gx + 2.5, LEVEL_A_Y + 3.8, gz + 2.5), Vector3(5, 0.4, 4.6), TUNNEL_ROCK)
	_add_corridor([
		Vector3(gx + 5.0, LEVEL_A_Y + 0.02, cz),   # west face of the Level A room
		Vector3(cx + TOWER_INNER_R, LEVEL_A_Y + 0.02, cz), # tower's inner wall face
	], 2.2, 3.8)
	_add_torch(Vector3(-58, LEVEL_A_Y + 1.9, cz))
	_add_torch(Vector3(-64, LEVEL_A_Y + 1.9, cz))
	# A pair of torches inside so the big empty room isn't pitch black.
	_add_torch(Vector3(cx + 5.5, LEVEL_A_Y + 2.2, cz + 1.8))
	_add_torch(Vector3(cx + 5.5, LEVEL_A_Y + 2.2, cz - 1.8))


## A box rotated around Y (mesh + collision) -- the tower's wall segments
## need to sit tangent to the circle they form.
func _add_yaw_box(pos: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _make_material(color)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


## A skull: sphere cranium, box jaw, two dark eye sockets. Faces -z at yaw 0.
## Purely decorative, no collision.
func _add_skull(pos: Vector3, yaw: float = 0.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var cranium := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	cranium.mesh = s
	cranium.material_override = _make_material(BONE_WHITE)
	root.add_child(cranium)
	var jaw := MeshInstance3D.new()
	var jb := BoxMesh.new()
	jb.size = Vector3(0.22, 0.12, 0.18)
	jaw.mesh = jb
	jaw.position = Vector3(0, -0.14, -0.06)
	jaw.material_override = _make_material(BONE_WHITE)
	root.add_child(jaw)
	for ex: float in [-0.07, 0.07]:
		var eye := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.06, 0.07, 0.04)
		eye.mesh = eb
		eye.position = Vector3(ex, 0.02, -0.185)
		eye.material_override = _make_material(Color(0.05, 0.05, 0.05, 1))
		root.add_child(eye)


## Ring of stones, crossed logs, an emissive flame cone, and a warm light.
## `y` is the floor height the fire sits on (rooms below grade pass theirs).
func _add_campfire(x: float, z: float, y: float = 0.0) -> void:
	for k in range(7):
		var a := TAU * float(k) / 7.0
		_add_sphere(Vector3(x + cos(a) * 0.8, y + 0.14, z + sin(a) * 0.8), 0.2, STONE_GRAY, false)
	_add_box(Vector3(x, y + 0.12, z), Vector3(1.1, 0.15, 0.15), Color(0.2, 0.12, 0.08, 1), false)
	_add_box(Vector3(x, y + 0.12, z), Vector3(0.15, 0.15, 1.1), Color(0.2, 0.12, 0.08, 1), false)
	_add_cylinder(Vector3(x, y + 0.5, z), 0.03, 0.38, 0.85, Color(1, 0.55, 0.15, 1), false, true)
	var light := OmniLight3D.new()
	light.position = Vector3(x, y + 1.3, z)
	light.light_color = TORCH_COLOR
	light.light_energy = 1.8
	light.omni_range = 11.0
	add_child(light)


# --- NW: farm --------------------------------------------------------------------

func _build_farm() -> void:
	# Fence rectangle with a gap in the south side (x -24..-18) facing the town.
	var fh := 1.1
	_add_box(Vector3(-35, fh * 0.5, 55), Vector3(40, fh, 0.2), FENCE_WOOD)      # north
	_add_box(Vector3(-55, fh * 0.5, 35), Vector3(0.2, fh, 40), FENCE_WOOD)      # west
	_add_box(Vector3(-15, fh * 0.5, 35), Vector3(0.2, fh, 40), FENCE_WOOD)      # east
	_add_box(Vector3(-39.5, fh * 0.5, 15), Vector3(31, fh, 0.2), FENCE_WOOD)    # south, west of gap
	_add_box(Vector3(-16.5, fh * 0.5, 15), Vector3(3, fh, 0.2), FENCE_WOOD)     # south, east of gap

	# Barn with a roof, and a silo beside it.
	_add_box(Vector3(-45, 2.5, 45), Vector3(8, 5, 10), BARN_RED)
	_add_box(Vector3(-45, 5.9, 45), Vector3(8.6, 1.8, 10.6), BARN_ROOF)
	_add_cylinder(Vector3(-37, 3, 48), 1.5, 1.5, 6.0, Color(0.8, 0.8, 0.75))
	_add_cylinder(Vector3(-37, 7, 48), 0.0, 1.5, 2.0, BARN_RED, false)

	# Crop rows (visual only, no collision, so nobody gets stuck on the lettuce).
	for i in range(8):
		_add_box(Vector3(-38, 0.08, 20 + i * 3), Vector3(26, 0.15, 1.0), Color(0.55, 0.42, 0.18), false)

	# Scarecrow.
	_add_box(Vector3(-21, 1.2, 30), Vector3(0.15, 2.4, 0.15), FENCE_WOOD)
	_add_box(Vector3(-21, 1.9, 30), Vector3(1.4, 0.15, 0.15), FENCE_WOOD)
	_add_sphere(Vector3(-21, 2.5, 30), 0.3, Color(0.9, 0.8, 0.5), false)

	# Hay bales by the east fence, south end (the pond took their old spot).
	_add_cylinder(Vector3(-18, 0.7, 21.5), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))
	_add_cylinder(Vector3(-19.5, 0.7, 24), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))
	_add_cylinder(Vector3(-17.8, 0.7, 26.5), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))

	_build_pond()


## The duck pond. The bowl is four full-width shore ramps (one per side)
## plus a flat mud floor: where two perpendicular ramps overlap in a corner,
## whichever surface is higher wins for walking, which miters the corner for
## free. The water is a thin translucent slab rendered single-sided, so a
## camera dunked below the surface sees clear air instead of a blue screen
## (same lesson as the shaft tubes). Wading ripples and the wading-slowdown
## zone live on a PondRipples node; ducks included, as the name demands.
func _build_pond() -> void:
	var cx := POND_CENTER.x
	var cz := POND_CENTER.y
	var rim := POND_HALF + 0.1  # tuck the shore lip a hair over the grass seam
	var w := POND_HALF * 2.0 + 0.2
	_add_box(Vector3(cx, -POND_DEPTH - 0.15, cz), Vector3(POND_FLOOR_HALF * 2.0 + 0.4, 0.3, POND_FLOOR_HALF * 2.0 + 0.4), POND_MUD)
	_add_ramp(Vector3(cx, 0.02, cz - rim), Vector3(cx, -POND_DEPTH, cz - POND_FLOOR_HALF), w, POND_MUD)
	_add_ramp(Vector3(cx, 0.02, cz + rim), Vector3(cx, -POND_DEPTH, cz + POND_FLOOR_HALF), w, POND_MUD)
	_add_ramp(Vector3(cx - rim, 0.02, cz), Vector3(cx - POND_FLOOR_HALF, -POND_DEPTH, cz), w, POND_MUD)
	_add_ramp(Vector3(cx + rim, 0.02, cz), Vector3(cx + POND_FLOOR_HALF, -POND_DEPTH, cz), w, POND_MUD)

	var water := MeshInstance3D.new()
	water.position = Vector3(cx, POND_WATER_Y - 0.01, cz)
	var slab := BoxMesh.new()
	slab.size = Vector3(POND_HALF * 2.0 - 0.4, 0.02, POND_HALF * 2.0 - 0.4)
	water.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = WATER_COLOR
	mat.roughness = 0.15
	mat.metallic = 0.2
	water.material_override = mat
	add_child(water)

	var ripples: Node3D = POND_RIPPLES.new()
	ripples.position = Vector3(cx, POND_WATER_Y, cz)
	ripples.half = POND_HALF
	add_child(ripples)

	_add_duck(Vector3(cx - 1.5, POND_WATER_Y, cz - 1.0), 0.7)
	_add_duck(Vector3(cx + 1.8, POND_WATER_Y, cz + 1.6), -1.8)
	_add_sign(Vector3(cx - POND_HALF - 1.5, 0, cz - POND_HALF - 1.2), "DUCK POND")


## A duck: white sphere body, sphere head, orange cone beak. Floats where you
## put it and contemplates nothing. Faces -z at yaw 0. No collision.
func _add_duck(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var white := _make_material(Color(0.95, 0.94, 0.9, 1))
	var body := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.28
	bs.height = 0.46
	body.mesh = bs
	body.position = Vector3(0, 0.1, 0)
	body.material_override = white
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.26
	head.mesh = hs
	head.position = Vector3(0, 0.35, -0.22)
	head.material_override = white
	root.add_child(head)
	var beak := MeshInstance3D.new()
	var bk := CylinderMesh.new()
	bk.top_radius = 0.0
	bk.bottom_radius = 0.05
	bk.height = 0.16
	beak.mesh = bk
	beak.position = Vector3(0, 0.33, -0.38)
	beak.rotation.x = -PI * 0.5
	beak.material_override = _make_material(Color(0.95, 0.6, 0.15, 1))
	root.add_child(beak)


# --- SE: canyon maze --------------------------------------------------------------

func _build_canyon_maze() -> void:
	# Solid rock blocks straight from the MAZE_ROWS drawing above.
	for r in range(MAZE_ROWS.size()):
		var row := MAZE_ROWS[r]
		for c in range(row.length()):
			if row[c] != "#":
				continue
			var x := MAZE_ORIGIN_X + (c + 0.5) * MAZE_CELL
			var z := MAZE_ORIGIN_Z - (r + 0.5) * MAZE_CELL
			_add_box(Vector3(x, MAZE_WALL_HEIGHT * 0.5, z), Vector3(MAZE_CELL, MAZE_WALL_HEIGHT, MAZE_CELL), CANYON_ROCK)

	# A coat rack with a cowboy hat, in the deep pocket next to Dave and the
	# prize (cell col 7, row 7) -- grants the revolver power (see coat_rack.gd).
	# Nobody knows who left it here. Dave denies everything.
	var rack := COAT_RACK_SCENE.instantiate()
	rack.position = Vector3(49.5, 0, -51)
	add_child(rack)


# --- SW: snowy hills ---------------------------------------------------------------

func _build_snowy_hills() -> void:
	# Rounded mounds sunk partway into the ground so they read as hills you can
	# actually walk up and over.
	var mounds := [
		[-20, -20, 4.0], [-32, -18, 5.0], [-46, -22, 6.0], [-54, -34, 5.0],
		[-44, -40, 4.5], [-30, -36, 5.5], [-18, -44, 4.0], [-38, -52, 6.0],
		[-52, -52, 4.5], [-24, -54, 5.0],
	]
	for m in mounds:
		_add_mound(m[0], m[1], m[2])

	var pines := [
		[-16, -30], [-26, -26], [-40, -28], [-50, -18], [-55, -44],
		[-46, -32], [-34, -46], [-22, -38], [-16, -52], [-42, -16],
	]
	for p in pines:
		_add_pine(p[0], p[1])

	_add_rock(-28, -48, 0.8)
	_add_rock(-48, -46, 0.6)
	_add_rock(-36, -22, 0.7)
	_add_rock(-20, -32, 0.5)

	# The mandatory snowman -- also grants the snowball-throwing power (see snowman.gd).
	var snowman := SNOWMAN_SCENE.instantiate()
	snowman.position = Vector3(-30, 0, -33)
	add_child(snowman)


# --- underground: surface ground collision (with 4 entrance-sized holes) ------

func _build_ground_collision() -> void:
	var half := MAP_HALF
	var whole: Array = [Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0))]
	var holes: Array = ENTRANCE_SHAFTS.values()
	var rects := _rects_minus_holes(whole, holes, SHAFT_RADIUS + 0.15)
	# The duck pond's basin needs its own hole (its shores and floor supply
	# the collision inside it).
	rects = _rects_minus_holes(rects, [POND_CENTER], POND_HALF)
	for r in rects:
		var rect: Rect2 = r
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		_add_collision_box(Vector3(cx, -0.5, cz), Vector3(rect.size.x, 1.0, rect.size.y))


# --- underground: tunnel network -----------------------------------------------

func _build_tunnels() -> void:
	# Level A's floor gets holes where the connector shafts drop to Level B;
	# Level B is the bottom, so its floor stays solid throughout. Level A is
	# warm brown rock lit by torches; Level B is darker, grayer, and studded
	# with glowing gems -- the deeper you go, the stranger it gets.
	_build_tunnel_level(LEVEL_A_ROWS, LEVEL_A_ORIGIN, LEVEL_A_Y, CONNECTOR_SHAFTS,
		TUNNEL_ROCK, TUNNEL_FLOOR_COLOR, TUNNEL_CEILING_COLOR, false, [TOWER_GATE_CELL])
	_build_tunnel_level(LEVEL_B_ROWS, LEVEL_B_ORIGIN, LEVEL_B_Y, [],
		DEEP_ROCK, DEEP_FLOOR_COLOR, DEEP_CEILING_COLOR, true)

	for biome in ENTRANCE_SHAFTS:
		_build_entrance_shaft(ENTRANCE_SHAFTS[biome], biome)
	for pos in CONNECTOR_SHAFTS:
		_build_connector_shaft(pos)


func _build_tunnel_level(rows: Array[String], origin: Vector2, y: float, floor_holes: Array,
		rock: Color, floor_color: Color, ceiling_color: Color, gems: bool, skip_cells: Array = []) -> void:
	var cols := rows[0].length()
	var grid_rows := rows.size()
	var width := cols * TUNNEL_CELL
	var depth := grid_rows * TUNNEL_CELL

	# Gem placement uses a FIXED-seed sequence: the layout is byte-identical
	# on every run and every peer (same rule as the rest of the map -- this is
	# authored variety, not runtime randomness; the seed is just a compact way
	# of writing several hundred hand-ish-placed crystals).
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC4E5

	var floor_rects: Array = [Rect2(origin, Vector2(width, depth))]
	for r in _rects_minus_holes(floor_rects, floor_holes, SHAFT_RADIUS + 0.15):
		var rect: Rect2 = r
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		_add_box(Vector3(cx, y - 0.15, cz), Vector3(rect.size.x, 0.3, rect.size.y), floor_color)

	# Ceiling is purely atmospheric: nobody can jump anywhere near 4m, so it
	# never needs collision or holes, just something other than open sky
	# overhead when you look up.
	_add_visual_slab(Vector3(origin.x + width * 0.5, y + TUNNEL_WALL_HEIGHT, origin.y + depth * 0.5), Vector3(width, 0.3, depth), ceiling_color)

	for gy in range(grid_rows):
		var row: String = rows[gy]
		for gx in range(cols):
			var x := origin.x + gx * TUNNEL_CELL + TUNNEL_CELL * 0.5
			var z := origin.y + gy * TUNNEL_CELL + TUNNEL_CELL * 0.5
			if row[gx] == "#":
				if Vector2i(gx, gy) in skip_cells:
					continue # someone else fills this cell (see _build_tower)
				_add_box(Vector3(x, y + TUNNEL_WALL_HEIGHT * 0.5, z), Vector3(TUNNEL_CELL, TUNNEL_WALL_HEIGHT, TUNNEL_CELL), rock)
				if gems:
					# Stud every wall face that borders open corridor with a
					# handful of glowing crystals, poking out at odd angles.
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx := gx + d.x
						var ny := gy + d.y
						if nx < 0 or nx >= cols or ny < 0 or ny >= grid_rows:
							continue
						if rows[ny][nx] == "#":
							continue
						var out := Vector3(d.x, 0, d.y)
						var lateral := Vector3(out.z, 0, -out.x)
						var face := Vector3(x, y + TUNNEL_WALL_HEIGHT * 0.5, z) + out * (TUNNEL_CELL * 0.5)
						for k in range(2 + rng.randi_range(0, 2)):
							var p := face + lateral * rng.randf_range(-2.0, 2.0) + Vector3.UP * rng.randf_range(-1.5, 1.5)
							var tilt := (out + lateral * rng.randf_range(-0.5, 0.5) + Vector3.UP * rng.randf_range(-0.3, 0.6)).normalized()
							_add_gem(p, tilt, rng.randf_range(0.25, 0.7), GEM_COLORS[rng.randi_range(0, GEM_COLORS.size() - 1)], rng.randi_range(0, 2), rng.randf() < 0.2)
			elif gx % 2 == 1 and gy % 2 == 1:
				# A "room" cell (not a narrow connector passage). Light every
				# other one in a checkerboard so it's never dark without a
				# light in literally every room: torches up on Level A, glowing
				# floor crystal clusters down in the gem caverns, plus a couple
				# of crystals hanging from each room's ceiling.
				var c := (gx - 1) / 2
				var r := (gy - 1) / 2
				if gems:
					for k in range(2):
						var hp := Vector3(x + rng.randf_range(-1.8, 1.8), y + TUNNEL_WALL_HEIGHT - 0.1, z + rng.randf_range(-1.8, 1.8))
						var hang := (Vector3.DOWN + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized()
						_add_gem(hp, hang, rng.randf_range(0.3, 0.6), GEM_COLORS[rng.randi_range(0, GEM_COLORS.size() - 1)], 0, false)
					if (c + r) % 2 == 0:
						_add_gem_cluster(Vector3(x, y, z), GEM_COLORS[(c * 3 + r) % GEM_COLORS.size()], rng)
				elif (c + r) % 2 == 0:
					_add_torch(Vector3(x, y + 2.2, z))


## A single glowing crystal embedded in rock: `out_dir` is the direction it
## pokes out along (its base sits at `pos`, sunk slightly in). Shapes: 0 = a
## six-sided spike, 1 = a squared shard, 2 = a rounded nodule. All of them
## glow via emissive material; `bright` ones glow harder. Purely decorative.
func _add_gem(pos: Vector3, out_dir: Vector3, size: float, color: Color, shape: int, bright: bool) -> void:
	var mesh := MeshInstance3D.new()
	var y_axis := out_dir.normalized()
	var helper := Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis)
	mesh.transform = Transform3D(Basis(x_axis, y_axis, z_axis), pos + y_axis * (size * 0.3))
	match shape:
		0:
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = size * 0.3
			spike.height = size
			spike.radial_segments = 6
			mesh.mesh = spike
		1:
			var shard := BoxMesh.new()
			shard.size = Vector3(size * 0.35, size, size * 0.22)
			mesh.mesh = shard
		_:
			var orb := SphereMesh.new()
			orb.radius = size * 0.35
			orb.height = size * 0.7
			mesh.mesh = orb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.4)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5 if bright else 1.2
	mesh.material_override = mat
	mesh.add_to_group("gems")
	add_child(mesh)


## A floor-standing clump of crystals that actually CASTS light -- Level B's
## answer to the torch. One hue per cluster so each room has its own glow.
func _add_gem_cluster(floor_pos: Vector3, color: Color, rng: RandomNumberGenerator) -> void:
	for k in range(5):
		var a := TAU * float(k) / 5.0 + rng.randf_range(-0.3, 0.3)
		var p := floor_pos + Vector3(cos(a) * rng.randf_range(0.3, 0.8), 0, sin(a) * rng.randf_range(0.3, 0.8))
		var tilt := (Vector3.UP + Vector3(cos(a) * 0.35, 0, sin(a) * 0.35)).normalized()
		_add_gem(p, tilt, rng.randf_range(0.5, 1.1), color, 0 if k % 3 != 2 else 1, k == 0)
	_add_gem(floor_pos, Vector3.UP, 0.5, color, 2, false)
	var light := OmniLight3D.new()
	light.position = floor_pos + Vector3(0, 1.2, 0)
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = 8.0
	add_child(light)


func _build_entrance_shaft(pos: Vector2, biome: String) -> void:
	_build_switchback_ramp(pos, LEVEL_A_Y, 0.0)
	var biome_color: Color = {
		"forest": FOREST_CANOPY, "farm": BARN_RED, "canyon": CANYON_ROCK, "snow": Color(0.5, 0.72, 0.85, 1),
	}[biome]
	# The hole itself: an open-ended tube reaching all the way down to Level A's
	# floor, so looking in actually shows depth (and the ramps inside)
	# instead of a flat dark decal sitting on the grass. Plus a short
	# biome-tinted collar standing proud of the surface for a bit of rim detail.
	var shaft_top := 0.15
	var shaft_height := shaft_top - LEVEL_A_Y
	# Shaft wall: viewed only from inside the shaft (dropping in / climbing out),
	# so render the inner face only -- a camera clipping out through it sees nothing.
	_add_ring(Vector3(pos.x, shaft_top - shaft_height * 0.5, pos.y), SHAFT_RADIUS, shaft_height, TUNNEL_ROCK, BaseMaterial3D.CULL_FRONT)
	# Collar: a rim ring viewed from outside on the surface, so outer face only.
	_add_ring(Vector3(pos.x, 0.3, pos.y), SHAFT_RADIUS + 0.25, 0.6, biome_color, BaseMaterial3D.CULL_BACK)
	_add_sign(Vector3(pos.x + SHAFT_RADIUS + 1.5, 0, pos.y), "MIND THE GAP")


func _build_connector_shaft(pos: Vector2) -> void:
	_build_switchback_ramp(pos, LEVEL_B_Y, LEVEL_A_Y)
	var shaft_height := LEVEL_A_Y - LEVEL_B_Y
	_add_ring(Vector3(pos.x, LEVEL_A_Y - shaft_height * 0.5, pos.y), SHAFT_RADIUS, shaft_height, TUNNEL_ROCK, BaseMaterial3D.CULL_FRONT)
	_add_torch(Vector3(pos.x + 1.2, LEVEL_A_Y - 2.0, pos.y))
	_add_torch(Vector3(pos.x - 1.2, LEVEL_B_Y + 2.5, pos.y))


## Straight switchback ramps up the inside of a vertical shaft: alternating
## slopes with a flat landing at each turn, like a fire escape. The top
## landing deliberately stops TOP_LANDING_DROP short of y_top (the level
## you're climbing out onto), which is within normal jump height -- so "jump
## out of" the hole is literally one jump from the last landing, and hopping
## in lands you gently on that same landing. Everything below still works by
## just falling.
const RAMP_RUN := 2.2          # horizontal length of one slope (fits the shaft)
const RAMP_WIDTH := 1.2
# Lane separation matters more than lane width: consecutive slopes CONVERGE in
# height toward the landing they share, so a slope is always passing directly
# overhead of the previous one at less than head height near that end. The
# lanes therefore need a gap wider than the player capsule (0.8) between their
# edges, or climbers bonk into the underside of the next slope up.
const RAMP_LANE_OFFSET := 1.1  # lane edges: 0.5..1.7 either side -> 1.0 gap
const LANDING_LEN := 1.1
const TOP_LANDING_DROP := 0.9  # rim height above the top landing; jump apex is ~1.17
const MAX_SEGMENT_RISE := 1.6  # keeps every slope comfortably under 45 degrees

func _build_switchback_ramp(center: Vector2, y_bottom: float, y_top: float) -> void:
	var total_rise := (y_top - TOP_LANDING_DROP) - y_bottom
	var segments := int(ceilf(total_rise / MAX_SEGMENT_RISE))
	var rise := total_rise / segments
	var end_x := RAMP_RUN * 0.5 + LANDING_LEN * 0.5
	for i in range(segments):
		var y0 := y_bottom + i * rise
		# Even segments climb toward +x in the -z lane, odd ones back toward -x
		# in the +z lane, so consecutive slopes sit side by side instead of
		# stacked (headroom between same-lane slopes is two full rises).
		var dir := 1.0 if i % 2 == 0 else -1.0
		var lane_z := center.y + (-RAMP_LANE_OFFSET if i % 2 == 0 else RAMP_LANE_OFFSET)
		_add_ramp(
			Vector3(center.x - dir * RAMP_RUN * 0.5, y0, lane_z),
			Vector3(center.x + dir * RAMP_RUN * 0.5, y0 + rise, lane_z),
			RAMP_WIDTH, STONE_GRAY)
		# Landing at this slope's top end, spanning both lanes so turning
		# around is just walking across it.
		_add_box(Vector3(center.x + dir * end_x, y0 + rise - 0.125, center.y), Vector3(LANDING_LEN, 0.25, (RAMP_LANE_OFFSET + RAMP_WIDTH * 0.5) * 2.0), STONE_GRAY)


## Open-ended tube. `cull` picks which single side renders (CylinderMesh
## normals point outward): CULL_BACK shows only the OUTER face, CULL_FRONT
## only the INNER face, CULL_DISABLED both. Single-siding matters here because
## these are thin and a third-person camera clips through them -- rendering
## only the side you actually view from means a clipped camera sees the culled
## (invisible) far side instead of a wall of color blinding it.
func _add_ring(pos: Vector3, radius: float, height: float, color: Color, cull: int = BaseMaterial3D.CULL_DISABLED) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = pos
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	mesh.mesh = cyl
	var mat := _make_material(color)
	mat.cull_mode = cull
	mesh.material_override = mat
	add_child(mesh)
