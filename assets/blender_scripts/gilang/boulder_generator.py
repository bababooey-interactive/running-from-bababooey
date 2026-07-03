import bpy
import math
import os
import random
from mathutils import Vector

random.seed(42)
EXPORT_PATH = r"D:\code vs\Komgraf\Tubes\running-from-bababooey\assets\models\generated"

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

def setup_units():
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.length_unit = "METERS"
    bpy.context.scene.unit_settings.scale_length = 1.0

def make_mat(name, color, roughness=0.85, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat

def apply_rot_scale(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)

def bottom_to_z0(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    obj.location.z -= min(v.z for v in corners)

def origin_bottom_center(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_z = min(v.z for v in corners)
    cx = (min(v.x for v in corners) + max(v.x for v in corners)) / 2
    cy = (min(v.y for v in corners) + max(v.y for v in corners)) / 2
    old = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = (cx, cy, min_z)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    bpy.context.scene.cursor.location = old
    obj.select_set(False)

def fix_mesh(obj):
    if obj.type != "MESH":
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_flat()
    obj.select_set(False)

def add_camera_light():
    bpy.ops.object.light_add(type="AREA", location=(0, -6, 6))
    light = bpy.context.object
    light.name = "Preview_Area_Light"
    light.data.energy = 350
    light.data.size = 5
    bpy.ops.object.camera_add(location=(5, -8, 4), rotation=(math.radians(62), 0, math.radians(34)))
    cam = bpy.context.object
    cam.name = "Preview_Camera"
    cam.data.lens = 28
    bpy.context.scene.camera = cam

def export_asset(obj, base_name):
    os.makedirs(EXPORT_PATH, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    blend_path = os.path.join(EXPORT_PATH, base_name + ".blend")
    fbx_path = os.path.join(EXPORT_PATH, base_name + ".fbx")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.fbx(filepath=fbx_path, use_selection=True, global_scale=1.0, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"}, use_mesh_modifiers=True, mesh_smooth_type="FACE", use_triangles=True, bake_space_transform=False, embed_textures=False, path_mode="AUTO", use_metadata=True)
    print("EXPORT SELESAI:", blend_path, fbx_path)

def create_boulder_large():
    mat=make_mat("Boulder_Beige_RobloxSafe", (0.55,0.49,0.39,1))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.35, location=(0,0,1.1))
    obj=bpy.context.object; obj.name="Boulder_Large"; obj.data.name="Boulder_Large_Mesh"; obj.data.materials.append(mat)
    for v in obj.data.vertices:
        s=random.uniform(.75,1.25)
        v.co.x*=s*random.uniform(.92,1.15); v.co.y*=s*random.uniform(.85,1.12); v.co.z*=s*random.uniform(.75,1.20)
        if v.co.z < -0.55: v.co.z*=.35
    tex=bpy.data.textures.new("Boulder_Noise", type="VORONOI"); tex.noise_scale=1.5
    disp=obj.modifiers.new("Small_Rock_Displacement","DISPLACE"); disp.texture=tex; disp.strength=.08
    bpy.context.view_layer.objects.active=obj; obj.select_set(True); bpy.ops.object.modifier_apply(modifier=disp.name); obj.select_set(False)
    bpy.data.textures.remove(tex)
    obj.scale=(2.3,2.0,1.8); apply_rot_scale(obj); bottom_to_z0(obj); origin_bottom_center(obj); fix_mesh(obj)
    return obj

def main():
    clear_scene(); setup_units(); obj=create_boulder_large(); add_camera_light(); export_asset(obj,"boulder_large")
if __name__=="__main__": main()
