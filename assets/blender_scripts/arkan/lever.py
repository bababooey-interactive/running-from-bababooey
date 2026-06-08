"""
lever.py — Low-poly wall lever with ON and OFF states for Roblox.

Usage: Run from Blender's scripting panel (Text > Run Script).
Exports two FBX files:
  assets/models/lever_off.fbx  — arm tilted back  (-40°)
  assets/models/lever_on.fbx   — arm pushed forward (+40°)
  assets/models/lever.blend    — both states saved in one blend file

In Roblox Studio you can swap between the two models via a Script, or use
a single model and tween/rotate the arm part between the two angles.
"""

import math
import os

import bpy

# Lever arm angle from vertical (degrees).  Tweak if you want a different throw.
ANGLE_OFF = -40  # arm tilted back  → OFF
ANGLE_ON = 40  # arm pushed forward → ON


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_mat(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def assign_mat(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def build_lever(arm_angle_deg):
    """
    Build a full lever assembly at the given arm angle.
    arm_angle_deg: rotation of the arm around the X axis (+ = forward, - = back).
    Returns a list of all mesh objects.
    """
    r = math.radians(arm_angle_deg)

    mat_iron = make_mat("Iron", (0.22, 0.22, 0.25), metallic=0.90, roughness=0.30)
    mat_grip = make_mat("Grip", (0.16, 0.08, 0.04), roughness=0.95)  # dark wood handle

    # ── Base plate ──────────────────────────────────────────────────────────
    # Flat rectangular plate that mounts to a wall or floor.
    # Spans z = 0.00 → 0.10
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0.05))
    base = bpy.context.active_object
    base.name = "Lever_Base"
    base.scale = (0.18, 0.12, 0.05)
    bpy.ops.object.transform_apply(scale=True)
    assign_mat(base, mat_iron)

    # ── Pivot axle ───────────────────────────────────────────────────────────
    # Short horizontal cylinder at the top of the base plate.
    # Center at z = 0.14, runs along Y axis.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8,
        radius=0.030,
        depth=0.16,
        location=(0, 0, 0.14),
        rotation=(math.pi / 2, 0, 0),
    )
    pivot = bpy.context.active_object
    pivot.name = "Lever_Pivot"
    assign_mat(pivot, mat_iron)

    # ── Arm rod ───────────────────────────────────────────────────────────────
    # Thin cylinder, 0.50 m long.  Its geometric center is placed halfway along
    # the angled direction from the pivot (z=0.14) so that it rotates cleanly.
    ARM_LEN = 0.50
    HALF_ARM = ARM_LEN / 2
    PIVOT_Z = 0.14

    arm_cx = 0.0
    arm_cy = -math.sin(r) * HALF_ARM
    arm_cz = PIVOT_Z + math.cos(r) * HALF_ARM

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6,
        radius=0.022,
        depth=ARM_LEN,
        location=(arm_cx, arm_cy, arm_cz),
    )
    arm = bpy.context.active_object
    arm.name = "Lever_Arm"
    arm.rotation_euler.x = r  # tilt the cylinder along with its position
    assign_mat(arm, mat_iron)

    # ── Grip (T-bar) ──────────────────────────────────────────────────────────
    # Short horizontal cylinder at the tip of the arm, perpendicular to it.
    tip_y = -math.sin(r) * ARM_LEN
    tip_z = PIVOT_Z + math.cos(r) * ARM_LEN

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6,
        radius=0.034,
        depth=0.13,
        location=(0, tip_y, tip_z),
        rotation=(math.pi / 2, 0, 0),
    )
    grip = bpy.context.active_object
    grip.name = "Lever_Grip"
    assign_mat(grip, mat_grip)

    # ── Hierarchy ─────────────────────────────────────────────────────────────
    for obj in (pivot, arm, grip):
        obj.parent = base

    # Origin at bottom center of base (z=0) for easy Roblox placement
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    return [base, pivot, arm, grip]


def export_fbx(parts, fbx_path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)

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


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    export_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "models"))
    os.makedirs(export_dir, exist_ok=True)

    states = [
        ("off", ANGLE_OFF),
        ("on", ANGLE_ON),
    ]

    for state, angle in states:
        clear_scene()
        parts = build_lever(angle)
        export_fbx(parts, os.path.join(export_dir, f"lever_{state}.fbx"))

    # Save final .blend (contains the last built state, ON)
    blend_path = os.path.join(export_dir, "lever.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"➔ Saved BLEND:  {blend_path}")


main()
