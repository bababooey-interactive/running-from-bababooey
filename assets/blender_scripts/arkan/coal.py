"""
coal.py — Simple low-poly coal lump for Roblox (pickup / throwable).

Usage: Run from Blender's scripting panel (Text > Run Script).
Exports:  assets/models/coal.fbx
          assets/models/coal.blend
"""

import os

import bpy


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def create_coal():
    clear_scene()

    # Icosphere subdivisions=1 → 20 flat triangular faces (nice chunky low-poly lump)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1, radius=0.15, location=(0, 0, 0.15)
    )
    coal = bpy.context.active_object
    coal.name = "Coal"

    # Squash slightly so it reads as a ground-picked lump, not a perfect sphere
    coal.scale = (1.0, 0.85, 0.72)
    bpy.ops.object.transform_apply(scale=True)

    # Dark matte coal material
    mat = bpy.data.materials.new(name="Coal_Mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.03, 0.03, 0.03, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.98

    coal.data.materials.clear()
    coal.data.materials.append(mat)

    # Origin at the very bottom of the lump
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.objects.active = coal
    coal.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    return coal


def export_coal(coal):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    export_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "models"))
    os.makedirs(export_dir, exist_ok=True)

    fbx_path = os.path.join(export_dir, "coal.fbx")
    blend_path = os.path.join(export_dir, "coal.blend")

    bpy.ops.object.select_all(action="DESELECT")
    coal.select_set(True)

    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
    )
    print(f"➔ Exported FBX: {fbx_path}")

    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"➔ Saved BLEND:  {blend_path}")


coal = create_coal()
export_coal(coal)
