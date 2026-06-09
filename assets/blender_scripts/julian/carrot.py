"""
Blender Python Script: Low-Poly Stylized Carrot (v3)
Game: Bababooeys Can (Not) Move
Compatible: Blender 4.x / 5.x
Fix v3:
  - Hapus SMOOTH_BY_ANGLE modifier (tidak ada di Blender 5.x)
  - Ganti dengan EDGE_SPLIT modifier (selalu tersedia)
Output: ~/Carrot.fbx
"""

import bpy
import bmesh
import math
import random
import os

# ──────────────────────────────────────────────
# 0. CLEAN SCENE
# ──────────────────────────────────────────────
def clean_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)

clean_scene()
random.seed(42)


# ──────────────────────────────────────────────
# 1. MATERIALS
# ──────────────────────────────────────────────
def set_input_safe(bsdf, names, value):
    for n in names:
        if n in bsdf.inputs:
            bsdf.inputs[n].default_value = value
            return

def make_material(name, r, g, b):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value  = 0.75
        set_input_safe(bsdf, ["Specular IOR Level", "Specular"], 0.05)
    return mat

mat_carrot = make_material("Mat_Carrot", 0.95, 0.45, 0.05)   # oranye vivid
mat_stem   = make_material("Mat_Stem",   0.22, 0.65, 0.12)   # hijau daun


# ──────────────────────────────────────────────
# 2. HELPER
# ──────────────────────────────────────────────
def bm_to_object(bm, name):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# ──────────────────────────────────────────────
# 3. CARROT BODY  (tapered + random ring bumps)
# ──────────────────────────────────────────────
def build_carrot_body():
    """
    Wortel low-poly dengan:
    - Bahu lebih besar
    - Pangkal daun sedikit cekung
    - Tekstur ring alami
    - Ujung lancip
    """

    bm = bmesh.new()

    SEGS   = 8
    TOP_R  = 0.14
    BOT_R  = 0.004
    HEIGHT = 0.85
    RINGS  = 12

    verts_by_ring = []

    for ri in range(RINGS):

        t = ri / (RINGS - 1)
        z = HEIGHT * (1.0 - t)

        # Profil wortel lebih natural
        if t < 0.25:
            base_r = TOP_R * (1.0 - 0.15 * (t / 0.25))
        else:
            nt = (t - 0.25) / 0.75
            base_r = (TOP_R * 0.85) * (1.0 - nt) + BOT_R * nt

        # Tekstur ring
        jitter = random.uniform(-0.12, 0.12) if 0.1 < t < 0.9 else 0.0
        ring_pattern = math.sin(t * 30.0) * 0.03

        r = max(
            base_r * (1.0 + jitter) * (1.0 + ring_pattern),
            0.003
        )

        # Cekungan di pangkal daun
        if ri == 0:
            r *= 0.85
        elif ri == 1:
            r *= 0.92

        ring = []

        for si in range(SEGS):

            a = 2 * math.pi * si / SEGS

            if 0.15 < t < 0.85:
                a += random.uniform(-0.06, 0.06)

            ring.append(
                bm.verts.new(
                    (
                        math.cos(a) * r,
                        math.sin(a) * r,
                        z
                    )
                )
            )

        verts_by_ring.append(ring)

    # Tip bawah
    tip_v = bm.verts.new((0, 0, 0))

    for ri in range(RINGS - 1):
        curr = verts_by_ring[ri]
        nxt  = verts_by_ring[ri + 1]

        for si in range(SEGS):
            ni = (si + 1) % SEGS

            bm.faces.new([
                curr[si],
                curr[ni],
                nxt[ni],
                nxt[si]
            ])

    last = verts_by_ring[-1]

    for si in range(SEGS):
        ni = (si + 1) % SEGS

        bm.faces.new([
            last[ni],
            tip_v,
            last[si]
        ])

    # Cap atas
    top_center = bm.verts.new((0, 0, HEIGHT))
    top_ring   = verts_by_ring[0]

    for si in range(SEGS):
        ni = (si + 1) % SEGS

        bm.faces.new([
            top_ring[si],
            top_center,
            top_ring[ni]
        ])

    bmesh.ops.recalc_face_normals(
        bm,
        faces=bm.faces
    )

    obj = bm_to_object(bm, "Carrot_Body")
    obj.data.materials.append(mat_carrot)

    return obj, HEIGHT


# ──────────────────────────────────────────────
# 4. TANGKAI DAUN  (3 buah, menyebar seperti kipas)
# ──────────────────────────────────────────────
def build_stem(index, total, carrot_top_z):
    """Silinder tipis taper, sedikit miring ke luar."""
    SEGS   = 4
    RADIUS = 0.010
    LENGTH = 0.42

    spread = [-45, -20, 0, 20, 45]
    lean    = math.radians(spread[index])
    x_off   = (index - (total - 1) / 2.0) * 0.055

    bm    = bmesh.new()
    rings = []
    SSEGS = 3

    for si in range(SSEGS):
        t     = si / (SSEGS - 1)
        r     = RADIUS * (1.0 - t * 0.80)
        seg_z = carrot_top_z + t * LENGTH * math.cos(lean)
        seg_x = x_off        + t * LENGTH * math.sin(lean)
        ring  = []
        for vi in range(SEGS):
            a = 2 * math.pi * vi / SEGS
            ring.append(bm.verts.new((seg_x + math.cos(a) * r, math.sin(a) * r, seg_z)))
        rings.append(ring)

    for ri in range(SSEGS - 1):
        curr, nxt = rings[ri], rings[ri + 1]
        for vi in range(SEGS):
            ni = (vi + 1) % SEGS
            bm.faces.new([curr[vi], curr[ni], nxt[ni], nxt[vi]])

    # Ujung lancip tangkai
    tip_v = bm.verts.new((x_off + LENGTH * math.sin(lean), 0, carrot_top_z + LENGTH * math.cos(lean)))
    for vi in range(SEGS):
        ni = (vi + 1) % SEGS
        bm.faces.new([rings[-1][vi], rings[-1][ni], tip_v])

    # Cap pangkal
    base_c = bm.verts.new((x_off, 0, carrot_top_z))
    for vi in range(SEGS):
        ni = (vi + 1) % SEGS
        bm.faces.new([rings[0][ni], rings[0][vi], base_c])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = bm_to_object(bm, f"Stem_{index}")
    obj.data.materials.append(mat_stem)
    return obj


# ──────────────────────────────────────────────
# 5. ASSEMBLE & JOIN
# ──────────────────────────────────────────────
carrot_obj, carrot_height = build_carrot_body()
stem_objs = [build_stem(i, 5, carrot_height) for i in range(5)]

bpy.ops.object.select_all(action='DESELECT')
for obj in [carrot_obj] + stem_objs:
    obj.select_set(True)
bpy.context.view_layer.objects.active = carrot_obj
bpy.ops.object.join()

final           = bpy.context.active_object
final.name      = "Carrot"
final.data.name = "Carrot"

# ──────────────────────────────────────────────
# 6. ORIGIN → CENTER  (Roblox pivot)
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
final.select_set(True)
bpy.context.view_layer.objects.active = final
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
final.location = (0, 0, 0)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ──────────────────────────────────────────────
# 7. SMOOTH SHADING  — pakai EDGE_SPLIT (tersedia di semua versi)
#    SMOOTH_BY_ANGLE tidak tersedia di semua build Blender 5.x
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
final.select_set(True)
bpy.context.view_layer.objects.active = final

bpy.ops.object.shade_smooth()   # aktifkan smooth shading dulu

# EDGE_SPLIT: edge di atas 55° akan tetap sharp → low-poly faceted look
mod = final.modifiers.new(name="EdgeSplit", type='EDGE_SPLIT')
mod.split_angle    = math.radians(55)
mod.use_edge_angle = True
mod.use_edge_sharp = True

# ──────────────────────────────────────────────
# 8. EXPORT FBX  (Roblox settings)
# ──────────────────────────────────────────────
export_path = os.path.join(os.path.expanduser("~"), "Carrot.fbx")

bpy.ops.object.select_all(action='DESELECT')
final.select_set(True)

bpy.ops.export_scene.fbx(
    filepath             = export_path,
    use_selection        = True,
    apply_unit_scale     = True,
    apply_scale_options  = 'FBX_SCALE_ALL',
    axis_up              = 'Y',
    axis_forward         = '-Z',
    bake_space_transform = True,
    mesh_smooth_type     = 'FACE',
    use_mesh_modifiers   = True,
    add_leaf_bones       = False,
    path_mode            = 'COPY',
    embed_textures       = False,
)

print(f"[Carrot v3] Blender {bpy.app.version[0]}.{bpy.app.version[1]} — export OK")
print(f"[Carrot v3] Exported → {export_path}")
print(f"[Carrot v3] Tri count ≈ {sum(len(p.vertices) - 2 for p in final.data.polygons)}")

# Kok ga keikut isinya
