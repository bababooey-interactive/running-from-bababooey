"""
=============================================================================
ROBLOX LABYRINTH ASSET PACK - Blender Python Script (bpy)
=============================================================================
Deskripsi:
    Script ini membuat modular asset pack bertema Cave/Stone Dungeon untuk
    map labirin Roblox Studio. Semua aset dibuat secara procedural menggunakan
    bpy tanpa addon eksternal.

Cara Pakai:
    1. Buka Blender (versi 3.0 atau lebih baru direkomendasikan)
    2. Buka Scripting workspace
    3. Paste atau load script ini
    4. Klik "Run Script"
    5. Tunggu hingga selesai (±30-60 detik tergantung PC)
    6. File .blend dan .fbx akan tersimpan di folder exports/ relatif terhadap
       lokasi Blender project Anda (atau path absolute yang ditentukan)

Aset yang dibuat:
    A. Modular Stone Wall Set (5 varian)
    B. Cave Ceiling Set (4 varian)
    C. Boulder Prop Set (4 varian)
    D. Old Fireplace Prop (lengkap)

Author  : Generated for Roblox Cave Dungeon Labyrinth
Version : 1.0
=============================================================================
"""

import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix

# =============================================================================
# KONFIGURASI GLOBAL
# =============================================================================

# Random seed agar hasil konsisten setiap run
random.seed(42)

# Path output - akan dibuat otomatis jika belum ada
# Ganti path ini sesuai kebutuhan Anda
#EXPORT_PATH = os.path.join(os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~"), "exports")
EXPORT_PATH = "D:/code vs/Komgraf/Tubes/running-from-bababooey/assets/models"
# Nama file output
BLEND_FILENAME = "roblox_labyrinth_asset_pack.blend"
FBX_FILENAME   = "roblox_labyrinth_asset_pack.fbx"

# Ukuran modul standar (dalam meter, 1 meter = 1 stud di Roblox)
TILE_SIZE = 4.0   # 4x4 meter per tile modul
WALL_H    = 3.0   # tinggi dinding standar
WALL_T    = 0.3   # ketebalan dinding

# Warna material (RGBA linear)
COL_STONE_GRAY   = (0.25, 0.24, 0.22, 1.0)   # abu-abu batu gelap
COL_STONE_LIGHT  = (0.45, 0.42, 0.38, 1.0)   # batu terang
COL_BROWN_EARTH  = (0.30, 0.22, 0.15, 1.0)   # coklat tanah
COL_MOSS_GREEN   = (0.18, 0.28, 0.12, 1.0)   # hijau lumut
COL_BRICK_RED    = (0.35, 0.18, 0.12, 1.0)   # bata merah tua
COL_WOOD_DARK    = (0.12, 0.08, 0.05, 1.0)   # kayu gelap
COL_EMBER_ORANGE = (0.8,  0.3,  0.0,  1.0)   # bara api
COL_FIRE_YELLOW  = (1.0,  0.6,  0.0,  1.0)   # api


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def clear_scene():
    """Hapus semua objek, mesh, material, dan koleksi default di scene."""
    # Hapus semua objek
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    # Hapus semua mesh yang tidak terpakai
    for mesh in bpy.data.meshes:
        bpy.data.meshes.remove(mesh)
    
    # Hapus semua material yang tidak terpakai
    for mat in bpy.data.materials:
        bpy.data.materials.remove(mat)
    
    # Hapus semua koleksi selain Scene Collection
    for col in bpy.data.collections:
        bpy.data.collections.remove(col)
    
    print("[CLEAR] Scene berhasil dibersihkan.")


def create_collection(name, parent=None):
    """Buat koleksi baru dan tambahkan ke parent (default: Scene Collection)."""
    col = bpy.data.collections.new(name)
    if parent is None:
        bpy.context.scene.collection.children.link(col)
    else:
        parent.children.link(col)
    return col


def link_to_collection(obj, collection):
    """Pindahkan objek ke koleksi tertentu."""
    # Hapus dari semua koleksi yang ada
    for col in obj.users_collection:
        col.objects.unlink(obj)
    # Tambahkan ke koleksi target
    collection.objects.link(obj)


def apply_transforms(obj):
    """Apply semua transform (location, rotation, scale) pada objek."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def set_origin_to_bottom_center(obj):
    """Set origin objek ke titik tengah bawah (bottom center)."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    
    # Hitung bounding box
    local_coords = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    min_z = min(v.z for v in local_coords)
    
    # Pindah cursor ke bottom center
    cx = (max(v.x for v in local_coords) + min(v.x for v in local_coords)) / 2
    cy = (max(v.y for v in local_coords) + min(v.y for v in local_coords)) / 2
    
    bpy.context.scene.cursor.location = (cx, cy, min_z)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    
    obj.select_set(False)


def add_noise_displacement(obj, strength=0.05, scale=3.0):
    """
    Tambahkan Displace modifier dengan texture noise untuk membuat
    permukaan terlihat tidak rata / natural.
    """
    # Buat texture noise
    tex = bpy.data.textures.new(name=f"Noise_{obj.name}", type='CLOUDS')
    tex.noise_scale = scale
    tex.noise_depth = 4
    
    # Tambahkan modifier Displace
    mod = obj.modifiers.new(name="Displace_Noise", type='DISPLACE')
    mod.texture = tex
    mod.strength = strength
    mod.texture_coords = 'LOCAL'
    
    # Apply modifier
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Displace_Noise")
    obj.select_set(False)
    
    # Hapus texture yang sudah tidak dipakai
    bpy.data.textures.remove(tex)


def subdivide_mesh(obj, cuts=2):
    """Subdivide mesh untuk mendapatkan lebih banyak vertex (persiapan noise)."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.subdivide(number_cuts=cuts)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def shade_smooth_obj(obj):
    """Set semua face menjadi smooth shading."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)


def recalc_normals(obj):
    """Recalculate normals ke luar."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def safe_face_new(bm, verts):
    """
    Membuat face bmesh dengan aman.
    Jika face yang sama sudah ada, Blender akan melewatinya
    supaya script tidak berhenti dengan error:
    ValueError: faces.new(...): face already exists
    """
    try:
        return bm.faces.new(verts)
    except ValueError:
        return None


# =============================================================================
# MATERIAL FUNCTIONS
# =============================================================================

def create_stone_material(name, base_color, roughness_val=0.85, use_noise=True):
    """
    Buat material batu procedural menggunakan Shader Nodes.
    Menggunakan Noise Texture untuk variasi warna dan roughness.
    
    Parameters:
        name        : nama material
        base_color  : warna dasar (RGBA tuple)
        roughness_val: nilai roughness dasar (0-1)
        use_noise   : aktifkan noise variasi warna
    """
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    
    # Bersihkan node default
    nodes.clear()
    
    # --- Node: Output ---
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)
    
    # --- Node: Principled BSDF ---
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    bsdf.inputs['Roughness'].default_value = roughness_val
    bsdf.inputs['Specular IOR Level'].default_value = 0.1  # Batu tidak mengkilap
    
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    if use_noise:
        # --- Node: Texture Coordinate ---
        tex_coord = nodes.new('ShaderNodeTexCoord')
        tex_coord.location = (-600, 0)
        
        # --- Node: Mapping (scale noise) ---
        mapping = nodes.new('ShaderNodeMapping')
        mapping.location = (-400, 0)
        mapping.inputs['Scale'].default_value = (2.5, 2.5, 2.5)
        links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])
        
        # --- Node: Noise Texture (variasi warna) ---
        noise1 = nodes.new('ShaderNodeTexNoise')
        noise1.location = (-200, 100)
        noise1.inputs['Scale'].default_value = 5.0
        noise1.inputs['Detail'].default_value = 8.0
        noise1.inputs['Roughness'].default_value = 0.7
        noise1.inputs['Distortion'].default_value = 0.3
        links.new(mapping.outputs['Vector'], noise1.inputs['Vector'])
        
        # --- Node: Noise Texture (roughness variation) ---
        noise2 = nodes.new('ShaderNodeTexNoise')
        noise2.location = (-200, -150)
        noise2.inputs['Scale'].default_value = 8.0
        noise2.inputs['Detail'].default_value = 4.0
        links.new(mapping.outputs['Vector'], noise2.inputs['Vector'])
        
        # --- Node: ColorRamp (map noise ke variasi warna batu) ---
        ramp_color = nodes.new('ShaderNodeValToRGB')
        ramp_color.location = (0, 100)
        # Sesuaikan stop warna berdasarkan base_color
        r, g, b, a = base_color
        ramp_color.color_ramp.elements[0].color = (r * 0.7, g * 0.7, b * 0.7, 1.0)  # lebih gelap
        ramp_color.color_ramp.elements[1].color = (min(r * 1.3, 1.0), min(g * 1.3, 1.0), min(b * 1.3, 1.0), 1.0)  # lebih terang
        links.new(noise1.outputs['Fac'], ramp_color.inputs['Fac'])
        
        # --- Node: ColorRamp (roughness) ---
        ramp_rough = nodes.new('ShaderNodeValToRGB')
        ramp_rough.location = (0, -150)
        ramp_rough.color_ramp.elements[0].color = (roughness_val * 0.8,) * 4
        ramp_rough.color_ramp.elements[1].color = (min(roughness_val * 1.1, 1.0),) * 4
        links.new(noise2.outputs['Fac'], ramp_rough.inputs['Fac'])
        
        # Hubungkan warna dan roughness ke BSDF
        links.new(ramp_color.outputs['Color'],  bsdf.inputs['Base Color'])
        links.new(ramp_rough.outputs['Color'],  bsdf.inputs['Roughness'])
        
        # --- Node: Lumut (sedikit hijau di beberapa area) ---
        noise_moss = nodes.new('ShaderNodeTexNoise')
        noise_moss.location = (-200, 300)
        noise_moss.inputs['Scale'].default_value = 3.0
        noise_moss.inputs['Detail'].default_value = 2.0
        links.new(mapping.outputs['Vector'], noise_moss.inputs['Vector'])
        
        ramp_moss = nodes.new('ShaderNodeValToRGB')
        ramp_moss.location = (0, 300)
        ramp_moss.color_ramp.elements[0].color = (0, 0, 0, 1)
        ramp_moss.color_ramp.elements[1].color = (*COL_MOSS_GREEN[:3], 1)
        ramp_moss.color_ramp.elements[0].position = 0.7  # lumut hanya sedikit
        links.new(noise_moss.outputs['Fac'], ramp_moss.inputs['Fac'])
        
        # Mix warna batu + lumut
        mix_node = nodes.new('ShaderNodeMixRGB')
        mix_node.location = (150, 200)
        mix_node.blend_type = 'OVERLAY'
        mix_node.inputs['Fac'].default_value = 0.15  # 15% pengaruh lumut
        links.new(ramp_color.outputs['Color'], mix_node.inputs['Color1'])
        links.new(ramp_moss.outputs['Color'],  mix_node.inputs['Color2'])
        links.new(mix_node.outputs['Color'],   bsdf.inputs['Base Color'])
        
    else:
        # Material sederhana tanpa noise
        bsdf.inputs['Base Color'].default_value = base_color
    
    return mat


def create_brick_material(name):
    """Buat material batu bata tua procedural."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (700, 0)
    
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (400, 0)
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Specular IOR Level'].default_value = 0.05
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-700, 0)
    
    mapping = nodes.new('ShaderNodeMapping')
    mapping.location = (-500, 0)
    mapping.inputs['Scale'].default_value = (3.0, 3.0, 3.0)
    links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])
    
    # Noise untuk variasi warna bata
    noise = nodes.new('ShaderNodeTexNoise')
    noise.location = (-300, 100)
    noise.inputs['Scale'].default_value = 4.0
    noise.inputs['Detail'].default_value = 6.0
    noise.inputs['Roughness'].default_value = 0.6
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.location = (-100, 100)
    ramp.color_ramp.elements[0].color = (0.28, 0.12, 0.08, 1)   # bata gelap
    ramp.color_ramp.elements[1].color = (0.45, 0.22, 0.14, 1)   # bata terang
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    
    return mat


def create_wood_material(name):
    """Buat material kayu gelap procedural."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)
    
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    bsdf.inputs['Roughness'].default_value = 0.8
    bsdf.inputs['Specular IOR Level'].default_value = 0.15
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-500, 0)
    
    mapping = nodes.new('ShaderNodeMapping')
    mapping.location = (-300, 0)
    mapping.inputs['Scale'].default_value = (5.0, 1.0, 1.0)  # serat kayu
    links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])
    
    noise = nodes.new('ShaderNodeTexNoise')
    noise.location = (-100, 0)
    noise.inputs['Scale'].default_value = 10.0
    noise.inputs['Detail'].default_value = 4.0
    noise.inputs['Roughness'].default_value = 0.5
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.location = (100, 0)
    ramp.color_ramp.elements[0].color = (0.08, 0.05, 0.02, 1)  # kayu sangat gelap
    ramp.color_ramp.elements[1].color = (0.18, 0.11, 0.06, 1)  # kayu gelap
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    
    return mat


def create_ember_material(name):
    """Buat material ember/bara api dengan emission."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (500, 0)
    
    emission = nodes.new('ShaderNodeEmission')
    emission.location = (200, 0)
    emission.inputs['Color'].default_value = (*COL_FIRE_YELLOW[:3], 1.0)
    emission.inputs['Strength'].default_value = 3.0
    
    links.new(emission.outputs['Emission'], output.inputs['Surface'])
    
    return mat


# =============================================================================
# A. MODULAR STONE WALL SET
# =============================================================================

def create_wall_straight(col, mat_stone):
    """
    Dinding lurus 4x3m dengan efek batu slate bertumpuk horizontal.
    Ini adalah unit modul dasar untuk labirin.
    """
    print("[WALL] Membuat Wall_Straight...")
    
    bm = bmesh.new()
    
    # Buat slab-slab batu bertumpuk (stacked slate layers)
    layer_count = 8
    layer_height = WALL_H / layer_count
    
    for i in range(layer_count):
        z_bot = i * layer_height
        z_top = z_bot + layer_height * 0.92  # sedikit gap antar layer
        
        # Variasi posisi x (membuat batu tidak rata sempurna)
        x_offset = random.uniform(-0.02, 0.02)
        y_offset_front = random.uniform(-0.01, 0.01)
        y_offset_back  = random.uniform(-0.01, 0.01)
        
        # Buat kotak satu layer
        verts = [
            bm.verts.new((-TILE_SIZE/2 + x_offset, -WALL_T/2 + y_offset_front, z_bot)),
            bm.verts.new(( TILE_SIZE/2 + x_offset, -WALL_T/2 + y_offset_front, z_bot)),
            bm.verts.new(( TILE_SIZE/2 + x_offset,  WALL_T/2 + y_offset_back,  z_bot)),
            bm.verts.new((-TILE_SIZE/2 + x_offset,  WALL_T/2 + y_offset_back,  z_bot)),
            bm.verts.new((-TILE_SIZE/2 + x_offset, -WALL_T/2 + y_offset_front, z_top)),
            bm.verts.new(( TILE_SIZE/2 + x_offset, -WALL_T/2 + y_offset_front, z_top)),
            bm.verts.new(( TILE_SIZE/2 + x_offset,  WALL_T/2 + y_offset_back,  z_top)),
            bm.verts.new((-TILE_SIZE/2 + x_offset,  WALL_T/2 + y_offset_back,  z_top)),
        ]
        
        # Buat faces
        safe_face_new(bm, [verts[0], verts[1], verts[5], verts[4]])  # depan
        safe_face_new(bm, [verts[2], verts[3], verts[7], verts[6]])  # belakang
        safe_face_new(bm, [verts[1], verts[2], verts[6], verts[5]])  # kanan
        safe_face_new(bm, [verts[3], verts[0], verts[4], verts[7]])  # kiri
        safe_face_new(bm, [verts[4], verts[5], verts[6], verts[7]])  # atas
        safe_face_new(bm, [verts[3], verts[2], verts[1], verts[0]])  # bawah
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Wall_Straight_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Wall_Straight", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat_stone)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    
    link_to_collection(obj, col)
    print("[WALL] Wall_Straight selesai.")
    return obj


def create_wall_corner(col, mat_stone):
    """
    Dinding sudut 90 derajat. Menggabungkan dua dinding lurus
    membentuk sudut L untuk tikungan labirin.
    """
    print("[WALL] Membuat Wall_Corner_90...")
    
    bm = bmesh.new()
    layer_count = 8
    layer_height = WALL_H / layer_count
    
    for i in range(layer_count):
        z_bot = i * layer_height
        z_top = z_bot + layer_height * 0.92
        
        # Segmen pertama (arah X)
        x_off = random.uniform(-0.02, 0.02)
        y_off = random.uniform(-0.01, 0.01)
        
        # Dinding arah X
        verts_x = [
            bm.verts.new((0,             -WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/2,  -WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/2,   WALL_T/2 + y_off, z_bot)),
            bm.verts.new((0,              WALL_T/2 + y_off, z_bot)),
            bm.verts.new((0,             -WALL_T/2 + y_off, z_top)),
            bm.verts.new((-TILE_SIZE/2,  -WALL_T/2 + y_off, z_top)),
            bm.verts.new((-TILE_SIZE/2,   WALL_T/2 + y_off, z_top)),
            bm.verts.new((0,              WALL_T/2 + y_off, z_top)),
        ]
        safe_face_new(bm, [verts_x[0], verts_x[1], verts_x[5], verts_x[4]])
        safe_face_new(bm, [verts_x[2], verts_x[3], verts_x[7], verts_x[6]])
        safe_face_new(bm, [verts_x[1], verts_x[2], verts_x[6], verts_x[5]])
        safe_face_new(bm, [verts_x[3], verts_x[0], verts_x[4], verts_x[7]])
        safe_face_new(bm, [verts_x[4], verts_x[5], verts_x[6], verts_x[7]])
        safe_face_new(bm, [verts_x[3], verts_x[2], verts_x[1], verts_x[0]])
        
        # Dinding arah Y (dengan offset agar tidak overlap di sudut)
        verts_y = [
            bm.verts.new((-WALL_T/2 + x_off, 0,             z_bot)),
            bm.verts.new((-WALL_T/2 + x_off, -TILE_SIZE/2,  z_bot)),
            bm.verts.new(( WALL_T/2 + x_off, -TILE_SIZE/2,  z_bot)),
            bm.verts.new(( WALL_T/2 + x_off, 0,             z_bot)),
            bm.verts.new((-WALL_T/2 + x_off, 0,             z_top)),
            bm.verts.new((-WALL_T/2 + x_off, -TILE_SIZE/2,  z_top)),
            bm.verts.new(( WALL_T/2 + x_off, -TILE_SIZE/2,  z_top)),
            bm.verts.new(( WALL_T/2 + x_off, 0,             z_top)),
        ]
        safe_face_new(bm, [verts_y[0], verts_y[1], verts_y[5], verts_y[4]])
        safe_face_new(bm, [verts_y[2], verts_y[3], verts_y[7], verts_y[6]])
        safe_face_new(bm, [verts_y[1], verts_y[2], verts_y[6], verts_y[5]])
        safe_face_new(bm, [verts_y[3], verts_y[0], verts_y[4], verts_y[7]])
        safe_face_new(bm, [verts_y[4], verts_y[5], verts_y[6], verts_y[7]])
        safe_face_new(bm, [verts_y[3], verts_y[2], verts_y[1], verts_y[0]])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Wall_Corner_90_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Wall_Corner_90", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat_stone)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    
    link_to_collection(obj, col)
    print("[WALL] Wall_Corner_90 selesai.")
    return obj


def create_wall_end_cap(col, mat_stone):
    """
    Dinding end cap - penutup ujung dinding.
    Berbentuk U untuk menutup ujung koridor labirin.
    """
    print("[WALL] Membuat Wall_End_Cap...")
    
    bm = bmesh.new()
    layer_count = 8
    layer_height = WALL_H / layer_count
    
    for i in range(layer_count):
        z_bot = i * layer_height
        z_top = z_bot + layer_height * 0.92
        y_off = random.uniform(-0.01, 0.01)
        
        # Dinding depan pendek
        v = [
            bm.verts.new((-TILE_SIZE/4, -WALL_T/2 + y_off, z_bot)),
            bm.verts.new(( TILE_SIZE/4, -WALL_T/2 + y_off, z_bot)),
            bm.verts.new(( TILE_SIZE/4,  WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/4,  WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/4, -WALL_T/2 + y_off, z_top)),
            bm.verts.new(( TILE_SIZE/4, -WALL_T/2 + y_off, z_top)),
            bm.verts.new(( TILE_SIZE/4,  WALL_T/2 + y_off, z_top)),
            bm.verts.new((-TILE_SIZE/4,  WALL_T/2 + y_off, z_top)),
        ]
        safe_face_new(bm, [v[0], v[1], v[5], v[4]])
        safe_face_new(bm, [v[2], v[3], v[7], v[6]])
        safe_face_new(bm, [v[1], v[2], v[6], v[5]])
        safe_face_new(bm, [v[3], v[0], v[4], v[7]])
        safe_face_new(bm, [v[4], v[5], v[6], v[7]])
        safe_face_new(bm, [v[3], v[2], v[1], v[0]])
        
        # Sayap kiri
        x_off = random.uniform(-0.01, 0.01)
        vl = [
            bm.verts.new((-TILE_SIZE/4 - WALL_T + x_off, -TILE_SIZE/4, z_bot)),
            bm.verts.new((-TILE_SIZE/4         + x_off, -TILE_SIZE/4, z_bot)),
            bm.verts.new((-TILE_SIZE/4         + x_off,  WALL_T/2,    z_bot)),
            bm.verts.new((-TILE_SIZE/4 - WALL_T + x_off,  WALL_T/2,   z_bot)),
            bm.verts.new((-TILE_SIZE/4 - WALL_T + x_off, -TILE_SIZE/4, z_top)),
            bm.verts.new((-TILE_SIZE/4         + x_off, -TILE_SIZE/4, z_top)),
            bm.verts.new((-TILE_SIZE/4         + x_off,  WALL_T/2,    z_top)),
            bm.verts.new((-TILE_SIZE/4 - WALL_T + x_off,  WALL_T/2,   z_top)),
        ]
        safe_face_new(bm, [vl[0], vl[1], vl[5], vl[4]])
        safe_face_new(bm, [vl[2], vl[3], vl[7], vl[6]])
        safe_face_new(bm, [vl[1], vl[2], vl[6], vl[5]])
        safe_face_new(bm, [vl[3], vl[0], vl[4], vl[7]])
        safe_face_new(bm, [vl[4], vl[5], vl[6], vl[7]])
        safe_face_new(bm, [vl[3], vl[2], vl[1], vl[0]])
        
        # Sayap kanan
        vr = [
            bm.verts.new(( TILE_SIZE/4         + x_off, -TILE_SIZE/4, z_bot)),
            bm.verts.new(( TILE_SIZE/4 + WALL_T + x_off, -TILE_SIZE/4, z_bot)),
            bm.verts.new(( TILE_SIZE/4 + WALL_T + x_off,  WALL_T/2,   z_bot)),
            bm.verts.new(( TILE_SIZE/4         + x_off,  WALL_T/2,    z_bot)),
            bm.verts.new(( TILE_SIZE/4         + x_off, -TILE_SIZE/4, z_top)),
            bm.verts.new(( TILE_SIZE/4 + WALL_T + x_off, -TILE_SIZE/4, z_top)),
            bm.verts.new(( TILE_SIZE/4 + WALL_T + x_off,  WALL_T/2,   z_top)),
            bm.verts.new(( TILE_SIZE/4         + x_off,  WALL_T/2,    z_top)),
        ]
        safe_face_new(bm, [vr[0], vr[1], vr[5], vr[4]])
        safe_face_new(bm, [vr[2], vr[3], vr[7], vr[6]])
        safe_face_new(bm, [vr[1], vr[2], vr[6], vr[5]])
        safe_face_new(bm, [vr[3], vr[0], vr[4], vr[7]])
        safe_face_new(bm, [vr[4], vr[5], vr[6], vr[7]])
        safe_face_new(bm, [vr[3], vr[2], vr[1], vr[0]])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Wall_End_Cap_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Wall_End_Cap", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat_stone)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    
    link_to_collection(obj, col)
    print("[WALL] Wall_End_Cap selesai.")
    return obj


def create_wall_short(col, mat_stone):
    """
    Dinding pendek (setengah tinggi). Digunakan sebagai pagar,
    pembatas rendah, atau variasi tinggi koridor.
    """
    print("[WALL] Membuat Wall_Short...")
    
    short_height = WALL_H * 0.5
    bm = bmesh.new()
    layer_count = 4
    layer_height = short_height / layer_count
    
    for i in range(layer_count):
        z_bot = i * layer_height
        z_top = z_bot + layer_height * 0.90
        x_off = random.uniform(-0.025, 0.025)
        y_off = random.uniform(-0.015, 0.015)
        
        v = [
            bm.verts.new((-TILE_SIZE/2 + x_off, -WALL_T/2 + y_off, z_bot)),
            bm.verts.new(( TILE_SIZE/2 + x_off, -WALL_T/2 + y_off, z_bot)),
            bm.verts.new(( TILE_SIZE/2 + x_off,  WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/2 + x_off,  WALL_T/2 + y_off, z_bot)),
            bm.verts.new((-TILE_SIZE/2 + x_off, -WALL_T/2 + y_off, z_top)),
            bm.verts.new(( TILE_SIZE/2 + x_off, -WALL_T/2 + y_off, z_top)),
            bm.verts.new(( TILE_SIZE/2 + x_off,  WALL_T/2 + y_off, z_top)),
            bm.verts.new((-TILE_SIZE/2 + x_off,  WALL_T/2 + y_off, z_top)),
        ]
        safe_face_new(bm, [v[0], v[1], v[5], v[4]])
        safe_face_new(bm, [v[2], v[3], v[7], v[6]])
        safe_face_new(bm, [v[1], v[2], v[6], v[5]])
        safe_face_new(bm, [v[3], v[0], v[4], v[7]])
        safe_face_new(bm, [v[4], v[5], v[6], v[7]])
        safe_face_new(bm, [v[3], v[2], v[1], v[0]])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Wall_Short_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Wall_Short", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat_stone)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    
    link_to_collection(obj, col)
    print("[WALL] Wall_Short selesai.")
    return obj


def create_wall_pillar(col, mat_stone):
    """
    Pilar batu berbentuk persegi. Bisa dipakai di persimpangan
    atau sebagai dekorasi sudut ruangan.
    """
    print("[WALL] Membuat Wall_Pillar...")
    
    pw = 0.5   # lebar pilar
    bm = bmesh.new()
    layer_count = 10
    layer_height = WALL_H / layer_count
    
    for i in range(layer_count):
        z_bot = i * layer_height
        z_top = z_bot + layer_height * 0.94
        xoff = random.uniform(-0.015, 0.015)
        yoff = random.uniform(-0.015, 0.015)
        
        v = [
            bm.verts.new((-pw/2 + xoff, -pw/2 + yoff, z_bot)),
            bm.verts.new(( pw/2 + xoff, -pw/2 + yoff, z_bot)),
            bm.verts.new(( pw/2 + xoff,  pw/2 + yoff, z_bot)),
            bm.verts.new((-pw/2 + xoff,  pw/2 + yoff, z_bot)),
            bm.verts.new((-pw/2 + xoff, -pw/2 + yoff, z_top)),
            bm.verts.new(( pw/2 + xoff, -pw/2 + yoff, z_top)),
            bm.verts.new(( pw/2 + xoff,  pw/2 + yoff, z_top)),
            bm.verts.new((-pw/2 + xoff,  pw/2 + yoff, z_top)),
        ]
        for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
            safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Wall_Pillar_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Wall_Pillar", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat_stone)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    
    link_to_collection(obj, col)
    print("[WALL] Wall_Pillar selesai.")
    return obj


# =============================================================================
# B. CAVE CEILING SET
# =============================================================================

def create_ceiling_flat(col, mat_cave):
    """
    Ceiling datar kasar. Panel 4x4m yang dipasang di atas dinding.
    Disubdivide dan diberi noise agar terlihat seperti batu gua alami.
    """
    print("[CEIL] Membuat Ceiling_Flat...")
    
    bpy.ops.mesh.primitive_plane_add(size=TILE_SIZE, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = "Ceiling_Flat"
    obj.data.name = "Ceiling_Flat_Mesh"
    
    # Tebalkan ceiling
    solidify = obj.modifiers.new(name="Solidify", type='SOLIDIFY')
    solidify.thickness = 0.4
    solidify.offset = -1.0
    bpy.ops.object.modifier_apply(modifier="Solidify")
    
    # Subdivide untuk noise
    subdivide_mesh(obj, cuts=4)
    
    # Tambahkan noise untuk permukaan kasar
    add_noise_displacement(obj, strength=0.12, scale=2.5)
    
    # Flip ke bawah (ceiling menghadap ke bawah)
    obj.rotation_euler.x = math.radians(180)
    bpy.ops.object.transform_apply(rotation=True)
    
    obj.data.materials.append(mat_cave)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    
    link_to_collection(obj, col)
    print("[CEIL] Ceiling_Flat selesai.")
    return obj


def create_ceiling_arch(col, mat_cave):
    """
    Ceiling lengkung gua. Menggunakan curve/arch shape dengan
    cross-section yang disubdivide untuk tampilan gua natural.
    """
    print("[CEIL] Membuat Ceiling_Arch...")
    
    bm = bmesh.new()
    
    # Buat lengkung arch menggunakan loop vertex
    segments = 16     # resolusi lengkung
    depth     = TILE_SIZE  # kedalaman (arah Y)
    width     = TILE_SIZE  # lebar
    arch_h    = 1.2        # tinggi arch dari ujung ke puncak
    
    # Generate titik-titik arch (setengah lingkaran pipih)
    arch_verts_bot = []
    arch_verts_top = []
    
    for seg in range(segments + 1):
        t = seg / segments
        angle = math.pi * t
        x = -width/2 + t * width
        # Bentuk arch (parabola agar lebih natural dari lingkaran)
        y_arch = arch_h * math.sin(math.pi * t)
        
        arch_verts_bot.append((x, -depth/2, y_arch))
        arch_verts_top.append((x,  depth/2, y_arch))
    
    # Tambah ketebalan arch
    thick = 0.35
    arch_verts_bot_thick = []
    arch_verts_top_thick = []
    for x, y, z in arch_verts_bot:
        arch_verts_bot_thick.append((x, y, z + thick))
    for x, y, z in arch_verts_top:
        arch_verts_top_thick.append((x, y, z + thick))
    
    # Buat vertex bmesh
    def add_ring(coords):
        return [bm.verts.new(c) for c in coords]
    
    vbb = add_ring(arch_verts_bot)
    vtb = add_ring(arch_verts_top)
    vbt = add_ring(arch_verts_bot_thick)
    vtt = add_ring(arch_verts_top_thick)
    
    # Buat faces (quads sepanjang arch)
    for i in range(segments):

        # Muka depan arch
        try:
            safe_face_new(bm, [vbb[i], vbb[i+1], vtb[i+1], vtb[i]])
        except ValueError:
            pass

        # Sisi bawah / inner
        try:
            safe_face_new(bm, [vbt[i], vtt[i], vtt[i+1], vbt[i+1]])
        except ValueError:
            pass

        # Sisi kiri / samping
        try:
            safe_face_new(bm, [vbb[i], vbt[i], vtt[i], vtb[i]])
        except ValueError:
            pass

        # Sisi kanan / samping
        try:
            safe_face_new(bm, [vbb[i+1], vtb[i+1], vtt[i+1], vbt[i+1]])
        except ValueError:
            pass
    
    # Tutup ujung-ujung arch
    safe_face_new(bm, vbb + [vbt[i] for i in range(len(vbt))][::-1])
    safe_face_new(bm, vtb + [vtt[i] for i in range(len(vtt))][::-1])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Ceiling_Arch_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Ceiling_Arch", mesh)
    bpy.context.scene.collection.objects.link(obj)
    
    # Subdivide + noise untuk tekstur gua
    subdivide_mesh(obj, cuts=2)
    add_noise_displacement(obj, strength=0.08, scale=3.0)
    
    obj.data.materials.append(mat_cave)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    
    link_to_collection(obj, col)
    print("[CEIL] Ceiling_Arch selesai.")
    return obj


def create_ceiling_stalactite(col, mat_cave):
    """
    Ceiling dengan stalactite kecil menggantung.
    Setiap stalactite dibuat sebagai cone dengan variasi posisi/ukuran.
    """
    print("[CEIL] Membuat Ceiling_Stalactite...")
    
    # Buat parent empty untuk stalactite group
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    parent = bpy.context.active_object
    parent.name = "Ceiling_Stalactite_Group"
    
    # Base ceiling datar
    bpy.ops.mesh.primitive_plane_add(size=TILE_SIZE, location=(0, 0, 0))
    base = bpy.context.active_object
    base.name = "Ceiling_Stalactite_Base"
    base.data.name = "Ceiling_Stalactite_Base_Mesh"
    
    solidify = base.modifiers.new(name="Solidify", type='SOLIDIFY')
    solidify.thickness = 0.3
    solidify.offset = -1.0
    bpy.ops.object.modifier_apply(modifier="Solidify")
    
    subdivide_mesh(base, cuts=3)
    add_noise_displacement(base, strength=0.1, scale=2.0)
    
    base.rotation_euler.x = math.radians(180)
    bpy.ops.object.transform_apply(rotation=True)
    base.data.materials.append(mat_cave)
    base.parent = parent
    
    # Buat stalactite (8-12 buah dengan variasi)
    stala_count = random.randint(8, 12)
    for idx in range(stala_count):
        sx = random.uniform(-TILE_SIZE/2 * 0.8, TILE_SIZE/2 * 0.8)
        sy = random.uniform(-TILE_SIZE/2 * 0.8, TILE_SIZE/2 * 0.8)
        s_height = random.uniform(0.2, 0.7)
        s_radius = random.uniform(0.04, 0.12)
        s_segs   = random.randint(5, 8)
        
        bpy.ops.mesh.primitive_cone_add(
            vertices=s_segs,
            radius1=s_radius,
            radius2=0.01,
            depth=s_height,
            location=(sx, sy, -s_height/2)
        )
        stala = bpy.context.active_object
        stala.name = f"Stalactite_{idx:02d}"
        stala.data.name = f"Stalactite_{idx:02d}_Mesh"
        stala.data.materials.append(mat_cave)
        stala.parent = parent
    
    # Jadikan parent sebagai objek utama yang dikembalikan
    link_to_collection(parent, col)
    for child in parent.children:
        link_to_collection(child, col)
    
    set_origin_to_bottom_center(parent)
    apply_transforms(parent)
    
    print("[CEIL] Ceiling_Stalactite selesai.")
    return parent


def create_ceiling_crack(col, mat_cave):
    """
    Ceiling dengan celah/retakan dan cahaya dari atas.
    Dibuat dari beberapa panel dengan gap di tengah.
    """
    print("[CEIL] Membuat Ceiling_Crack...")
    
    bm = bmesh.new()
    
    # Panel kiri (dengan celah di tengah)
    crack_w = 0.15   # lebar celah
    panel_w = TILE_SIZE/2 - crack_w/2
    
    # Panel kiri
    for panel_x_start, panel_x_end in [
        (-TILE_SIZE/2, -crack_w/2),
        (crack_w/2, TILE_SIZE/2)
    ]:
        # Panel dengan ketebalan dan sedikit miring untuk celah natural
        slope = random.uniform(-0.1, 0.1)
        v = [
            bm.verts.new((panel_x_start, -TILE_SIZE/2, slope)),
            bm.verts.new((panel_x_end,   -TILE_SIZE/2, 0.0)),
            bm.verts.new((panel_x_end,    TILE_SIZE/2, 0.0)),
            bm.verts.new((panel_x_start,  TILE_SIZE/2, slope)),
            bm.verts.new((panel_x_start, -TILE_SIZE/2, slope + 0.35)),
            bm.verts.new((panel_x_end,   -TILE_SIZE/2, 0.35)),
            bm.verts.new((panel_x_end,    TILE_SIZE/2, 0.35)),
            bm.verts.new((panel_x_start,  TILE_SIZE/2, slope + 0.35)),
        ]
        for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
            safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh = bpy.data.meshes.new("Ceiling_Crack_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Ceiling_Crack", mesh)
    bpy.context.scene.collection.objects.link(obj)
    
    subdivide_mesh(obj, cuts=2)
    add_noise_displacement(obj, strength=0.06, scale=3.0)
    
    # Flip
    obj.rotation_euler.x = math.radians(180)
    bpy.ops.object.transform_apply(rotation=True)
    
    obj.data.materials.append(mat_cave)
    
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    
    link_to_collection(obj, col)
    print("[CEIL] Ceiling_Crack selesai.")
    return obj


# =============================================================================
# C. BOULDER PROP SET
# =============================================================================

def create_boulder_from_ico(name, size, subdivisions=2, noise_str=0.18):
    """
    Helper: Buat boulder dari icosphere yang dimodifikasi.
    Icosphere memberikan bentuk bola yang kemudian dibuat tidak beraturan
    dengan displacement noise.
    
    Parameters:
        name        : nama objek
        size        : radius dasar boulder
        subdivisions: resolusi icosphere (lebih tinggi = lebih detail)
        noise_str   : kekuatan displacement noise
    """
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=size,
        location=(0, 0, 0)
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    
    # Scale non-uniform agar terlihat natural (bukan bola sempurna)
    obj.scale = (
        random.uniform(0.7, 1.3),
        random.uniform(0.6, 1.1),
        random.uniform(0.5, 0.9)
    )
    bpy.ops.object.transform_apply(scale=True)
    
    # Subdivide lebih lanjut untuk detail noise
    subdivide_mesh(obj, cuts=1)
    
    # Noise displacement untuk permukaan kasar dan retak
    add_noise_displacement(obj, strength=noise_str, scale=random.uniform(1.5, 3.0))
    
    # Geser sedikit ke atas agar tidak menghilang ke bawah ground
    obj.location.z = size * 0.3
    bpy.ops.object.transform_apply(location=False)
    
    return obj


def create_boulder_large(col, mat_stone):
    """Boulder besar - obstacle atau dekorasi dinding gua."""
    print("[BOULDER] Membuat Boulder_Large...")
    obj = create_boulder_from_ico("Boulder_Large", size=1.2, subdivisions=3, noise_str=0.20)
    obj.data.materials.append(mat_stone)
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    link_to_collection(obj, col)
    print("[BOULDER] Boulder_Large selesai.")
    return obj


def create_boulder_medium(col, mat_stone):
    """Boulder sedang - penghias sudut ruangan atau cluster dengan boulder lain."""
    print("[BOULDER] Membuat Boulder_Medium...")
    obj = create_boulder_from_ico("Boulder_Medium", size=0.7, subdivisions=2, noise_str=0.15)
    obj.data.materials.append(mat_stone)
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    link_to_collection(obj, col)
    print("[BOULDER] Boulder_Medium selesai.")
    return obj


def create_boulder_small(col, mat_stone):
    """Boulder kecil - scatter prop di lantai gua."""
    print("[BOULDER] Membuat Boulder_Small...")
    obj = create_boulder_from_ico("Boulder_Small", size=0.35, subdivisions=2, noise_str=0.10)
    obj.data.materials.append(mat_stone)
    set_origin_to_bottom_center(obj)
    apply_transforms(obj)
    recalc_normals(obj)
    shade_smooth_obj(obj)
    link_to_collection(obj, col)
    print("[BOULDER] Boulder_Small selesai.")
    return obj


def create_floor_rubble(col, mat_stone):
    """
    Pecahan batu lantai / rubble - kumpulan batu kecil pipih
    yang tersebar di lantai gua.
    """
    print("[BOULDER] Membuat Floor_Rubble...")
    
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    parent = bpy.context.active_object
    parent.name = "Floor_Rubble_Group"
    
    # Buat 6-10 pecahan batu kecil
    for idx in range(random.randint(6, 10)):
        px = random.uniform(-0.8, 0.8)
        py = random.uniform(-0.8, 0.8)
        pz = 0.0
        
        # Buat shard (pecahan pipih tidak beraturan)
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=random.uniform(0.08, 0.22),
            location=(px, py, pz)
        )
        shard = bpy.context.active_object
        shard.name = f"Rubble_Shard_{idx:02d}"
        shard.data.name = f"Rubble_Shard_{idx:02d}_Mesh"
        
        # Pipihkan di sumbu Z
        shard.scale = (
            random.uniform(0.8, 1.6),
            random.uniform(0.8, 1.6),
            random.uniform(0.15, 0.35)
        )
        shard.rotation_euler.z = random.uniform(0, math.pi * 2)
        shard.rotation_euler.x = random.uniform(-0.1, 0.1)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        
        add_noise_displacement(shard, strength=0.03, scale=2.0)
        
        shard.data.materials.append(mat_stone)
        shard.parent = parent
        link_to_collection(shard, col)
    
    link_to_collection(parent, col)
    set_origin_to_bottom_center(parent)
    apply_transforms(parent)
    
    print("[BOULDER] Floor_Rubble selesai.")
    return parent


# =============================================================================
# D. OLD FIREPLACE PROP
# =============================================================================

def create_fireplace(col, mat_brick, mat_wood, mat_stone, mat_ember):
    """
    Fireplace tua dari batu bata dengan mantel kayu, lubang tungku,
    cerobong, kayu bakar, ember, dan tong dekorasi.
    
    Semua bagian digabung dalam satu empty parent untuk kemudahan
    import di Roblox Studio.
    """
    print("[FIRE] Membuat Old_Fireplace...")
    
    # Parent empty
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    fp_parent = bpy.context.active_object
    fp_parent.name = "Old_Fireplace_Group"
    
    parts = []  # Daftar semua bagian untuk parent assignment
    
    # -------------------------
    # 1. BADAN UTAMA FIREPLACE
    # -------------------------
    # Dimensi: lebar 2m, tinggi 2m, dalam 0.8m
    fp_w = 2.0
    fp_h = 2.0
    fp_d = 0.8
    
    bm = bmesh.new()
    
    # Dinding kiri
    v_left = [(-fp_w/2, 0, 0), (-fp_w/2, fp_d, 0),
              (-fp_w/2 + 0.25, fp_d, 0), (-fp_w/2 + 0.25, 0, 0),
              (-fp_w/2, 0, fp_h), (-fp_w/2, fp_d, fp_h),
              (-fp_w/2 + 0.25, fp_d, fp_h), (-fp_w/2 + 0.25, 0, fp_h)]
    v = [bm.verts.new(c) for c in v_left]
    for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
        safe_face_new(bm, [v[j] for j in fi])
    
    # Dinding kanan
    v_right = [(fp_w/2 - 0.25, 0, 0), (fp_w/2 - 0.25, fp_d, 0),
               (fp_w/2, fp_d, 0), (fp_w/2, 0, 0),
               (fp_w/2 - 0.25, 0, fp_h), (fp_w/2 - 0.25, fp_d, fp_h),
               (fp_w/2, fp_d, fp_h), (fp_w/2, 0, fp_h)]
    v = [bm.verts.new(c) for c in v_right]
    for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
        safe_face_new(bm, [v[j] for j in fi])
    
    # Dinding belakang
    back_h = fp_h
    v_back = [(-fp_w/2 + 0.25, fp_d - 0.05, 0), (fp_w/2 - 0.25, fp_d - 0.05, 0),
              (fp_w/2 - 0.25, fp_d, 0), (-fp_w/2 + 0.25, fp_d, 0),
              (-fp_w/2 + 0.25, fp_d - 0.05, back_h), (fp_w/2 - 0.25, fp_d - 0.05, back_h),
              (fp_w/2 - 0.25, fp_d, back_h), (-fp_w/2 + 0.25, fp_d, back_h)]
    v = [bm.verts.new(c) for c in v_back]
    for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
        safe_face_new(bm, [v[j] for j in fi])
    
    # Lantai dalam tungku
    arch_open_h = 1.2  # tinggi bukaan arch tungku
    v_floor = [(-fp_w/2 + 0.25, 0, 0), (fp_w/2 - 0.25, 0, 0),
               (fp_w/2 - 0.25, fp_d, 0), (-fp_w/2 + 0.25, fp_d, 0)]
    safe_face_new(bm, [bm.verts.new(c) for c in v_floor])
    
    # Bagian atas di atas arch (di atas bukaan)
    lintel_bot = arch_open_h
    v_lintel = [(-fp_w/2 + 0.25, 0, lintel_bot), (fp_w/2 - 0.25, 0, lintel_bot),
                (fp_w/2 - 0.25, fp_d * 0.1, lintel_bot), (-fp_w/2 + 0.25, fp_d * 0.1, lintel_bot),
                (-fp_w/2 + 0.25, 0, fp_h * 0.65), (fp_w/2 - 0.25, 0, fp_h * 0.65),
                (fp_w/2 - 0.25, fp_d * 0.1, fp_h * 0.65), (-fp_w/2 + 0.25, fp_d * 0.1, fp_h * 0.65)]
    v = [bm.verts.new(c) for c in v_lintel]
    for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
        safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh_body = bpy.data.meshes.new("Fireplace_Body_Mesh")
    bm.to_mesh(mesh_body)
    bm.free()
    
    fp_body = bpy.data.objects.new("Fireplace_Body", mesh_body)
    bpy.context.scene.collection.objects.link(fp_body)
    fp_body.data.materials.append(mat_brick)
    fp_body.parent = fp_parent
    parts.append(fp_body)
    
    # -------------------------
    # 2. ARCH BUKAAN TUNGKU
    # -------------------------
    bm = bmesh.new()
    arch_segs = 12
    arch_r    = 0.75
    arch_thick = 0.15
    arch_depth = 0.12
    
    for seg in range(arch_segs + 1):
        t     = seg / arch_segs
        angle = math.pi * t
        ax    = math.cos(angle) * arch_r
        az    = arch_open_h * 0.6 + math.sin(angle) * arch_r * 0.7
        
        if seg < arch_segs:
            t2    = (seg + 1) / arch_segs
            angle2 = math.pi * t2
            ax2   = math.cos(angle2) * arch_r
            az2   = arch_open_h * 0.6 + math.sin(angle2) * arch_r * 0.7
            
            ax_in  = math.cos(angle)  * (arch_r - arch_thick)
            az_in  = arch_open_h * 0.6 + math.sin(angle)  * (arch_r - arch_thick) * 0.7
            ax2_in = math.cos(angle2) * (arch_r - arch_thick)
            az2_in = arch_open_h * 0.6 + math.sin(angle2) * (arch_r - arch_thick) * 0.7
            
            v = [
                bm.verts.new((ax,    0,          az)),
                bm.verts.new((ax2,   0,          az2)),
                bm.verts.new((ax2_in,0,          az2_in)),
                bm.verts.new((ax_in, 0,          az_in)),
                bm.verts.new((ax,    arch_depth, az)),
                bm.verts.new((ax2,   arch_depth, az2)),
                bm.verts.new((ax2_in,arch_depth, az2_in)),
                bm.verts.new((ax_in, arch_depth, az_in)),
            ]
            for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
                safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh_arch = bpy.data.meshes.new("Fireplace_Arch_Mesh")
    bm.to_mesh(mesh_arch)
    bm.free()
    
    fp_arch = bpy.data.objects.new("Fireplace_Arch", mesh_arch)
    bpy.context.scene.collection.objects.link(fp_arch)
    fp_arch.data.materials.append(mat_brick)
    fp_arch.parent = fp_parent
    parts.append(fp_arch)
    
    # -------------------------
    # 3. MANTEL KAYU
    # -------------------------
    bm = bmesh.new()
    mantel_y  = 0.05
    mantel_z  = fp_h * 0.78
    mantel_w  = fp_w + 0.2
    mantel_d  = 0.18
    mantel_h  = 0.12
    
    # Papan mantel horizontal
    v = [
        bm.verts.new((-mantel_w/2, -mantel_d/2, mantel_z)),
        bm.verts.new(( mantel_w/2, -mantel_d/2, mantel_z)),
        bm.verts.new(( mantel_w/2,  mantel_d/2, mantel_z)),
        bm.verts.new((-mantel_w/2,  mantel_d/2, mantel_z)),
        bm.verts.new((-mantel_w/2, -mantel_d/2, mantel_z + mantel_h)),
        bm.verts.new(( mantel_w/2, -mantel_d/2, mantel_z + mantel_h)),
        bm.verts.new(( mantel_w/2,  mantel_d/2, mantel_z + mantel_h)),
        bm.verts.new((-mantel_w/2,  mantel_d/2, mantel_z + mantel_h)),
    ]
    for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
        safe_face_new(bm, [v[j] for j in fi])
    
    # Kolom kiri mantel
    col_w = 0.12
    col_h = mantel_z
    for cx in [-mantel_w/2 + col_w/2, mantel_w/2 - col_w/2]:
        v = [
            bm.verts.new((cx - col_w/2, -col_w/2, 0)),
            bm.verts.new((cx + col_w/2, -col_w/2, 0)),
            bm.verts.new((cx + col_w/2,  col_w/2, 0)),
            bm.verts.new((cx - col_w/2,  col_w/2, 0)),
            bm.verts.new((cx - col_w/2, -col_w/2, col_h)),
            bm.verts.new((cx + col_w/2, -col_w/2, col_h)),
            bm.verts.new((cx + col_w/2,  col_w/2, col_h)),
            bm.verts.new((cx - col_w/2,  col_w/2, col_h)),
        ]
        for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
            safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh_mantel = bpy.data.meshes.new("Fireplace_Mantel_Mesh")
    bm.to_mesh(mesh_mantel)
    bm.free()
    
    fp_mantel = bpy.data.objects.new("Fireplace_Mantel", mesh_mantel)
    bpy.context.scene.collection.objects.link(fp_mantel)
    fp_mantel.data.materials.append(mat_wood)
    fp_mantel.parent = fp_parent
    parts.append(fp_mantel)
    
    # -------------------------
    # 4. CEROBONG (CHIMNEY)
    # -------------------------
    bm = bmesh.new()
    ch_w = 0.7
    ch_h = 1.2
    ch_t = 0.15
    
    ch_bot_z = fp_h * 0.65
    
    # 4 dinding cerobong (hollow)
    for side in range(4):
        if side == 0:   coords = [(-ch_w/2, 0, ch_bot_z), (ch_w/2, 0, ch_bot_z), (ch_w/2, ch_t, ch_bot_z), (-ch_w/2, ch_t, ch_bot_z),
                                  (-ch_w/2, 0, ch_bot_z+ch_h), (ch_w/2, 0, ch_bot_z+ch_h), (ch_w/2, ch_t, ch_bot_z+ch_h), (-ch_w/2, ch_t, ch_bot_z+ch_h)]
        elif side == 1: coords = [(-ch_w/2, ch_w, ch_bot_z), (ch_w/2, ch_w, ch_bot_z), (ch_w/2, ch_w-ch_t, ch_bot_z), (-ch_w/2, ch_w-ch_t, ch_bot_z),
                                  (-ch_w/2, ch_w, ch_bot_z+ch_h), (ch_w/2, ch_w, ch_bot_z+ch_h), (ch_w/2, ch_w-ch_t, ch_bot_z+ch_h), (-ch_w/2, ch_w-ch_t, ch_bot_z+ch_h)]
        elif side == 2: coords = [(-ch_w/2, ch_t, ch_bot_z), (-ch_w/2, ch_w-ch_t, ch_bot_z), (-ch_w/2-ch_t, ch_w-ch_t, ch_bot_z), (-ch_w/2-ch_t, ch_t, ch_bot_z),
                                  (-ch_w/2, ch_t, ch_bot_z+ch_h), (-ch_w/2, ch_w-ch_t, ch_bot_z+ch_h), (-ch_w/2-ch_t, ch_w-ch_t, ch_bot_z+ch_h), (-ch_w/2-ch_t, ch_t, ch_bot_z+ch_h)]
        else:           coords = [(ch_w/2+ch_t, ch_t, ch_bot_z), (ch_w/2+ch_t, ch_w-ch_t, ch_bot_z), (ch_w/2, ch_w-ch_t, ch_bot_z), (ch_w/2, ch_t, ch_bot_z),
                                  (ch_w/2+ch_t, ch_t, ch_bot_z+ch_h), (ch_w/2+ch_t, ch_w-ch_t, ch_bot_z+ch_h), (ch_w/2, ch_w-ch_t, ch_bot_z+ch_h), (ch_w/2, ch_t, ch_bot_z+ch_h)]
        v = [bm.verts.new(c) for c in coords]
        for fi in [[0,1,5,4],[2,3,7,6],[1,2,6,5],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
            safe_face_new(bm, [v[j] for j in fi])
    
    bm.normal_update()
    mesh_ch = bpy.data.meshes.new("Fireplace_Chimney_Mesh")
    bm.to_mesh(mesh_ch)
    bm.free()
    
    fp_chimney = bpy.data.objects.new("Fireplace_Chimney", mesh_ch)
    bpy.context.scene.collection.objects.link(fp_chimney)
    fp_chimney.data.materials.append(mat_brick)
    fp_chimney.parent = fp_parent
    parts.append(fp_chimney)
    
    # -------------------------
    # 5. KAYU BAKAR
    # -------------------------
    bm = bmesh.new()
    for log_idx in range(3):
        lx = random.uniform(-0.35, 0.35)
        ly = random.uniform(fp_d * 0.2, fp_d * 0.65)
        lz = log_idx * 0.07
        lr = random.uniform(0.05, 0.09)
        ll = random.uniform(0.5, 0.75)
        
        segs = 6
        for si in range(segs):
            a1 = (si / segs) * math.pi * 2
            a2 = ((si+1) / segs) * math.pi * 2
            
            # Dua lingkaran ujung log
            v = [
                bm.verts.new((lx + math.cos(a1)*lr, ly - ll/2, lz + math.sin(a1)*lr)),
                bm.verts.new((lx + math.cos(a2)*lr, ly - ll/2, lz + math.sin(a2)*lr)),
                bm.verts.new((lx + math.cos(a2)*lr, ly + ll/2, lz + math.sin(a2)*lr)),
                bm.verts.new((lx + math.cos(a1)*lr, ly + ll/2, lz + math.sin(a1)*lr)),
            ]
            safe_face_new(bm, v)
        
        # Tutup ujung
        end_verts_l = [bm.verts.new((lx + math.cos((si/segs)*math.pi*2)*lr, ly - ll/2, lz + math.sin((si/segs)*math.pi*2)*lr)) for si in range(segs)]
        end_verts_r = [bm.verts.new((lx + math.cos((si/segs)*math.pi*2)*lr, ly + ll/2, lz + math.sin((si/segs)*math.pi*2)*lr)) for si in range(segs)]
        safe_face_new(bm, end_verts_l)
        safe_face_new(bm, end_verts_r[::-1])
    
    bm.normal_update()
    mesh_log = bpy.data.meshes.new("Fireplace_Logs_Mesh")
    bm.to_mesh(mesh_log)
    bm.free()
    
    fp_logs = bpy.data.objects.new("Fireplace_Logs", mesh_log)
    bpy.context.scene.collection.objects.link(fp_logs)
    fp_logs.data.materials.append(mat_wood)
    fp_logs.parent = fp_parent
    parts.append(fp_logs)
    
    # -------------------------
    # 6. EMBER / BARA API (Emission)
    # -------------------------
    bpy.ops.mesh.primitive_plane_add(size=0.6, location=(0, fp_d * 0.4, 0.04))
    fp_ember = bpy.context.active_object
    fp_ember.name = "Fireplace_Ember"
    fp_ember.data.name = "Fireplace_Ember_Mesh"
    fp_ember.data.materials.append(mat_ember)
    fp_ember.parent = fp_parent
    
    # Subdivide ember untuk variasi
    subdivide_mesh(fp_ember, cuts=3)
    add_noise_displacement(fp_ember, strength=0.02, scale=4.0)
    parts.append(fp_ember)
    
    # -------------------------
    # 7. EMBER/BUCKET (tong kecil)
    # -------------------------
    bm = bmesh.new()
    bucket_segs = 8
    bucket_r_bot = 0.12
    bucket_r_top = 0.15
    bucket_h     = 0.25
    bucket_x     = fp_w/2 + 0.25
    
    for si in range(bucket_segs):
        a1 = (si / bucket_segs) * math.pi * 2
        a2 = ((si+1) / bucket_segs) * math.pi * 2
        v = [
            bm.verts.new((bucket_x + math.cos(a1)*bucket_r_bot, 0.2, math.sin(a1)*bucket_r_bot)),
            bm.verts.new((bucket_x + math.cos(a2)*bucket_r_bot, 0.2, math.sin(a2)*bucket_r_bot)),
            bm.verts.new((bucket_x + math.cos(a2)*bucket_r_top, 0.2, bucket_h + math.sin(a2)*bucket_r_top)),
            bm.verts.new((bucket_x + math.cos(a1)*bucket_r_top, 0.2, bucket_h + math.sin(a1)*bucket_r_top)),
        ]
        safe_face_new(bm, v)
    
    # Tutup bawah
    bot_verts = [bm.verts.new((bucket_x + math.cos((si/bucket_segs)*math.pi*2)*bucket_r_bot,
                                0.2, math.sin((si/bucket_segs)*math.pi*2)*bucket_r_bot))
                 for si in range(bucket_segs)]
    safe_face_new(bm, bot_verts[::-1])
    
    bm.normal_update()
    mesh_bucket = bpy.data.meshes.new("Fireplace_Bucket_Mesh")
    bm.to_mesh(mesh_bucket)
    bm.free()
    
    fp_bucket = bpy.data.objects.new("Fireplace_Bucket", mesh_bucket)
    bpy.context.scene.collection.objects.link(fp_bucket)
    fp_bucket.data.materials.append(mat_stone)
    fp_bucket.parent = fp_parent
    parts.append(fp_bucket)
    
    # -------------------------
    # 8. TONG DEKORASI (Barrel)
    # -------------------------
    bm = bmesh.new()
    barrel_segs = 10
    barrel_r    = 0.22
    barrel_h    = 0.55
    barrel_x    = -fp_w/2 - 0.35
    barrel_bulge = 0.05  # barrel sedikit bulging di tengah
    
    for row in range(6):
        rz  = row / 5
        rz2 = (row+1) / 5
        # Radius bervariasi (bulging di tengah)
        ri  = barrel_r + math.sin(math.pi * rz) * barrel_bulge
        ri2 = barrel_r + math.sin(math.pi * rz2) * barrel_bulge
        
        for si in range(barrel_segs):
            a1 = (si / barrel_segs) * math.pi * 2
            a2 = ((si+1) / barrel_segs) * math.pi * 2
            v = [
                bm.verts.new((barrel_x + math.cos(a1)*ri,  math.sin(a1)*ri,  rz  * barrel_h)),
                bm.verts.new((barrel_x + math.cos(a2)*ri,  math.sin(a2)*ri,  rz  * barrel_h)),
                bm.verts.new((barrel_x + math.cos(a2)*ri2, math.sin(a2)*ri2, rz2 * barrel_h)),
                bm.verts.new((barrel_x + math.cos(a1)*ri2, math.sin(a1)*ri2, rz2 * barrel_h)),
            ]
            safe_face_new(bm, v)
    
    # Tutup atas dan bawah
    for bz, rad in [(0, barrel_r), (barrel_h, barrel_r)]:
        cap_v = [bm.verts.new((barrel_x + math.cos((si/barrel_segs)*math.pi*2)*rad,
                               math.sin((si/barrel_segs)*math.pi*2)*rad, bz))
                 for si in range(barrel_segs)]
        if bz == 0:
            safe_face_new(bm, cap_v[::-1])
        else:
            safe_face_new(bm, cap_v)
    
    bm.normal_update()
    mesh_barrel = bpy.data.meshes.new("Fireplace_Barrel_Mesh")
    bm.to_mesh(mesh_barrel)
    bm.free()
    
    fp_barrel = bpy.data.objects.new("Fireplace_Barrel", mesh_barrel)
    bpy.context.scene.collection.objects.link(fp_barrel)
    fp_barrel.data.materials.append(mat_wood)
    fp_barrel.parent = fp_parent
    parts.append(fp_barrel)
    
    # -------------------------
    # 9. COLLISION PROXY
    # -------------------------
    # Simple box collision untuk seluruh fireplace
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, fp_d/2, fp_h/2))
    fp_col = bpy.context.active_object
    fp_col.name = "Fireplace_Collision"
    fp_col.data.name = "Fireplace_Collision_Mesh"
    fp_col.scale = (fp_w/2 + 0.15, fp_d/2 + 0.1, fp_h/2)
    bpy.ops.object.transform_apply(scale=True)
    fp_col.display_type = 'WIRE'  # Tampilkan sebagai wireframe
    fp_col.hide_render = True     # Tidak di-render
    fp_col.parent = fp_parent
    
    # Tambahkan semua part ke koleksi
    link_to_collection(fp_parent, col)
    for part in parts:
        link_to_collection(part, col)
    link_to_collection(fp_col, col)
    
    set_origin_to_bottom_center(fp_parent)
    
    print("[FIRE] Old_Fireplace selesai.")
    return fp_parent


# =============================================================================
# SETUP LIGHTING DAN KAMERA
# =============================================================================

def setup_lighting_and_camera():
    """
    Tambahkan kamera dan lighting untuk preview scene di Blender.
    Menggunakan HDRI-style ambient + key light.
    """
    print("[SETUP] Menambahkan kamera dan lighting...")
    
    # Hapus light default jika ada
    for obj in bpy.data.objects:
        if obj.type in ['LIGHT', 'CAMERA']:
            bpy.data.objects.remove(obj)
    
    # ---- Key Light (cahaya utama dari atas-samping) ----
    bpy.ops.object.light_add(type='AREA', location=(8, -6, 10))
    key_light = bpy.context.active_object
    key_light.name = "Key_Light"
    key_light.data.energy = 800
    key_light.data.size = 4.0
    key_light.rotation_euler = (math.radians(45), 0, math.radians(45))
    
    # ---- Fill Light (cahaya pengisi dari kiri) ----
    bpy.ops.object.light_add(type='AREA', location=(-10, 5, 6))
    fill_light = bpy.context.active_object
    fill_light.name = "Fill_Light"
    fill_light.data.energy = 200
    fill_light.data.size = 6.0
    fill_light.rotation_euler = (math.radians(60), 0, math.radians(-30))
    
    # ---- Rim Light (backlight agar objek terlihat dari belakang) ----
    bpy.ops.object.light_add(type='SPOT', location=(0, 15, 8))
    rim_light = bpy.context.active_object
    rim_light.name = "Rim_Light"
    rim_light.data.energy = 500
    rim_light.data.spot_size = math.radians(60)
    rim_light.rotation_euler = (math.radians(-50), 0, 0)
    
    # ---- World background ----
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("World")
        bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs['Color'].default_value = (0.05, 0.04, 0.035, 1.0)  # gelap dungeon
        bg.inputs['Strength'].default_value = 0.5
    
    # ---- Kamera ----
    bpy.ops.object.camera_add(location=(20, -16, 12))
    cam = bpy.context.active_object
    cam.name = "Preview_Camera"
    cam.rotation_euler = (math.radians(60), 0, math.radians(52))
    cam.data.lens = 35
    bpy.context.scene.camera = cam
    
    # Render settings untuk preview
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    
    print("[SETUP] Kamera dan lighting selesai.")


# =============================================================================
# LAYOUT SCENE
# =============================================================================

def arrange_assets_in_scene(asset_groups):
    """
    Susun semua aset di scene dengan jarak yang rapi.
    Layout dalam grid 4 baris x N kolom berdasarkan kategori.
    
    asset_groups: dict {kategori: [(obj, nama), ...]}
    """
    print("[LAYOUT] Menyusun aset di scene...")
    
    # Jarak antar aset
    spacing_x = TILE_SIZE * 1.8
    spacing_y = TILE_SIZE * 1.8
    
    row_y = 0
    for category, assets in asset_groups.items():
        col_x = 0
        for obj in assets:
            if obj is not None:
                obj.location = (col_x, row_y, 0)
                col_x += spacing_x
        row_y -= spacing_y
    
    print("[LAYOUT] Layout selesai.")


# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

def ensure_export_dir():
    """Buat folder exports jika belum ada."""
    os.makedirs(EXPORT_PATH, exist_ok=True)
    print(f"[EXPORT] Folder export: {EXPORT_PATH}")
    return EXPORT_PATH


def collect_objects_from_collection(collection):
    """
    Ambil semua objek dari collection, termasuk child object dari parent empty.
    Ini penting karena beberapa aset seperti fireplace/stalactite/rubble
    memakai Empty sebagai parent.
    """
    result = set()

    def add_obj_recursive(obj):
        result.add(obj)
        for child in obj.children:
            add_obj_recursive(child)

    def walk_collection(col):
        for obj in col.objects:
            add_obj_recursive(obj)
        for child_col in col.children:
            walk_collection(child_col)

    walk_collection(collection)
    return sorted(result, key=lambda o: o.name)


def select_objects_for_export(objects):
    """Select objek group tertentu untuk export FBX."""
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        if obj.name in bpy.data.objects:
            obj.select_set(True)

    for obj in objects:
        if obj.name in bpy.data.objects:
            bpy.context.view_layer.objects.active = obj
            break


def export_group_fbx(export_dir, filename, collection):
    """
    Export satu collection menjadi satu file FBX.
    Output hanya berisi objek dari kategori tersebut.
    """
    fbx_path = os.path.join(export_dir, filename)
    objects = collect_objects_from_collection(collection)
    exportable = [obj for obj in objects if obj.type in {'MESH', 'EMPTY'}]

    select_objects_for_export(exportable)

    bpy.ops.export_scene.fbx(
        filepath             = fbx_path,
        use_selection        = True,
        global_scale         = 1.0,
        apply_unit_scale     = True,
        apply_scale_options  = 'FBX_SCALE_ALL',
        axis_forward         = '-Z',
        axis_up              = 'Y',
        object_types         = {'MESH', 'EMPTY'},
        use_mesh_modifiers   = True,
        mesh_smooth_type     = 'FACE',
        use_triangles        = True,
        bake_space_transform = True,
        embed_textures       = False,
        path_mode            = 'AUTO',
        use_metadata         = True,
    )

    print(f"[EXPORT] FBX group disimpan: {fbx_path}")
    bpy.ops.object.select_all(action='DESELECT')


def export_group_blend(export_dir, filename, collection):
    """
    Export satu collection menjadi satu file .blend terpisah.
    Menggunakan bpy.data.libraries.write agar file .blend hanya membawa
    collection kategori tersebut beserta mesh/material dependensinya.
    """
    blend_path = os.path.join(export_dir, filename)

    datablocks = {collection}
    objects = collect_objects_from_collection(collection)

    for obj in objects:
        datablocks.add(obj)

        if getattr(obj, "data", None):
            datablocks.add(obj.data)

        if hasattr(obj, "material_slots"):
            for slot in obj.material_slots:
                if slot.material:
                    datablocks.add(slot.material)

    bpy.data.libraries.write(
        filepath=blend_path,
        datablocks=datablocks,
        fake_user=True,
        compress=True
    )

    print(f"[EXPORT] BLEND group disimpan: {blend_path}")


def export_all_asset_groups(export_dir, group_collections):
    """
    Export asset pack menjadi 4 pasang file:
    1. stone_wall_set.blend / .fbx
    2. cave_ceiling_set.blend / .fbx
    3. boulder_prop_set.blend / .fbx
    4. old_fireplace_prop.blend / .fbx
    """
    export_jobs = [
        ("stone_wall_set",      group_collections["walls"]),
        ("cave_ceiling_set",    group_collections["ceilings"]),
        ("boulder_prop_set",    group_collections["boulders"]),
        ("old_fireplace_prop",  group_collections["fireplace"]),
    ]

    for base_name, collection in export_jobs:
        print(f"\n[EXPORT] Memproses group: {base_name}")
        export_group_fbx(export_dir, base_name + ".fbx", collection)
        export_group_blend(export_dir, base_name + ".blend", collection)

    print("\n[EXPORT] Semua group selesai diexport.")


# =============================================================================
# MAIN FUNCTION
# =============================================================================

def main():
    """
    Fungsi utama yang mengorkestrasi pembuatan seluruh asset pack.
    Urutan eksekusi:
    1. Bersihkan scene
    2. Buat materials
    3. Buat koleksi
    4. Buat semua aset
    5. Atur layout scene
    6. Tambahkan kamera & lighting
    7. Export
    """
    print("=" * 60)
    print("ROBLOX LABYRINTH ASSET PACK - Mulai Generate...")
    print("=" * 60)
    
    # 1. Bersihkan scene
    clear_scene()
    
    # 2. Set unit ke metric
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.length_unit = 'METERS'
    bpy.context.scene.unit_settings.scale_length = 1.0
    
    # 3. Buat materials
    print("\n[MATERIAL] Membuat materials...")
    mat_stone_dark  = create_stone_material("Mat_Stone_Dark",  COL_STONE_GRAY,  roughness_val=0.88)
    mat_stone_light = create_stone_material("Mat_Stone_Light", COL_STONE_LIGHT, roughness_val=0.82)
    mat_cave        = create_stone_material("Mat_Cave_Ceiling", COL_BROWN_EARTH, roughness_val=0.92)
    mat_brick       = create_brick_material("Mat_Brick_Old")
    mat_wood        = create_wood_material("Mat_Wood_Dark")
    mat_ember       = create_ember_material("Mat_Ember_Fire")
    print("[MATERIAL] Semua material selesai.")
    
    # 4. Buat koleksi
    print("\n[COLLECTION] Membuat koleksi...")
    col_root   = create_collection("Roblox_Labyrinth_Assets")
    col_walls  = create_collection("A_Stone_Wall_Set",  parent=col_root)
    col_ceil   = create_collection("B_Cave_Ceiling_Set", parent=col_root)
    col_bould  = create_collection("C_Boulder_Prop_Set", parent=col_root)
    col_fire   = create_collection("D_Fireplace_Prop",   parent=col_root)
    print("[COLLECTION] Koleksi selesai.")
    
    # 5. Generate aset
    print("\n--- A. STONE WALL SET ---")
    w_straight  = create_wall_straight(col_walls, mat_stone_dark)
    w_corner    = create_wall_corner(col_walls, mat_stone_dark)
    w_endcap    = create_wall_end_cap(col_walls, mat_stone_dark)
    w_short     = create_wall_short(col_walls, mat_stone_light)
    w_pillar    = create_wall_pillar(col_walls, mat_stone_dark)
    
    print("\n--- B. CAVE CEILING SET ---")
    c_flat      = create_ceiling_flat(col_ceil, mat_cave)
    c_arch      = create_ceiling_arch(col_ceil, mat_cave)
    c_stala     = create_ceiling_stalactite(col_ceil, mat_cave)
    c_crack     = create_ceiling_crack(col_ceil, mat_cave)
    
    print("\n--- C. BOULDER PROP SET ---")
    b_large     = create_boulder_large(col_bould, mat_stone_light)
    b_medium    = create_boulder_medium(col_bould, mat_stone_light)
    b_small     = create_boulder_small(col_bould, mat_stone_dark)
    b_rubble    = create_floor_rubble(col_bould, mat_stone_dark)
    
    print("\n--- D. OLD FIREPLACE PROP ---")
    fireplace   = create_fireplace(col_fire, mat_brick, mat_wood, mat_stone_dark, mat_ember)
    
    # 6. Atur layout
    asset_groups = {
        "Wall_Set":     [w_straight, w_corner, w_endcap, w_short, w_pillar],
        "Ceiling_Set":  [c_flat, c_arch, c_stala, c_crack],
        "Boulder_Set":  [b_large, b_medium, b_small, b_rubble],
        "Fireplace":    [fireplace],
    }
    arrange_assets_in_scene(asset_groups)
    
    # 7. Kamera & Lighting
    setup_lighting_and_camera()
    
    # 8. Export menjadi 4 file .fbx dan 4 file .blend berdasarkan kategori aset
    print("\n[EXPORT] Memulai export modular per kategori...")
    export_dir = ensure_export_dir()

    group_collections = {
        "walls":     col_walls,
        "ceilings":  col_ceil,
        "boulders":  col_bould,
        "fireplace": col_fire,
    }

    export_all_asset_groups(export_dir, group_collections)

    print("\n" + "=" * 60)
    print("SELESAI! Asset pack berhasil dibuat menjadi 4 file FBX dan 4 file BLEND.")
    print(f"Lokasi file: {export_dir}")
    print("  - stone_wall_set.fbx")
    print("  - stone_wall_set.blend")
    print("  - cave_ceiling_set.fbx")
    print("  - cave_ceiling_set.blend")
    print("  - boulder_prop_set.fbx")
    print("  - boulder_prop_set.blend")
    print("  - old_fireplace_prop.fbx")
    print("  - old_fireplace_prop.blend")
    print("=" * 60)
    print("\nCATATAN ROBLOX STUDIO:")
    print("- Import FBX: File > Import > FBX")
    print("- Sesuaikan scale jika perlu (1 unit Blender = 1 stud Roblox)")
    print("- Tambahkan SpecialMesh atau UnionOperation sesuai kebutuhan")
    print("- Material perlu dibuat ulang di Roblox (tidak support Cycles)")
    print("=" * 60)


# =============================================================================
# JALANKAN SCRIPT
# =============================================================================

if __name__ == "__main__":
    main()
# Dipanggil langsung jika dijalankan di Blender Text Editor
else:
    main()