"""
Blender Python Script: Low-Poly Stylized Water Bottle
Game: Bababooeys Can (Not) Move
Compatible with Blender 4.x / 5.x
Run from: Scripting Tab > Run Script

Output: Exports 'WaterBottle.fbx' to ~/WaterBottle.fbx
Poly budget: < 1,500 triangles
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
# 1. MATERIALS  (Blender 4.x / 5.x safe)
# ──────────────────────────────────────────────
def set_input_safe(bsdf, possible_names, value):
    """Try each name until one exists — handles renamed inputs across versions."""
    for name in possible_names:
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = value
            return

def make_material(name, r, g, b, alpha=1.0, transmission=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value  = 0.15
        # Blender 3.x: "Specular"  →  Blender 4.x+: "Specular IOR Level"
        set_input_safe(bsdf, ["Specular IOR Level", "Specular"], 0.6)
        bsdf.inputs["Alpha"].default_value = alpha
        # Blender 3.x: "Transmission"  →  Blender 4.x+: "Transmission Weight"
        set_input_safe(bsdf, ["Transmission Weight", "Transmission"], transmission)
    if alpha < 1.0:
        mat.blend_method = 'BLEND'
    return mat

mat_body = make_material(
    "Mat_Bottle_Body",
    0.78, 0.90, 0.97,
    alpha=1.0,
    transmission=0.0
)
mat_cap   = make_material("Mat_Bottle_Cap",   0.96, 0.96, 0.96)
mat_label = make_material("Mat_Bottle_Label", 0.99, 0.99, 0.99)


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
# 3. BUILD WATER BOTTLE
# ──────────────────────────────────────────────
def build_bottle():
    """
    Lathe-style bottle built from a (height, radius) profile list.
    Ribbed grip = alternating tight/wide rings in the profile.
    10 radial segments keeps tri count very low.
    """
    SEGS = 16
    FULL_R = 0.155
    NECK_R = 0.048
    CAP_R  = 0.058

    # (z_height, radius) — radius 0 = single pole vertex
    profile = [
        (0.00, FULL_R * 0.60),   # base inset
        (0.02, FULL_R * 0.85),
        (0.06, FULL_R),
        # ── ribbed grip section ──
        (0.10, FULL_R),
        (0.13, FULL_R * 0.90),
        (0.16, FULL_R),
        (0.21, FULL_R * 0.90),
        (0.25, FULL_R),
        (0.30, FULL_R * 0.90),
        (0.34, FULL_R),
        (0.39, FULL_R * 0.90),
        (0.43, FULL_R),
        (0.48, FULL_R * 0.90),
        (0.52, FULL_R),
        (0.56, FULL_R * 0.96),
        (0.60, FULL_R * 0.93),
        (0.64, FULL_R * 0.96),
        (0.68, FULL_R * 0.70),
        (0.76, NECK_R * 1.4),
        (0.82, NECK_R),
        (0.90, NECK_R),
        # ── cap ──
        (0.92, CAP_R),
        (0.95, CAP_R),
        (1.00, CAP_R),
        (0.99, CAP_R * 0.92),
        (1.01, 0.0),   # top pole
    ]

    bm = bmesh.new()
    rings = []

    for (z, r) in profile:
        if r < 0.001:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            ring = []
            for si in range(SEGS):
                a = 2 * math.pi * si / SEGS
                ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            rings.append(ring)

    # Bottom fan (ring[0] single vert → ring[1])
    base_tip = rings[0][0]
    for si in range(SEGS):
        ni = (si + 1) % SEGS
        bm.faces.new([base_tip, rings[1][si], rings[1][ni]])

    # Lateral faces
    for li in range(1, len(rings) - 1):
        curr, nxt = rings[li], rings[li + 1]
        if len(curr) == SEGS and len(nxt) == SEGS:
            for si in range(SEGS):
                ni = (si + 1) % SEGS
                bm.faces.new([curr[si], curr[ni], nxt[ni], nxt[si]])
        elif len(curr) == SEGS and len(nxt) == 1:   # top pole fan
            pole = nxt[0]
            for si in range(SEGS):
                ni = (si + 1) % SEGS
                bm.faces.new([curr[si], curr[ni], pole])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = bm_to_object(bm, "WaterBottle")

    obj.data.materials.append(mat_body)    # slot 0
    obj.data.materials.append(mat_cap)     # slot 1
    obj.data.materials.append(mat_label)   # slot 2

    # Assign material per face by average Z
    for poly in obj.data.polygons:
        z_avg = sum(obj.data.vertices[vi].co.z for vi in poly.vertices) / len(poly.vertices)
        if z_avg > 0.90:
            poly.material_index = 1          # cap
        elif 0.26 < z_avg < 0.58:
            poly.material_index = 2        # label band
        else:
            poly.material_index = 0          # body

    return obj


# ──────────────────────────────────────────────
# 4. ASSEMBLE
# ──────────────────────────────────────────────
bottle           = build_bottle()
bottle.name      = "WaterBottle"
bottle.data.name = "WaterBottle"

# ──────────────────────────────────────────────
# 5. ORIGIN → BOUNDS CENTER
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
bottle.select_set(True)
bpy.context.view_layer.objects.active = bottle
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
bottle.location = (0, 0, 0)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)



# ──────────────────────────────────────────────
# 6. SMOOTH SHADING
# ──────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
bottle.select_set(True)
bpy.context.view_layer.objects.active = bottle

bpy.ops.object.shade_smooth()

#mod.split_angle = math.radians(45)
#mod.use_edge_angle = True
#mod.use_edge_sharp = True

#if hasattr(mod, 'angle'):
#    mod.angle = math.radians(45)
#else:
#    bottle.data.use_auto_smooth     = True
#    bottle.data.auto_smooth_angle   = math.radians(45)

# ──────────────────────────────────────────────
# 7. EXPORT FBX  (Roblox settings)
# ──────────────────────────────────────────────
export_path = os.path.join(os.path.expanduser("~"), "WaterBottle.fbx")

bpy.ops.object.select_all(action='DESELECT')
bottle.select_set(True)

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

#print(f"[WaterBottle] Blender {blender_ver[0]}.{blender_ver[1]} detected — export OK")
print(f"[WaterBottle] Exported → {export_path}")
print(f"[WaterBottle] Tri count ≈ {sum(len(p.vertices) - 2 for p in bottle.data.polygons)}")

# Kok ga keikut isinya
