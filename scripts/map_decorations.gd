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
## levels, and everywhere climbable via a spiral ramp -- no ladders, no dead
## ends. Layout below was generated offline with a recursive-backtracker +
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
const SHAFT_RADIUS := 2.2
const TORCH_COLOR := Color(1.0, 0.65, 0.3, 1)

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
	_build_farm()
	_build_canyon_maze()
	_build_snowy_hills()
	_build_ground_collision()
	_build_tunnels()


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


## Visual-only slab (no collision) -- used for tunnel ceilings, rendered from
## both sides since the player is always underneath looking up at it.
func _add_visual_slab(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = pos
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := _make_material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)


## A box rotated around Y -- used for spiral-ramp treads, which need to sit
## tangent to the shaft they wind around.
func _add_rotated_box(pos: Vector3, size: Vector3, yaw: float, color: Color) -> void:
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
	_add_box(Vector3(0, 2, h), Vector3(h * 2.0, 4, 1), BOUNDARY_GRAY)
	_add_box(Vector3(0, 2, -h), Vector3(h * 2.0, 4, 1), BOUNDARY_GRAY)
	_add_box(Vector3(h, 2, 0), Vector3(1, 4, h * 2.0), BOUNDARY_GRAY)
	_add_box(Vector3(-h, 2, 0), Vector3(1, 4, h * 2.0), BOUNDARY_GRAY)


func _build_quadrant_ground() -> void:
	# Flat color washes so each quadrant reads at a glance; lifted slightly
	# above the base ground plane to avoid z-fighting.
	_add_ground_patch(Vector3(35, 0.01, 35), Vector2(46, 46), FOREST_FLOOR)
	_add_ground_patch(Vector3(-35, 0.01, 35), Vector2(46, 46), FARM_FIELD)
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
	var trees := [
		[16, 18, 2.4, 1.3], [21, 15, 2.8, 1.5], [27, 19, 2.2, 1.2], [33, 15, 3.0, 1.6],
		[40, 17, 2.5, 1.3], [47, 14, 2.7, 1.4], [53, 18, 2.3, 1.2],
		[15, 27, 2.9, 1.5], [22, 24, 2.4, 1.2], [29, 26, 2.6, 1.4], [36, 23, 2.2, 1.1],
		[44, 26, 3.1, 1.6], [51, 24, 2.5, 1.3],
		[18, 35, 2.3, 1.3], [26, 33, 2.8, 1.5], [34, 36, 2.4, 1.2], [42, 33, 2.6, 1.4],
		[50, 35, 2.9, 1.5], [56, 30, 2.2, 1.2],
		[15, 44, 2.7, 1.4], [23, 42, 2.3, 1.2], [31, 45, 3.0, 1.6], [39, 43, 2.5, 1.3],
		[47, 45, 2.4, 1.3], [54, 42, 2.8, 1.5],
		[19, 52, 2.5, 1.3], [28, 54, 2.2, 1.2], [37, 51, 2.7, 1.4], [45, 53, 2.4, 1.3],
		[53, 55, 2.6, 1.4],
	]
	for t in trees:
		_add_tree(t[0], t[1], t[2], t[3])
	_add_rock(25, 29, 0.7)
	_add_rock(43, 38, 0.9)
	_add_rock(52, 48, 0.6)
	# A stump in a small clearing, for sitting on and contemplating life.
	_add_cylinder(Vector3(33, 0.3, 30), 0.5, 0.55, 0.6, TRUNK_BROWN)


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

	# Hay bales by the east fence.
	_add_cylinder(Vector3(-20, 0.7, 48), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))
	_add_cylinder(Vector3(-23, 0.7, 50), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))
	_add_cylinder(Vector3(-20.5, 0.7, 52), 1.0, 1.0, 1.4, Color(0.85, 0.75, 0.4))


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
		_add_sphere(Vector3(m[0], -m[2] * 0.55, m[1]), m[2], SNOW_WHITE)

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
	for r in _rects_minus_holes(whole, holes, SHAFT_RADIUS + 0.15):
		var rect: Rect2 = r
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		_add_collision_box(Vector3(cx, -0.5, cz), Vector3(rect.size.x, 1.0, rect.size.y))


# --- underground: tunnel network -----------------------------------------------

func _build_tunnels() -> void:
	# Level A's floor gets holes where the connector shafts drop to Level B;
	# Level B is the bottom, so its floor stays solid throughout.
	_build_tunnel_level(LEVEL_A_ROWS, LEVEL_A_ORIGIN, LEVEL_A_Y, CONNECTOR_SHAFTS)
	_build_tunnel_level(LEVEL_B_ROWS, LEVEL_B_ORIGIN, LEVEL_B_Y, [])

	for biome in ENTRANCE_SHAFTS:
		_build_entrance_shaft(ENTRANCE_SHAFTS[biome], biome)
	for pos in CONNECTOR_SHAFTS:
		_build_connector_shaft(pos)


func _build_tunnel_level(rows: Array[String], origin: Vector2, y: float, floor_holes: Array) -> void:
	var cols := rows[0].length()
	var grid_rows := rows.size()
	var width := cols * TUNNEL_CELL
	var depth := grid_rows * TUNNEL_CELL

	var floor_rects: Array = [Rect2(origin, Vector2(width, depth))]
	for r in _rects_minus_holes(floor_rects, floor_holes, SHAFT_RADIUS + 0.15):
		var rect: Rect2 = r
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		_add_box(Vector3(cx, y - 0.15, cz), Vector3(rect.size.x, 0.3, rect.size.y), TUNNEL_FLOOR_COLOR)

	# Ceiling is purely atmospheric: nobody can jump anywhere near 4m, so it
	# never needs collision or holes, just something other than open sky
	# overhead when you look up.
	_add_visual_slab(Vector3(origin.x + width * 0.5, y + TUNNEL_WALL_HEIGHT, origin.y + depth * 0.5), Vector3(width, 0.3, depth), TUNNEL_CEILING_COLOR)

	for gy in range(grid_rows):
		var row: String = rows[gy]
		for gx in range(cols):
			var x := origin.x + gx * TUNNEL_CELL + TUNNEL_CELL * 0.5
			var z := origin.y + gy * TUNNEL_CELL + TUNNEL_CELL * 0.5
			if row[gx] == "#":
				_add_box(Vector3(x, y + TUNNEL_WALL_HEIGHT * 0.5, z), Vector3(TUNNEL_CELL, TUNNEL_WALL_HEIGHT, TUNNEL_CELL), TUNNEL_ROCK)
			elif gx % 2 == 1 and gy % 2 == 1:
				# A "room" cell (not a narrow connector passage) -- light
				# every other one in a checkerboard so it's never dark
				# without needing a torch in literally every room.
				var c := (gx - 1) / 2
				var r := (gy - 1) / 2
				if (c + r) % 2 == 0:
					_add_torch(Vector3(x, y + 2.2, z))


func _build_entrance_shaft(pos: Vector2, biome: String) -> void:
	_build_spiral_ramp(pos, LEVEL_A_Y, -0.15, SHAFT_RADIUS - 0.5)
	var biome_color: Color = {
		"forest": FOREST_CANOPY, "farm": BARN_RED, "canyon": CANYON_ROCK, "snow": Color(0.5, 0.72, 0.85, 1),
	}[biome]
	# The hole itself: an open-ended tube reaching all the way down to Level A's
	# floor, so looking in actually shows depth (and the spiral ramp inside)
	# instead of a flat dark decal sitting on the grass. Plus a short
	# biome-tinted collar standing proud of the surface for a bit of rim detail.
	var shaft_top := 0.15
	var shaft_height := shaft_top - LEVEL_A_Y
	_add_ring(Vector3(pos.x, shaft_top - shaft_height * 0.5, pos.y), SHAFT_RADIUS, shaft_height, TUNNEL_ROCK)
	_add_ring(Vector3(pos.x, 0.3, pos.y), SHAFT_RADIUS + 0.25, 0.6, biome_color)
	_add_sign(Vector3(pos.x + SHAFT_RADIUS + 1.5, 0, pos.y), "MIND THE GAP")


func _build_connector_shaft(pos: Vector2) -> void:
	_build_spiral_ramp(pos, LEVEL_B_Y, LEVEL_A_Y, SHAFT_RADIUS - 0.5)
	var shaft_height := LEVEL_A_Y - LEVEL_B_Y
	_add_ring(Vector3(pos.x, LEVEL_A_Y - shaft_height * 0.5, pos.y), SHAFT_RADIUS, shaft_height, TUNNEL_ROCK)
	_add_torch(Vector3(pos.x + 1.2, LEVEL_A_Y - 2.0, pos.y))
	_add_torch(Vector3(pos.x - 1.2, LEVEL_B_Y + 2.5, pos.y))


## Winds a walkable staircase of overlapping treads around the inside wall of
## a vertical shaft from y_bottom to y_top, so "drop down into" (just fall)
## and "jump out of" (walk the ramp up, hop the last bit) both work with
## nothing but ordinary gravity and jump height -- no ladders, no teleports.
func _build_spiral_ramp(center: Vector2, y_bottom: float, y_top: float, radius: float) -> void:
	var rise := y_top - y_bottom
	var turns := maxf(1.0, rise / 4.0)
	var steps_per_turn := 14
	var steps := int(turns * steps_per_turn)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := t * turns * TAU
		var y := y_bottom + t * rise
		var tread_pos := Vector3(center.x + cos(angle) * radius, y, center.y + sin(angle) * radius)
		_add_rotated_box(tread_pos, Vector3(1.8, 0.25, 1.0), angle + PI * 0.5, STONE_GRAY)


func _add_ring(pos: Vector3, radius: float, height: float, color: Color) -> void:
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)
