"""Pinned, single-item Blender exporter. Live bpy validation belongs to LEA-81."""
import hashlib
import json
import sys
from pathlib import Path

import bpy

BUILDING_IMAGE_PATH = "//Texture.png"
CLOSED_IDS = {
    "tank2", "1story", "1story-gable-roof", "2story", "2story-slim",
    "2story-wide", "3story-small", "4story", "6story-stack",
}
REQUEST_FIELDS = {
    "atlasBasename", "atlasDigest", "category", "id", "outputPrivatePath",
    "policy", "resultPrivatePath", "scale", "sourceBasename",
}
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
    require(set(request) == REQUEST_FIELDS, "closed request schema")
    require(request["id"] in CLOSED_IDS and request["category"] in {"tank", "building"} and isinstance(request["scale"], (int, float)), "invalid identity")
    require((request["id"] == "tank2") == (request["category"] == "tank"), "closed category mapping")
    require(isinstance(request["policy"], dict) and set(request["policy"]) == {"animation", "texture"}, "closed policy")
    for key in ("sourceBasename", "atlasBasename"):
        value = request[key]
        require(value is None or (isinstance(value, str) and Path(value).name == value), "basename only")
    require(isinstance(request["sourceBasename"], str), "source basename required")
    require(request["atlasBasename"] is None or (request["atlasBasename"] == "Texture.png" and isinstance(request["atlasDigest"], str)), "atlas contract")
    require(request["atlasBasename"] is not None or request["atlasDigest"] is None, "tank atlas contract")
    for key in ("outputPrivatePath", "resultPrivatePath"):
        require(isinstance(request[key], str) and Path(request[key]).is_absolute(), "private path required")
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
        require(image.filepath == BUILDING_IMAGE_PATH, "building image path contract")
        require(Path(bpy.path.abspath(image.filepath)).resolve() == atlas, "building image escaped staging")
        try:
            image.reload()
            image.pixels[0]
        except Exception as error:
            raise RuntimeError("building image load failed") from error
        require(image.has_data, "building image data unavailable")
    return tuple(images)


def only(items, message):
    require(len(items) == 1, message)
    return items[0]


def linked_from(socket, node, output_name, message):
    require(socket.is_linked and len(socket.links) == 1, message)
    link = socket.links[0]
    require(link.from_node == node and link.from_socket == node.outputs[output_name], message)


def legacy_building_graphs(verified_images):
    graphs = []
    for material in bpy.data.materials:
        require(material.use_nodes and material.node_tree, "building material nodes required")
        node_tree = material.node_tree
        nodes = list(node_tree.nodes)
        require(len(nodes) == 3, "building material topology")
        image = only([node for node in nodes if node.type == "TEX_IMAGE"], "building material image node")
        diffuse = only([node for node in nodes if node.type == "BSDF_DIFFUSE"], "building material diffuse node")
        output = only([node for node in nodes if node.type == "OUTPUT_MATERIAL"], "building material output node")
        require(output.is_active_output, "building material active output")
        require(image.image and any(image.image == verified_image for verified_image in verified_images), "building material verified image")
        linked_from(diffuse.inputs["Color"], image, "Color", "building material image color link")
        linked_from(output.inputs["Surface"], diffuse, "BSDF", "building material surface link")
        require(len(node_tree.links) == 2, "building material topology")
        graphs.append((node_tree, image, diffuse, output))
    require(graphs, "building materials required")
    return graphs


def normalize_building_materials(verified_images):
    graphs = legacy_building_graphs(verified_images)
    for node_tree, image, diffuse, output in graphs:
        principled = node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        principled.name = "Principled BSDF"
        node_tree.links.new(image.outputs["Color"], principled.inputs["Base Color"])
        node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
        node_tree.nodes.remove(diffuse)


def select_and_scale(scale, category):
    bpy.context.scene.frame_set(0)
    for armature in (obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"):
        armature.data.pose_position = "POSE" if category == "tank" else "REST"
    bpy.ops.object.select_all(action="SELECT")
    roots = [obj for obj in bpy.context.selected_objects if obj.parent is None]
    require(roots, "source must contain an object hierarchy")
    if category == "tank":
        require(bpy.data.objects.get("AgentTeamScaleRoot") is None, "reserved scale root already exists")
        scaled_root = bpy.data.objects.new("AgentTeamScaleRoot", None)
        bpy.context.scene.collection.objects.link(scaled_root)
        for root in roots:
            world = root.matrix_world.copy()
            root.parent = scaled_root
            root.matrix_world = world
        scaled_root.scale = (scale, scale, scale)
        bpy.ops.object.select_all(action="SELECT")
        bpy.context.view_layer.objects.active = scaled_root
        return
    for root in roots:
        root.scale = tuple(component * scale for component in root.scale)
    bpy.context.view_layer.objects.active = roots[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def main():
    request_dir, request = load_request()
    source = (request_dir / request["sourceBasename"]).resolve()
    require(source.parent == request_dir.resolve() and source.is_file(), "source must be staged")
    bpy.ops.wm.open_mainfile(filepath=str(source))
    verified_images = verify_images(request_dir, request)
    source_action_names = sorted(action.name for action in bpy.data.actions)
    if request["category"] == "building":
        require(not source_action_names, "buildings must have no source actions")
        normalize_building_materials(verified_images)
    select_and_scale(request["scale"], request["category"])
    output = Path(request["outputPrivatePath"]).resolve()
    result = Path(request["resultPrivatePath"]).resolve()
    require(output.parent == request_dir and result.parent == request_dir and output != result, "private output must remain staged")
    result.write_text(json.dumps({"sourceActionNames": source_action_names}, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")
    bpy.ops.export_scene.gltf(filepath=str(output), **GLTF_OPTIONS)


if __name__ == "__main__":
    main()
