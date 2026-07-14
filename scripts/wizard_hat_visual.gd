extends RefCounted
## Builds the blue-cone-with-white-stars wizard hat out of primitives, so the
## Referenced via preload const (WIZARD_HAT_VISUAL) rather than class_name, so a
## headless run needs no editor import scan -- same as the rest of the project.
## exact same look is used both worn on a player's head (see player.gd) and as
## the pickup sitting in the woods (see wizard_hat_pickup.gd). Everything is
## added as children of `parent`; the hat's brim sits on `parent`'s local origin
## and the cone rises in +Y.

const HAT_BLUE := Color(0.24, 0.32, 0.72, 1)
const STAR_WHITE := Color(0.97, 0.97, 1.0, 1)
const CONE_H := 0.75
const CONE_R := 0.26
const CONE_BASE_Y := 0.03


static func build(parent: Node3D) -> void:
	var brim := MeshInstance3D.new()
	var bd := CylinderMesh.new()
	bd.top_radius = 0.36
	bd.bottom_radius = 0.36
	bd.height = 0.05
	brim.mesh = bd
	brim.material_override = _mat(HAT_BLUE, false)
	parent.add_child(brim)

	var cone := MeshInstance3D.new()
	var cd := CylinderMesh.new()
	cd.top_radius = 0.0
	cd.bottom_radius = CONE_R
	cd.height = CONE_H
	cd.radial_segments = 20
	cone.mesh = cd
	cone.position = Vector3(0, CONE_BASE_Y + CONE_H * 0.5, 0)
	cone.material_override = _mat(HAT_BLUE, false)
	parent.add_child(cone)

	# Stars scattered over the cone, each flat against the surface facing out.
	var star_mesh := _star_mesh()
	var star_mat := _mat(STAR_WHITE, true)
	# [angle degrees, height fraction up the cone 0..1]
	var spots := [[20, 0.62], [140, 0.5], [255, 0.55], [80, 0.32], [200, 0.28], [320, 0.22]]
	for s in spots:
		var ang := deg_to_rad(float(s[0]))
		var hf := float(s[1])
		var r := CONE_R * (1.0 - hf) + 0.015
		var y := CONE_BASE_Y + hf * CONE_H
		var radial := Vector3(cos(ang), 0, sin(ang))
		var x_axis := Vector3.UP.cross(radial).normalized()
		var y_axis := radial.cross(x_axis)
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		star.material_override = star_mat
		star.transform = Transform3D(Basis(x_axis, y_axis, radial), radial * r + Vector3(0, y, 0))
		parent.add_child(star)


## A flat five-pointed star lying in local XY (normal +Z), tip pointing +Y.
static func _star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := 0.09
	var inner := 0.036
	var pts: Array[Vector2] = []
	for i in range(10):
		var rad := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + float(i) * PI / 5.0
		pts.append(Vector2(cos(a) * rad, sin(a) * rad))
	for i in range(10):
		var p0 := pts[i]
		var p1 := pts[(i + 1) % 10]
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(p0.x, p0.y, 0))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(p1.x, p1.y, 0))
	return st.commit()


static func _mat(color: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.5
	return m
