"""
lever_box.py — Stylized industrial lever asset for Roblox.

Hierarchy
---------
  Lever_Base    (static geometry, origin at world 0, 0, 0)
    Lever_Handle  (animatable, pivot at 0, 0, PIVOT_Z = 0.04)

Lever_Base  — one joined mesh containing:
    • Flat rectangular base plate
    • 4 small hexagonal corner bolts
    • Solid semi-cylindrical housing guard

Lever_Handle  — one joined mesh containing:
    • Lever shaft  (cylinder)
    • Spherical knob (UV sphere)

Pivot placement
---------------
  PIVOT_Z = PLATE_H = 0.04 m.
  This is the centre of the housing arc and the physical hinge of the lever.
  Setting Lever_Handle's origin here means that rotating it around its
  LOCAL X axis in Roblox produces correct hinge-point animation with no
  additional scripting offsets required.

Roblox Studio usage
-------------------
  Import lever_box.fbx → Model with two parts.
  Animate the lever:
    local handle = model:FindFirstChild("Lever_Handle")
    handle.CFrame = handle.CFrame
                  * CFrame.fromAxisAngle(Vector3.xAxis, math.rad(angle))

Coordinate mapping (axis_forward="-Z", axis_up="Y")
    Blender X  →  Roblox X   (rotation axis, unchanged)
    Blender Y  →  Roblox -Z
    Blender Z  →  Roblox Y   (shaft extends upward in Roblox Y)

Output
------
  <cwd>/assets/models/lever_box.fbx
  <cwd>/assets/models/lever_box.blend

No materials, lights, or textures are assigned.
"""

import math
import os

import bmesh
import bpy

# ─── DIMENSIONS ──────────────────────────────────────────────────────────────

PLATE_W = 0.40  # base plate total width  (X)
PLATE_D = 0.28  # base plate total depth  (Y)
PLATE_H = 0.04  # base plate height       (Z) — also PIVOT_Z

BOLT_RADIUS = 0.022  # hex bolt circumradius
BOLT_HEIGHT = 0.018  # hex bolt height
BOLT_INSET_X = 0.030  # inset from plate long edge  (X)
BOLT_INSET_Y = 0.030  # inset from plate short edge (Y)

HOUSING_RADIUS = 0.080  # semi-cylinder arch outer radius
HOUSING_SEGS = 8  # arc segments → N+1 = 9 profile vertices
HOUSING_LEN = 0.20  # arch extrusion length along X

# The rotation axis sits at the centre of the housing arc,
# level with the top of the base plate.
PIVOT_Z = PLATE_H  # 0.040 m

SHAFT_RADIUS = 0.018  # lever shaft radius
SHAFT_LEN = 0.52  # shaft length, measured from pivot upward

KNOB_RADIUS = 0.042  # spherical knob radius
KNOB_Z = PIVOT_Z + SHAFT_LEN  # 0.560 m

EXPORT_DIR = os.path.join(os.getcwd(), "..", "models")

# ─────────────────────────────────────────────────────────────────────────────


# ─── SCENE UTILITIES ─────────────────────────────────────────────────────────


def clear_scene():
    """Delete all objects and purge orphaned mesh data-blocks."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def make_active(obj):
    """Set obj as the active object in the view layer."""
    bpy.context.view_layer.objects.active = obj


def link_obj(obj):
    """Link obj into the active scene collection and return it."""
    bpy.context.collection.objects.link(obj)
    return obj


def set_origin_to_world(obj, x, y, z):
    """
    Reposition obj's origin (pivot point) to the world coordinate (x, y, z).

    The mesh vertices are recalculated in local space to maintain their
    world positions — only the origin moves.  This is the operation that
    places the Lever_Handle pivot exactly at the housing hinge centre.
    """
    bpy.context.scene.cursor.location = (float(x), float(y), float(z))
    make_active(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


def join_into(components, active_component, final_name):
    """
    Join all objects in *components* into *active_component*.
    The surviving object is renamed to *final_name* and returned.
    The active component's transform is preserved as the joined object's
    transform; all other meshes are transformed into that local space.
    """
    bpy.ops.object.select_all(action="DESELECT")
    for obj in components:
        obj.select_set(True)
    make_active(active_component)
    bpy.ops.object.join()
    result = bpy.context.active_object
    result.name = final_name
    return result


# ─── LEVER_BASE COMPONENTS ───────────────────────────────────────────────────


def build_base_plate():
    """
    Flat rectangular box forming the mounting plate.

    World extents after transform_apply:
      X ∈ [−PLATE_W/2, +PLATE_W/2]   = [−0.20, +0.20]
      Y ∈ [−PLATE_D/2, +PLATE_D/2]   = [−0.14, +0.14]
      Z ∈ [0,          PLATE_H    ]   = [0.000, 0.040]

    primitive_cube_add produces a ±1 cube.  Scaling by (PLATE_W/2, PLATE_D/2,
    PLATE_H/2) gives the correct half-extents, then transform_apply bakes the
    scale into the mesh data so joining later is clean.
    """
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, PLATE_H / 2))
    obj = bpy.context.active_object
    obj.name = "_BasePlate"
    obj.scale = (PLATE_W / 2, PLATE_D / 2, PLATE_H / 2)
    make_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def build_hex_bolt(name, x, y):
    """
    Small hexagonal cylinder (6 vertices) representing a structural corner bolt.
    Sits flush on top of the base plate: bottom at z = PLATE_H.
    """
    z_centre = PLATE_H + BOLT_HEIGHT / 2
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6,
        radius=BOLT_RADIUS,
        depth=BOLT_HEIGHT,
        location=(x, y, z_centre),
    )
    obj = bpy.context.active_object
    obj.name = name
    return obj


def build_housing():
    """
    Solid semi-cylindrical housing guard, centred on the base plate.

    This arch is the visual cue that the lever arm rotates here.  The
    flat base of the arch sits at z = PIVOT_Z (top of the base plate).

    Geometry construction
    ---------------------
    The cross-section is a D-shape in the Y-Z plane:
      Arc:  (N+1) points from (y = −R, z = 0) sweeping upward to (y = +R, z = 0)
            using the parameterisation  y = −R·cos(t),  z_local = R·sin(t),
            t ∈ [0, π],  N = HOUSING_SEGS.
      The arc is extruded along X from −HOUSING_LEN/2 to +HOUSING_LEN/2.

    Resulting faces (N = HOUSING_SEGS = 8):
      N    outer side quads  — the curved outer surface of the arch
      1    front (N+1)-gon   — end cap at x = −HOUSING_LEN/2
      1    back  (N+1)-gon   — end cap at x = +HOUSING_LEN/2
      1    bottom quad        — seals the arch at z = PIVOT_Z; makes manifold
      ─────────────────────────────────────────────
      N+3  faces total        (11 for N=8)

    Because the mesh is a closed solid (every edge shared by exactly 2 faces),
    bmesh.ops.recalc_face_normals produces reliable outward-pointing normals.
    """
    R = HOUSING_RADIUS
    N = HOUSING_SEGS
    half_len = HOUSING_LEN / 2
    z_base = PIVOT_Z  # bottom of arch = top of plate = rotation axis Z

    bm = bmesh.new()

    front_verts = []  # vertices at x = −half_len  (front end cap, −X side)
    back_verts = []  # vertices at x = +half_len  (back end cap,  +X side)

    # Build arc profile: (N+1) points from (y=−R, z=0) up to (y=+R, z=0).
    for i in range(N + 1):
        t = math.pi * i / N
        y = -R * math.cos(t)  # −R → 0 → +R as t: 0 → π/2 → π
        z_local = R * math.sin(t)  #  0 → R →  0 as t: 0 → π/2 → π

        vf = bm.verts.new((-half_len, y, z_base + z_local))
        vb = bm.verts.new((half_len, y, z_base + z_local))
        front_verts.append(vf)
        back_verts.append(vb)

    bm.verts.ensure_lookup_table()

    # ── Outer curved surface — N side quads ──────────────────────────────────
    for i in range(N):
        bm.faces.new(
            [
                front_verts[i],
                back_verts[i],
                back_verts[i + 1],
                front_verts[i + 1],
            ]
        )

    # ── Front end cap  (x = −half_len) ───────────────────────────────────────
    # Reversed so recalc_face_normals can confirm −X outward normal.
    bm.faces.new(list(reversed(front_verts)))

    # ── Back end cap   (x = +half_len) ───────────────────────────────────────
    bm.faces.new(list(back_verts))

    # ── Bottom face — seals the arch at z_base, closes the manifold ──────────
    # Quad connecting the two base endpoints of each end cap.
    #   front_verts[ 0] = (−half_len, −R, z_base)
    #   front_verts[−1] = (−half_len, +R, z_base)
    #   back_verts[ 0]  = (+half_len, −R, z_base)
    #   back_verts[−1]  = (+half_len, +R, z_base)
    bm.faces.new(
        [
            front_verts[0],
            front_verts[-1],
            back_verts[-1],
            back_verts[0],
        ]
    )

    # Recalculate face normals on the closed solid for consistent outward winding.
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()

    mesh = bpy.data.meshes.new("_Housing")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new("_Housing", mesh)
    return link_obj(obj)


# ─── LEVER_HANDLE COMPONENTS ─────────────────────────────────────────────────


def build_shaft():
    """
    Vertical cylinder forming the lever arm.

    World bounds:
      Bottom  z = PIVOT_Z           = 0.040 m  (at the rotation axis)
      Centre  z = PIVOT_Z + L/2     = 0.300 m
      Top     z = PIVOT_Z + SHAFT_LEN = 0.560 m

    The cylinder is created centred at (0, 0, centre_z) so that after
    origin_set the bottom aligns exactly with the pivot.
    """
    centre_z = PIVOT_Z + SHAFT_LEN / 2  # 0.300 m
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12,
        radius=SHAFT_RADIUS,
        depth=SHAFT_LEN,
        location=(0.0, 0.0, centre_z),
    )
    obj = bpy.context.active_object
    obj.name = "_Shaft"
    return obj


def build_knob():
    """
    Spherical UV-sphere grip at the top of the shaft.
    Centred at (0, 0, KNOB_Z) = (0, 0, 0.560).
    16 longitude segments × 8 latitude rings give a clean, round silhouette.
    """
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16,
        ring_count=8,
        radius=KNOB_RADIUS,
        location=(0.0, 0.0, KNOB_Z),
    )
    obj = bpy.context.active_object
    obj.name = "_Knob"
    return obj


# ─── ASSEMBLY ────────────────────────────────────────────────────────────────


def build_scene():
    """
    Assemble the lever asset and return (lever_base, lever_handle).

    Lever_Base
    ----------
    Joined mesh of base plate + 4 hex bolts + housing arch.
    Origin placed at world (0, 0, 0) — the absolute bottom of the plate.
    This is the natural mounting point for placement in Roblox.

    Lever_Handle
    ------------
    Joined mesh of shaft cylinder + spherical knob.
    Origin placed at world (0, 0, PIVOT_Z = 0.040) — the exact centre of the
    housing arc and the physical rotation axis of the lever.

    CRITICAL PIVOT LOGIC:
    After join, the shaft object's origin is at its own geometric centre
    (0, 0, 0.30).  The set_origin_to_world call then moves the origin to
    (0, 0, 0.04), shifting every vertex in local space by +0.26 in Z.
    In Lever_Handle's LOCAL space the result is:
        local (0, 0, 0.00)  ←→  world (0, 0, 0.04)  = pivot / hinge
        local (0, 0, 0.26)  ←→  world (0, 0, 0.30)  = shaft centre
        local (0, 0, 0.52)  ←→  world (0, 0, 0.56)  = knob centre
    Rotating around LOCAL X in Roblox therefore hinges at the housing centre.

    Parenting
    ---------
    Setting lever_handle.parent = lever_base preserves world positions by
    updating matrix_parent_inverse automatically.  Lever_Handle's local
    position relative to Lever_Base will be (0, 0, PIVOT_Z).
    """
    clear_scene()

    # ── Construct Lever_Base ──────────────────────────────────────────────────
    base_plate = build_base_plate()

    # Four hex bolts at the plate corners, inset from the edges.
    bx = PLATE_W / 2 - BOLT_INSET_X  # 0.200 - 0.030 = 0.170
    by = PLATE_D / 2 - BOLT_INSET_Y  # 0.140 - 0.030 = 0.110

    bolt_fl = build_hex_bolt("_Bolt_FL", -bx, -by)  # front-left
    bolt_fr = build_hex_bolt("_Bolt_FR", +bx, -by)  # front-right
    bolt_bl = build_hex_bolt("_Bolt_BL", -bx, +by)  # back-left
    bolt_br = build_hex_bolt("_Bolt_BR", +bx, +by)  # back-right

    housing = build_housing()

    # Join all static components into a single Lever_Base mesh.
    lever_base = join_into(
        components=[base_plate, bolt_fl, bolt_fr, bolt_bl, bolt_br, housing],
        active_component=base_plate,
        final_name="Lever_Base",
    )
    # Origin at (0, 0, 0): the absolute bottom-centre of the base plate.
    set_origin_to_world(lever_base, 0.0, 0.0, 0.0)

    # ── Construct Lever_Handle ────────────────────────────────────────────────
    shaft = build_shaft()
    knob = build_knob()

    # Join shaft + knob into a single Lever_Handle mesh.
    lever_handle = join_into(
        components=[shaft, knob],
        active_component=shaft,
        final_name="Lever_Handle",
    )

    # CRITICAL: Place the origin at the rotation axis centre.
    # (0, 0, PIVOT_Z) is the centre of the housing arc and the physical
    # hinge point.  This single call is what makes the Roblox animation work.
    set_origin_to_world(lever_handle, 0.0, 0.0, PIVOT_Z)

    # ── Parent handle to base ─────────────────────────────────────────────────
    # The handle inherits the base's world transform (moves when the base
    # moves) while remaining independently rotatable for animation.
    lever_handle.parent = lever_base

    return lever_base, lever_handle


# ─── EXPORT ──────────────────────────────────────────────────────────────────


def export(lever_base, lever_handle):
    """
    Write lever_box.fbx and lever_box.blend to EXPORT_DIR.

    FBX settings
    ------------
    mesh_smooth_type = "FACE"    — flat shading preserves the industrial facets.
    axis_forward     = "-Z"     }
    axis_up          = "Y"      } convert Blender Z-up → Roblox Y-up.
    bake_space_transform = True  — bakes axis remapping into vertex data.
    """
    os.makedirs(EXPORT_DIR, exist_ok=True)

    fbx_path = os.path.join(EXPORT_DIR, "lever_box.fbx")
    blend_path = os.path.join(EXPORT_DIR, "lever_box.blend")

    bpy.ops.object.select_all(action="DESELECT")
    lever_base.select_set(True)
    lever_handle.select_set(True)
    make_active(lever_base)

    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        bake_space_transform=True,
    )
    print(f"➔ Exported FBX:  {fbx_path}")

    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"➔ Saved BLEND:   {blend_path}")

    # Verification summary printed to the Blender console.
    print()
    print("━" * 60)
    print("  lever_box  —  asset summary")
    print("━" * 60)
    print(
        f"  Lever_Base   origin  :  {tuple(round(v, 4) for v in lever_base.location)}"
    )
    print(
        f"  Lever_Handle origin  :  {tuple(round(v, 4) for v in lever_handle.location)}"
    )
    print(f"    ↳ pivot = rotation axis at z = {PIVOT_Z:.3f} m")
    print()
    print("  Structural layout (world space, at rest / vertical):")
    print(f"    Base plate      z ∈ [0.000, {PLATE_H:.3f}] m")
    print(f"    Housing arch    z ∈ [{PIVOT_Z:.3f}, {PIVOT_Z + HOUSING_RADIUS:.3f}] m")
    print(f"    Shaft           z ∈ [{PIVOT_Z:.3f}, {PIVOT_Z + SHAFT_LEN:.3f}] m")
    print(f"    Knob centre     z  = {KNOB_Z:.3f} m")
    print()
    print("  To animate in Roblox Studio (Lua):")
    print("    local h = model:FindFirstChild('Lever_Handle')")
    print("    h.CFrame = h.CFrame")
    print("               * CFrame.fromAxisAngle(Vector3.xAxis, math.rad(angle))")
    print("━" * 60)


# ─── ENTRY POINT ─────────────────────────────────────────────────────────────

lever_base, lever_handle = build_scene()
export(lever_base, lever_handle)
