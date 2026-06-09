"""
Blender Python Script: Low-Poly Stylized Meat on a Bone  (v3)
Game: Bababooeys Can (Not) Move
Compatible: Blender 4.x / 5.x
Fix v3:
  - Satu tulang di tengah (horizontal, sejajar sumbu X)
  - Daging dirotate 90° agar silinder horizontal sejajar tulang
  - Smooth shading tanpa SMOOTH_BY_ANGLE modifier
Output: ~/Meat.fbx
"""

import bpy
import bmesh
import math
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
        bsdf.inputs["Roughness"].default_value  = 0.8
        set_input_safe(bsdf, ["Specular IOR Level", "Specular"], 0.1)
    return mat

mat_meat = make_material("Mat_Meat", 0.85, 0.20, 0.18)   # merah/pink
mat_bone = make_material("Mat_Bone", 0.92, 0.89, 0.82)   # beige/tulang


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
# 3. DAGING  — silinder HORIZONTAL (sepanjang sumbu X)
#    Pinched di tengah → bentuk seperti steak/drum
# ──────────────────────────────────────────────
def build_meat():
    """
    Silinder horizontal: sumbu memanjang = X
    Radius = arah Y dan Z
    Pinch di ring tengah agar terlihat seperti potongan daging
    """
    bm     = bmesh.new()
    SEGS   = 8       # segmen radial (low-poly)
    RADIUS = 0.30    # radius daging
    LENGTH = 0.60    # panjang sepanjang sumbu X
    LAYERS = 4       # jumlah ring vertikal

    # Scale per ring — ring tengah diperkecil (pinch effect)
    scales = [1.0, 0.90, 0.78, 0.90, 1.0]

    verts_by_ring = []
    for li in range(LAYERS + 1):
        # x berjalan dari -LENGTH/2 sampai +LENGTH/2
        x = -LENGTH / 2 + LENGTH * li / LAYERS
        s = scales[li] * RADIUS
        ring = []
        for si in range(SEGS):
            a = 2 * math.pi * si / SEGS
            # Silinder horizontal: Y dan Z adalah radius, X adalah panjang
            y = math.cos(a) * s
            z = math.sin(a) * s
            ring.append(bm.verts.new((x, y, z)))
        verts_by_ring.append(ring)

    # Sisi (quad faces)
    for li in range(LAYERS):
        curr, nxt = verts_by_ring[li], verts_by_ring[li + 1]
        for si in range(SEGS):
            ni = (si + 1) % SEGS
            bm.faces.new([curr[si], curr[ni], nxt[ni], nxt[si]])

    # Cap kanan (tutup ujung +X) — fan
    cap_r = bm.verts.new((LENGTH / 2, 0, 0))
    for si in range(SEGS):
        ni = (si + 1) % SEGS
        bm.faces.new([verts_by_ring[-1][si], cap_r, verts_by_ring[-1][ni]])

    # Cap kiri (tutup ujung -X) — fan, winding dibalik
    cap_l = bm.verts.new((-LENGTH / 2, 0, 0))
    for si in range(SEGS):
        ni = (si + 1) % SEGS
        bm.faces.new([verts_by_ring[0][ni], cap_l, verts_by_ring[0][si]])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = bm_to_object(bm, "Meat_Body")
    obj.data.materials.append(mat_meat)
    return obj


# ──────────────────────────────────────────────
# 4. SATU TULANG DI TENGAH  — menembus daging secara horizontal
#    Struktur: shaft silinder + bola di kedua ujung
# ──────────────────────────────────────────────
def build_single_bone():
    """
    Satu tulang horizontal sepanjang sumbu X.
    Shaft radius kecil, kedua ujung ada knob (bola gepeng = joint).
    Total panjang tulang > panjang daging agar mencuat keluar.
    """
    bm = bmesh.new()

    SEGS      = 8       # segmen radial
    SHAFT_R   = 0.045   # radius shaft tulang
    BONE_HALF = 0.70    # setengah panjang tulang (total = 1.40)
    KNOB_R    = 0.14    # radius bola ujung
    KNOB_FLAT = 0.70    # faktor flatten bola di arah X (biar pipih)

    # ── Shaft: 3 ring sepanjang X ──
    shaft_rings = []
    for i in range(3):
        x = -BONE_HALF + BONE_HALF * i   # -0.70, 0.0, +0.70
        ring = []
        for si in range(SEGS):
            a = 2 * math.pi * si / SEGS
            ring.append(bm.verts.new((x, math.cos(a) * SHAFT_R, math.sin(a) * SHAFT_R)))
        shaft_rings.append(ring)

    for ri in range(2):
        curr, nxt = shaft_rings[ri], shaft_rings[ri + 1]
        for si in range(SEGS):
            ni = (si + 1) % SEGS
            bm.faces.new([curr[si], curr[ni], nxt[ni], nxt[si]])

    # ── Bola ujung (knob) — low-poly sphere ──
    def add_knob(cx, r_yz, r_x, segs=8, rings=5):
        """Bola semi-gepeng: r_x di sumbu X, r_yz di sumbu YZ."""
        bv = []
        # Top pole (+X arah)
        bv.append([bm.verts.new((cx + r_x, 0, 0))])
        for ri in range(1, rings):
            phi = math.pi * ri / rings
            rx  = cx + r_x * math.cos(phi)
            ryz = r_yz * math.sin(phi)
            row = []
            for si in range(segs):
                t = 2 * math.pi * si / segs
                row.append(bm.verts.new((rx, ryz * math.cos(t), ryz * math.sin(t))))
            bv.append(row)
        # Bottom pole (-X arah)
        bv.append([bm.verts.new((cx - r_x, 0, 0))])

        # Fan top
        for si in range(segs):
            ni = (si + 1) % segs
            bm.faces.new([bv[0][0], bv[1][si], bv[1][ni]])
        # Bands
        for ri in range(1, rings - 1):
            curr, nxt = bv[ri], bv[ri + 1]
            for si in range(segs):
                ni = (si + 1) % segs
                bm.faces.new([curr[si], curr[ni], nxt[ni], nxt[si]])
        # Fan bottom
        prev = bv[-2]
        for si in range(segs):
            ni = (si + 1) % segs
            bm.faces.new([prev[ni], bv[-1][0], prev[si]])

    add_knob( BONE_HALF, KNOB_R, KNOB_R * KNOB_FLAT)   # ujung kanan
    add_knob(-BONE_HALF, KNOB_R, KNOB_R * KNOB_FLAT)   # ujung kiri

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = bm_to_object(bm, "Bone_Center")
    obj.data.materials.append(mat_bone)
    return obj


# ──────────────────────────────────────────────
# 5. ASSEMBLE & JOIN
# ──────────────────────────────────────────────
meat_obj = build_meat()
bone_obj = build_single_bone()

bpy.ops.object.select_all(action='DESELECT')
meat_obj.select_set(True)
bone_obj.select_set(True)
bpy.context.view_layer.objects.active = meat_obj
bpy.ops.object.join()

final           = bpy.context.active_object
final.name      = "Meat"
final.data.name = "Meat"

# ──────────────────────────────────────────────
# 6. ORIGIN → GEOMETRY CENTER  (Roblox pivot)
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
final.select_set(True)
bpy.context.view_layer.objects.active = final
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
final.location = (0, 0, 0)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ──────────────────────────────────────────────
# 7. SMOOTH SHADING  — AMAN untuk semua versi Blender 4.x/5.x
#    Tidak pakai SMOOTH_BY_ANGLE modifier (tidak tersedia di semua build)
#    Pakai EDGE_SPLIT modifier sebagai gantinya — selalu tersedia
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
final.select_set(True)
bpy.context.view_layer.objects.active = final
bpy.ops.object.shade_smooth()   # shade smooth dulu

# EDGE_SPLIT modifier — tersedia di semua versi Blender
mod = final.modifiers.new(name="EdgeSplit", type='EDGE_SPLIT')
mod.split_angle = math.radians(60)   # edge tajam di atas 60° tetap sharp
mod.use_edge_angle = True
mod.use_edge_sharp  = True

# ──────────────────────────────────────────────
# 8. EXPORT FBX  (Roblox settings)
# ──────────────────────────────────────────────
export_path = os.path.join(os.path.expanduser("~"), "Meat.fbx")

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

print(f"[Meat v3] Blender {bpy.app.version[0]}.{bpy.app.version[1]} — export OK")
print(f"[Meat v3] Exported → {export_path}")
print(f"[Meat v3] Tri count ≈ {sum(len(p.vertices) - 2 for p in final.data.polygons)}")

# Kok ga keikut isinya
