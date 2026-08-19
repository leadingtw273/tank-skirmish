"""Pinned, single-item Blender exporter. Live bpy validation belongs to LEA-81."""
import hashlib
import json
import sys
from pathlib import Path

import bpy

BUILDING_IMAGE_PATH = "//Texture.png"
GLTF_OPTIONS = {
    "export_format": "GLB",
    "export_yup": True,
    "use_selection": True,
    "export_apply": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_draco_mesh_compression_enable": False,
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def load_request():
    marker = sys.argv.index("--")
    require(len(sys.argv) == marker + 2, "exactly one request path is required")
    request_path = Path(sys.argv[marker + 1]).resolve()
    request = json.loads(request_path.read_text(encoding="utf-8"))
    expected = {"category", "id", "outputPrivatePath", "policy", "resultPrivatePath", "scale", "sourceBasename", "atlasBasename", "atlasDigest"}
    require(set(request) == expected, "closed request schema")
    require(request["id"] in {"tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"}, "closed model id")
    require(request["category"] in {"tank", "building"} and isinstance(request["scale"], (int, float)), "invalid identity")
    for key in ("sourceBasename", "atlasBasename"):
        value = request[key]
        require(value is None or (isinstance(value, str) and Path(value).name == value), "basename only")
    return request_path.parent, request


def used_images():
    images = []
    for material in bpy.data.materials:
        if material.use_nodes and material.node_tree:
            images.extend(node.image for node in material.node_tree.nodes if node.type == "TEX_IMAGE" and node.image)
    return images


def verify_images(request_dir, request):
    images = used_images()
    if request["category"] == "tank":
        require(request["id"] == "tank2" and not images, "Tank2 must not depend on material images")
        return
    require(request["atlasBasename"] == "Texture.png", "building atlas basename")
    require(images, "building must use Texture.png")
    atlas = (request_dir / "Texture.png").resolve()
    require(atlas.parent == request_dir.resolve() and atlas.is_file(), "atlas must be staged")
    require(hashlib.sha256(atlas.read_bytes()).hexdigest() == request["atlasDigest"], "atlas digest mismatch")
    for image in images:
        require(image.filepath == BUILDING_IMAGE_PATH and image.has_data, "building image contract")
        require(Path(bpy.path.abspath(image.filepath)).resolve() == atlas, "building image escaped staging")


def select_and_scale(scale):
    bpy.context.scene.frame_set(0)
    for armature in (obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"):
        armature.data.pose_position = "REST"
    bpy.ops.object.select_all(action="SELECT")
    roots = [obj for obj in bpy.context.selected_objects if obj.parent is None]
    require(roots, "source must contain an object hierarchy")
    for root in roots:
        root.scale = tuple(component * scale for component in root.scale)
    bpy.context.view_layer.objects.active = roots[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def main():
    request_dir, request = load_request()
    source = (request_dir / request["sourceBasename"]).resolve()
    require(source.parent == request_dir.resolve() and source.is_file(), "source must be staged")
    bpy.ops.wm.open_mainfile(filepath=str(source))
    verify_images(request_dir, request)
    source_action_names = sorted(action.name for action in bpy.data.actions)
    if request["category"] == "building":
        require(not source_action_names, "buildings must have no source actions")
    select_and_scale(request["scale"])
    output = Path(request["outputPrivatePath"])
    result = Path(request["resultPrivatePath"])
    require(output.parent == request_dir and result.parent == request_dir, "private output must remain staged")
    bpy.ops.export_scene.gltf(filepath=str(output), **GLTF_OPTIONS)
    result.write_text(json.dumps({"sourceActionNames": source_action_names}, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
