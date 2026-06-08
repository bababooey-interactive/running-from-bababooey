"""
lantern.py — Low-poly stylized pagoda lantern for Roblox.
Target Blender/bpy version: 5.1.2

Hierarchy
---------
Lantern_Base  (root parent, origin at world 0,0,0)
  Lantern_Pillar_FL   tapered corner pillar — front-left
  Lantern_Pillar_FR   tapered corner pillar — front-right
  Lantern_Pillar_BL   tapered corner pillar — back-left
  Lantern_Pillar_BR   tapered corner pillar — back-right
  Lantern_Glass       inner tapered glass chamber (separate for Roblox materials)
  Lantern_Roof        pagoda flared roof (3-ring custom mesh)
  Lantern_Top_Collar  small square capping plate
  Lantern_Ring        thick vertical torus handle

Output (written to <cwd>/assets/models/)
-----------------------------------------
  lantern.fbx    — mesh asset for Roblox Studio
  lantern.blend  — source file for future Blender edits

No materials, colors, textures, or lights are assigned.
"""

import math
import os

import bmesh
import bpy

# ─── DIMENSIONS ──────────────────────────────────────────────────────────────

# Base plate
BASE_HALF = 0.300  # XY half-extent → footprint 0.60 × 0.60
BASE_H = 0.060  # height of base plate

# Main chamber (four tapered pillars + inner glass box)
CHAMBER_H = 0.500
CHAMBER_BOT_Z = BASE_H  # 0.060
CHAMBER_TOP_Z = BASE_H + CHAMBER_H  # 0.560

# Corner pillar dimensions — both center XY and cross-section grow upward,
# giving the chamber its characteristic outward taper.
PIL_BOT_C = 0.215  # center XY offset at bottom
PIL_TOP_C = 0.255  # center XY offset at top  (leans outward)
PIL_BOT_HS = 0.030  # half cross-section at bottom
PIL_TOP_HS = 0.035  # half cross-section at top

# Inner glass chamber — tapered to match the pillar spread
GLASS_BOT_H = 0.160  # XY half-extent at bottom (inside pillar inner faces)
GLASS_TOP_H = 0.205  # XY half-extent at top

# Pagoda roof — three concentric vertex rings
ROOF_EAVE_R = 0.460  # outer eave half-extent
ROOF_EAVE_Z = CHAMBER_TOP_Z - 0.025  # 0.535 — droops slightly below frame top
ROOF_MID_R = 0.310  # mid-slope half-extent
ROOF_MID_Z = CHAMBER_TOP_Z + 0.040  # 0.600 — inflection between eave and body
ROOF_PEAK_R = 0.170  # peak half-extent
ROOF_PEAK_Z = CHAMBER_TOP_Z + 0.280  # 0.840

# Top collar — small square plate capping the roof peak
COLLAR_HALF = 0.170  # XY half-extent
COLLAR_H = 0.050
COLLAR_BOT_Z = ROOF_PEAK_Z  # 0.840
COLLAR_TOP_Z = COLLAR_BOT_Z + COLLAR_H  # 0.890

# Ring handle — vertical torus so it reads as a grab / hang loop
RING_MAJOR_R = 0.110  # outer radius of the ring
RING_MINOR_R = 0.042  # tube radius (makes it "thick")
# Place centre so the ring's lowest arc is flush with the collar top
RING_Z = COLLAR_TOP_Z + RING_MAJOR_R  # 1.000

# ─────────────────────────────────────────────────────────────────────────────


# ─── SCENE UTILITIES ─────────────────────────────────────────────────────────


def clear_scene():
    """Delete every object and remove orphaned mesh data blocks."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def link_obj(obj):
    """Link an object into the active scene collection and return it."""
    bpy.context.collection.objects.link(obj)
    return obj


# ─── MESH CONSTRUCTION HELPERS ───────────────────────────────────────────────


def build_mesh_object(name, verts, faces):
    """
    Create a named Blender object from raw vertex coordinates and face index
    lists.  Uses BMesh for geometry construction and runs recalc_face_normals
    so that all face normals consistently point outward on closed manifold
    meshes.

    Parameters
    ----------
    name  : str            — object and mesh data-block name
    verts : list of 3-tuple — (x, y, z) vertex coordinates in world space
    faces : list of tuple   — each entry is an ordered sequence of vertex
                               indices forming one polygon (CCW from outside)

    Returns
    -------
    bpy.types.Object  (already linked into the active collection)
    """
    bm = bmesh.new()
    bm_verts = [bm.verts.new(co) for co in verts]
    bm.verts.ensure_lookup_table()
    for face_indices in faces:
        bm.faces.new([bm_verts[i] for i in face_indices])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    return link_obj(obj)


def make_tapered_box(
    name, bot_hx, bot_hy, top_hx, top_hy, z_bot, z_top, cx=0.0, cy=0.0
):
    """
    Closed tapered rectangular prism (frustum box).

    Vertex layout
    -------------
      0 = front-left  bottom    4 = front-left  top
      1 = front-right bottom    5 = front-right top
      2 = back-right  bottom    6 = back-right  top
      3 = back-left   bottom    7 = back-left   top

    Face winding is CCW when viewed from outside so that
    recalc_face_normals can confirm outward normals reliably.
    """
    v = [
        (cx - bot_hx, cy - bot_hy, z_bot),  # 0
        (cx + bot_hx, cy - bot_hy, z_bot),  # 1
        (cx + bot_hx, cy + bot_hy, z_bot),  # 2
        (cx - bot_hx, cy + bot_hy, z_bot),  # 3
        (cx - top_hx, cy - top_hy, z_top),  # 4
        (cx + top_hx, cy - top_hy, z_top),  # 5
        (cx + top_hx, cy + top_hy, z_top),  # 6
        (cx - top_hx, cy + top_hy, z_top),  # 7
    ]
    f = [
        (3, 2, 1, 0),  # bottom  –Z outward
        (4, 5, 6, 7),  # top     +Z outward
        (0, 1, 5, 4),  # front   –Y outward
        (1, 2, 6, 5),  # right   +X outward
        (2, 3, 7, 6),  # back    +Y outward
        (3, 0, 4, 7),  # left    –X outward
    ]
    return build_mesh_object(name, v, f)


# ─── COMPONENT CREATORS ──────────────────────────────────────────────────────


def create_base():
    """
    Flat square base plate.
    Spans z = 0.000 → BASE_H (0.060).
    This object serves as the root parent for the entire hierarchy.
    """
    return make_tapered_box(
        "Lantern_Base",
        BASE_HALF,
        BASE_HALF,  # bottom half-extents (uniform, straight sides)
        BASE_HALF,
        BASE_HALF,  # top half-extents
        0.0,
        BASE_H,
    )


def create_pillar(sx, sy):
    """
    Single tapered corner pillar for the main chamber frame.

    The pillar leans slightly outward as it rises: both its XY centre
    position and its cross-section grow from bottom to top, producing
    the outward taper of the chamber.

    Parameters
    ----------
    sx : int  — X-axis sign: -1 for left,  +1 for right
    sy : int  — Y-axis sign: -1 for front, +1 for back
    """
    label = ("F" if sy < 0 else "B") + ("L" if sx < 0 else "R")
    name = f"Lantern_Pillar_{label}"

    # Centre positions at bottom and top
    bcx, bcy = sx * PIL_BOT_C, sy * PIL_BOT_C
    tcx, tcy = sx * PIL_TOP_C, sy * PIL_TOP_C
    bhs, ths = PIL_BOT_HS, PIL_TOP_HS
    z0, z1 = CHAMBER_BOT_Z, CHAMBER_TOP_Z

    v = [
        (bcx - bhs, bcy - bhs, z0),  # 0
        (bcx + bhs, bcy - bhs, z0),  # 1
        (bcx + bhs, bcy + bhs, z0),  # 2
        (bcx - bhs, bcy + bhs, z0),  # 3
        (tcx - ths, tcy - ths, z1),  # 4
        (tcx + ths, tcy - ths, z1),  # 5
        (tcx + ths, tcy + ths, z1),  # 6
        (tcx - ths, tcy + ths, z1),  # 7
    ]
    f = [
        (3, 2, 1, 0),  # bottom
        (4, 5, 6, 7),  # top
        (0, 1, 5, 4),  # front
        (1, 2, 6, 5),  # right
        (2, 3, 7, 6),  # back
        (3, 0, 4, 7),  # left
    ]
    return build_mesh_object(name, v, f)


def create_glass():
    """
    Inner glass chamber that fills the space framed by the four corner pillars.

    Named 'Lantern_Glass' so it can be targeted independently in Roblox Studio
    to receive a transparency or neon material without affecting the frame.

    The box is wider at the top than the bottom, matching the outward taper of
    the surrounding pillar frame.
    """
    return make_tapered_box(
        "Lantern_Glass",
        GLASS_BOT_H,
        GLASS_BOT_H,  # bottom half-extents
        GLASS_TOP_H,
        GLASS_TOP_H,  # top half-extents (wider)
        CHAMBER_BOT_Z,
        CHAMBER_TOP_Z,
    )


def create_roof():
    """
    Pagoda-style flared roof built from three concentric square vertex rings.

    Ring 0 — outer eave :  widest, positioned slightly below the frame top
                            to create the characteristic droop of a pagoda eave.
    Ring 1 — mid slope  :  narrower, above the frame; inflection between the
                            spreading eave and the converging body.
    Ring 2 — peak       :  narrowest; forms the apex of the roof.

    Topology: 12 vertices, 10 quad faces (closed manifold).
      4 eave-slope faces  (ring 0 → ring 1)
      4 body-slope faces  (ring 1 → ring 2)
      1 top cap           (ring 2 square)
      1 bottom cap        (ring 0 square, closes the solid for clean normals)

    The bottom cap sits below the chamber top and is hidden inside the lantern
    body at runtime; it exists solely to make the mesh manifold so that
    recalc_face_normals works reliably.
    """
    er, ez = ROOF_EAVE_R, ROOF_EAVE_Z
    mr, mz = ROOF_MID_R, ROOF_MID_Z
    pr, pz = ROOF_PEAK_R, ROOF_PEAK_Z

    v = [
        # Ring 0 — outer eave (4 vertices)
        (-er, -er, ez),  #  0  front-left
        (er, -er, ez),  #  1  front-right
        (er, er, ez),  #  2  back-right
        (-er, er, ez),  #  3  back-left
        # Ring 1 — mid slope (4 vertices)
        (-mr, -mr, mz),  #  4  front-left
        (mr, -mr, mz),  #  5  front-right
        (mr, mr, mz),  #  6  back-right
        (-mr, mr, mz),  #  7  back-left
        # Ring 2 — peak (4 vertices)
        (-pr, -pr, pz),  #  8  front-left
        (pr, -pr, pz),  #  9  front-right
        (pr, pr, pz),  # 10  back-right
        (-pr, pr, pz),  # 11  back-left
    ]
    f = [
        # Eave slopes (ring 0 → ring 1): the spreading, drooped overhang
        (0, 1, 5, 4),  # front eave
        (1, 2, 6, 5),  # right eave
        (2, 3, 7, 6),  # back eave
        (3, 0, 4, 7),  # left eave
        # Body slopes (ring 1 → ring 2): converging upper roof
        (4, 5, 9, 8),  # front body
        (5, 6, 10, 9),  # right body
        (6, 7, 11, 10),  # back body
        (7, 4, 8, 11),  # left body
        # Caps — close the solid
        (8, 9, 10, 11),  # top cap    (+Z outward)
        (3, 2, 1, 0),  # bottom cap (–Z outward, closes manifold)
    ]
    return build_mesh_object("Lantern_Roof", v, f)


def create_top_collar():
    """
    Small square capping plate sitting on top of the roof peak, between
    the peak and the ring handle.
    Spans z = COLLAR_BOT_Z → COLLAR_TOP_Z (0.840 → 0.890).
    """
    return make_tapered_box(
        "Lantern_Top_Collar",
        COLLAR_HALF,
        COLLAR_HALF,
        COLLAR_HALF,
        COLLAR_HALF,
        COLLAR_BOT_Z,
        COLLAR_TOP_Z,
    )


def create_ring():
    """
    Thick torus ring handle mounted on top of the collar.

    Oriented vertically (ring plane in XZ, axis along Y) so it reads as
    an arch / carry handle.  The ring's lowest arc is flush with the top
    of the collar (COLLAR_TOP_Z).

    Uses a low segment count for a faceted, stylised low-poly appearance.
    """
    bpy.ops.mesh.primitive_torus_add(
        major_radius=RING_MAJOR_R,
        minor_radius=RING_MINOR_R,
        major_segments=12,
        minor_segments=8,
        location=(0.0, 0.0, RING_Z),
        rotation=(math.pi / 2, 0.0, 0.0),  # 90° X-rotation → ring stands upright
    )
    ring = bpy.context.active_object
    ring.name = "Lantern_Ring"
    return ring


# ─── ASSEMBLY ────────────────────────────────────────────────────────────────


def build_lantern():
    """
    Instantiate every component, establish the parent hierarchy, and pin the
    root origin to (0, 0, 0) at the absolute bottom of the base plate.

    Returns
    -------
    bpy.types.Object  — the root Lantern_Base object
    """
    clear_scene()

    # Create all components
    base = create_base()

    pil_fl = create_pillar(-1, -1)  # front-left
    pil_fr = create_pillar(1, -1)  # front-right
    pil_bl = create_pillar(-1, 1)  # back-left
    pil_br = create_pillar(1, 1)  # back-right

    glass = create_glass()
    roof = create_roof()
    collar = create_top_collar()
    ring = create_ring()

    # Parent all components to the base plate.
    # Setting .parent directly preserves each child's world-space position
    # by updating its matrix_parent_inverse automatically.
    children = (pil_fl, pil_fr, pil_bl, pil_br, glass, roof, collar, ring)
    for child in children:
        child.parent = base

    # Confirm the root origin sits at the absolute bottom of the lantern (z=0).
    # The base mesh was built with its lowest vertices already at z=0, so this
    # is a no-op in practice but makes the intent explicit.
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    return base


# ─── EXPORT ──────────────────────────────────────────────────────────────────


def export_lantern(base):
    """
    Export the assembled lantern hierarchy.

    Files written
    -------------
      <cwd>/assets/models/lantern.fbx    — for Roblox Studio import
      <cwd>/assets/models/lantern.blend  — source project for Blender editing

    Axis remapping converts Blender's Z-up coordinate system to the Y-up
    system used by Roblox Studio (axis_forward="-Z", axis_up="Y").
    """
    export_dir = os.path.join(os.getcwd(), "..", "models")
    os.makedirs(export_dir, exist_ok=True)

    fbx_path = os.path.join(export_dir, "lantern.fbx")
    blend_path = os.path.join(export_dir, "lantern.blend")

    # Select the root and every object in its subtree for export
    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    for child in base.children_recursive:
        child.select_set(True)

    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        mesh_smooth_type="FACE",  # flat shading preserves the low-poly facets
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        bake_space_transform=True,  # bakes axis conversion into mesh data
    )
    print(f"➔ Exported FBX:  {fbx_path}")

    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"➔ Saved BLEND:   {blend_path}")

    print()
    print("Lantern structure summary:")
    print(
        f"  Total height  ≈ {RING_Z + RING_MAJOR_R + RING_MINOR_R:.3f} m  "
        f"(base bottom → ring apex)"
    )
    print(f"  Base footprint: {BASE_HALF * 2:.2f} × {BASE_HALF * 2:.2f} m")
    print(f"  Chamber:        z {CHAMBER_BOT_Z:.3f} → {CHAMBER_TOP_Z:.3f}")
    print(f"  Roof eave:      z {ROOF_EAVE_Z:.3f}  r ±{ROOF_EAVE_R:.3f}")
    print(f"  Roof peak:      z {ROOF_PEAK_Z:.3f}  r ±{ROOF_PEAK_R:.3f}")
    print(
        f"  Ring centre:    z {RING_Z:.3f}  "
        f"(major r {RING_MAJOR_R}, minor r {RING_MINOR_R})"
    )
    print()
    print("In Roblox Studio:")
    print(
        "  • Select 'Lantern_Glass' and apply a transparent or neon SurfaceAppearance."
    )
    print(
        "  • Add a PointLight inside Lantern_Glass; recommended Brightness=5, Range=16."
    )


# ─── ENTRY POINT ─────────────────────────────────────────────────────────────

root = build_lantern()
export_lantern(root)
