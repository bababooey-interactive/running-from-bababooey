"""
coal_generator.py — Procedurally generate 5 distinct low-poly coal chunks for Roblox.

Usage: Run from Blender's Scripting panel (Text > Run Script).
       Launch Blender from the project root so os.getcwd() resolves correctly.

Algorithm per chunk
-------------------
  1. Set a unique per-chunk seed for full reproducibility.
  2. Sample three independent scale factors (X / Y / Z) from that seed.
  3. Build a 0.30 m cube via bmesh.ops.create_cube.
  4. Subdivide all edges once (cuts=1, use_grid_fill=True):
       8 corners + 12 edge midpoints + 6 face centres = 26 vertices, 24 quad faces.
  5. Displace every vertex with a bimodal magnitude:
       ~35 % of verts  → large offset (0.04–0.09 m)  → sharp edges / protrusions.
       ~65 % of verts  → tiny offset  (0.00–0.022 m)  → flat structural facets.
  6. Recalculate face normals for a consistent outward winding.
  7. Apply the pre-sampled non-uniform scale (different silhouette per chunk).
  8. Bake all transforms so the FBX carries no pending scale data.
  9. Centre the object origin at the mesh geometric centroid.
  10. Export to <cwd>/assets/models/coal_N.fbx.

No materials, lights, or textures are added.
Output: coal_1.fbx  coal_2.fbx  coal_3.fbx  coal_4.fbx  coal_5.fbx
"""

import os
import random

import bmesh
import bpy

# ─── CONFIGURATION ────────────────────────────────────────────────────────────

# Export root — CWD-relative so the script works when Blender is launched from
# the project root directory (e.g. `blender --python .../coal_generator.py`).
EXPORT_DIR = os.path.join(os.getcwd(), "..", "models")

# Base cube edge length in metres.
# After non-uniform scale each finished chunk spans roughly 0.15 – 0.42 m.
BASE_CUBE_SIZE = 0.30

# One deterministic seed per chunk.  Changing a single seed re-rolls only
# that piece without affecting the other four.
CHUNK_SEEDS = [17, 83, 251, 512, 999]

# Independent per-axis scale ranges — the primary driver of silhouette variety.
# Z is intentionally compressed so the lumps read as ground-picked objects.
SCALE_X_RANGE = (0.80, 1.40)
SCALE_Y_RANGE = (0.70, 1.30)
SCALE_Z_RANGE = (0.50, 0.88)

# Bimodal displacement parameters.
# The two-tier approach produces the required mix of flat facets (low-disp verts)
# and sharp, unpredictable edges (high-disp verts).
DISP_SHARP_RANGE = (0.04, 0.09)  # 27 – 60 % of cube half-extent → protrusions
DISP_FLAT_RANGE = (0.00, 0.022)  # 0  – 15 % of cube half-extent → flat regions
SHARP_PROB = 0.35  # probability that a vertex gets large displacement

# ─────────────────────────────────────────────────────────────────────────────


def clear_scene():
    """Delete all scene objects and remove orphaned mesh data-blocks."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def displace_vertex(co):
    """
    Perturb a single BMesh vertex coordinate in-place using a bimodal magnitude.

    Two possible displacement tiers are chosen probabilistically:

      Tier A (SHARP)  p = SHARP_PROB  → large random offset in every axis.
                                         Adjacent verts on the same face that
                                         land in opposite tiers produce the
                                         sharp crease / protrusion effect.

      Tier B (FLAT)   p = 1 - SHARP_PROB → near-zero offset.
                                         When several neighbours are all Flat,
                                         the local surface stays roughly planar,
                                         creating the structural facet look.

    Random call budget per invocation (5 total — kept fixed so the scale
    factors drawn before the loop are not affected by DISP tuning):
      1 × random.random()   — tier branch
      1 × random.uniform()  — magnitude
      3 × random.uniform()  — per-axis signed offset
    """
    if random.random() < SHARP_PROB:
        magnitude = random.uniform(*DISP_SHARP_RANGE)
    else:
        magnitude = random.uniform(*DISP_FLAT_RANGE)

    co.x += random.uniform(-magnitude, magnitude)
    co.y += random.uniform(-magnitude, magnitude)
    co.z += random.uniform(-magnitude, magnitude)


def generate_chunk(variation_index, seed):
    """
    Procedurally build one coal chunk and return its linked bpy.types.Object.

    Parameters
    ----------
    variation_index : int — 1-based label used in the object name (Coal_1 … Coal_5)
    seed            : int — random seed; unique per chunk for distinct shapes

    Returns
    -------
    bpy.types.Object — mesh with all transforms applied, origin at centroid
    """
    # ── Seed the RNG once per chunk ───────────────────────────────────────────
    random.seed(seed)

    # ── 1. Sample scale factors first ─────────────────────────────────────────
    # Drawing them before the displacement loop means that changing DISP_*
    # constants later will not alter the chunk's overall proportions.
    scale_x = random.uniform(*SCALE_X_RANGE)
    scale_y = random.uniform(*SCALE_Y_RANGE)
    scale_z = random.uniform(*SCALE_Z_RANGE)

    # ── 2. Build a cube in BMesh ──────────────────────────────────────────────
    # bmesh.ops.create_cube places vertices at ± (size / 2) on every axis.
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=BASE_CUBE_SIZE)

    # ── 3. Subdivide all edges once ───────────────────────────────────────────
    # Snapshot the pre-subdivision edge list before the topology mutates.
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    pre_subdiv_edges = bm.edges[:]

    bmesh.ops.subdivide_edges(
        bm,
        edges=pre_subdiv_edges,
        cuts=1,  # one new vertex per edge
        use_grid_fill=True,  # subdivide each face into a 2 × 2 quad grid
        smooth=0.0,  # no Catmull-Clark softening — stays blocky
    )
    # Resulting topology: 26 verts (8 corners + 12 edge midpoints + 6 face
    # centres), 24 quads (4 per original cube face).

    # ── 4. Bimodal vertex displacement ────────────────────────────────────────
    # Rebuild the lookup table after topology changed.
    bm.verts.ensure_lookup_table()
    for vert in bm.verts:
        displace_vertex(vert.co)

    # ── 5. Consistent outward face normals ────────────────────────────────────
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()

    # ── 6. Commit to a Blender mesh object ────────────────────────────────────
    obj_name = f"Coal_{variation_index}"
    mesh = bpy.data.meshes.new(obj_name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new(obj_name, mesh)
    bpy.context.collection.objects.link(obj)

    # ── 7. Apply non-uniform scale ────────────────────────────────────────────
    # Set as an object transform, then immediately bake it into vertex positions
    # with transform_apply so the exported FBX carries no pending scale data.
    obj.scale = (scale_x, scale_y, scale_z)

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # ── 8. Centre the origin at the geometric centroid ────────────────────────
    # Displacement and non-uniform scale shift the centroid away from the world
    # origin.  Resetting it to ORIGIN_GEOMETRY ensures the Roblox part pivot
    # lands at the visual centre of the coal piece, which makes script-driven
    # placement and physics predictable.
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="MEDIAN")

    return obj


def export_chunk(obj, variation_index):
    """
    Export one fully prepared coal chunk as a standalone FBX file.

    Parameters
    ----------
    obj             : bpy.types.Object
    variation_index : int — suffix for the filename (coal_1.fbx … coal_5.fbx)
    """
    os.makedirs(EXPORT_DIR, exist_ok=True)
    fbx_path = os.path.join(EXPORT_DIR, f"coal_{variation_index}.fbx")

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        mesh_smooth_type="FACE",  # per-face (flat) normals; low-poly facets show clearly
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",  # Blender Z-up → Roblox Y-up
        axis_up="Y",
        use_mesh_modifiers=True,
        bake_space_transform=True,  # bakes axis remapping into vertex data
    )
    print(f"      ➔  {fbx_path}")


def main():
    """
    Generate and export all five coal chunk variations.

    Each iteration:
      • Clears the scene completely (no leftover data between chunks).
      • Generates a unique mesh using its dedicated seed.
      • Reports vertex / face count so you can confirm low-poly geometry.
      • Writes a standalone FBX.
    """
    print()
    print("━" * 54)
    print("  coal_generator.py  —  5 unique coal chunks")
    print("━" * 54)

    for i, seed in enumerate(CHUNK_SEEDS, start=1):
        print(f"\n  [{i}/5]  Coal_{i}  (seed = {seed})")

        clear_scene()
        chunk = generate_chunk(i, seed)

        vcount = len(chunk.data.vertices)
        fcount = len(chunk.data.polygons)
        print(f"         mesh  :  {vcount} verts  /  {fcount} faces")

        export_chunk(chunk, i)

    print()
    print("━" * 54)
    print(f"  ✓  All 5 chunks exported to:")
    print(f"     {EXPORT_DIR}")
    print("━" * 54)
    print()


main()
