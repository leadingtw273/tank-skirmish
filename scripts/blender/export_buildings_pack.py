"""Export the LEA-177 Quaternius Buildings Pack without altering its source assets.

Run Blender with ``--disable-autoexec``.  The script consumes only the official
Blend/PNG files under assets/QuaterniusBuildings and emits reproducible GLBs.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import bpy


SCALE = 3.6
PALETTES = (
    "Blue", "Casino", "Dark", "DarkBlue", "DarkPurple", "Green", "Grey",
    "Light", "Light2", "Red", "Signs", "Yellow",
)
TEXTURED_GROUPS = ("base", "parts", "finished")
ALL_GROUPS = ("base", "parts", "finished", "materials")
GLTF_OPTIONS = {
    "export_format": "GLB",
    "export_yup": True,
    "use_selection": True,
    "export_apply": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_draco_mesh_compression_enable": False,
}


def arguments() -> argparse.Namespace:
    marker = __import__("sys").argv.index("--")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--group", choices=(*ALL_GROUPS, "full_pack"), required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--inspect-source", type=Path)
    return parser.parse_args(__import__("sys").argv[marker + 1 :])


def mesh_roots() -> list[bpy.types.Object]:
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("source Blend has no mesh objects")
    roots: list[bpy.types.Object] = []
    for obj in meshes:
        root = obj
        while root.parent is not None:
            root = root.parent
        if root not in roots:
            roots.append(root)
    return roots


def select_and_scale() -> None:
    bpy.context.scene.frame_set(0)
    bpy.ops.object.select_all(action="DESELECT")
    roots = mesh_roots()
    for root in roots:
        root.select_set(True)
        root.scale = tuple(axis * SCALE for axis in root.scale)
    bpy.context.view_layer.objects.active = roots[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def source_image(material: bpy.types.Material):
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                return node.image
    return None


def normalize_materials(texture: Path | None, textured: bool) -> None:
    """Translate Blender 2.79 Diffuse materials into glTF-supported PBR nodes."""
    palette_image = None
    if texture is not None:
        palette_image = bpy.data.images.load(str(texture), check_existing=False)
        palette_image.colorspace_settings.name = "sRGB"
        palette_image.pack()
    for material in bpy.data.materials:
        image = palette_image if palette_image is not None else source_image(material)
        color = tuple(material.diffuse_color)
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Base Color"].default_value = color
        links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        if textured:
            if image is None:
                raise RuntimeError(f"textured material has no atlas image: {material.name}")
            image.pack()
            uv = nodes.new("ShaderNodeUVMap")
            atlas = nodes.new("ShaderNodeTexImage")
            atlas.image = image
            links.new(uv.outputs["UV"], atlas.inputs["Vector"])
            links.new(atlas.outputs["Color"], shader.inputs["Base Color"])


def export(source: Path, output: Path, texture: Path | None) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(source))
    normalize_materials(texture, source.parent.name != "materials")
    select_and_scale()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output), **GLTF_OPTIONS)


def source_files(source_root: Path, group: str) -> list[Path]:
    return sorted((source_root / group).glob("*.blend"))


def jobs(source_root: Path, output_root: Path, group: str):
    if group == "full_pack":
        for source_group in ALL_GROUPS:
            for source in source_files(source_root, source_group):
                yield source, output_root / group / source_group / f"{source.stem}.glb", None
        return
    sources = source_files(source_root, group)
    if group == "materials":
        for source in sources:
            yield source, output_root / group / f"{source.stem}.glb", None
        return
    for palette in PALETTES:
        texture = source_root / "textures" / f"Texture_{palette}.png"
        if not texture.is_file():
            raise RuntimeError(f"missing official palette: {texture}")
        for source in sources:
            yield source, output_root / group / palette.lower() / f"{source.stem}.glb", texture


def main() -> None:
    args = arguments()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    if args.inspect_source:
        bpy.ops.wm.open_mainfile(filepath=str(args.inspect_source.resolve()))
        for material in bpy.data.materials:
            print("MATERIAL", material.name, "nodes=", material.use_nodes, "diffuse=", tuple(material.diffuse_color))
            if material.node_tree:
                for node in material.node_tree.nodes:
                    print(" NODE", node.type, node.name, "image=", node.image.name if node.type == "TEX_IMAGE" and node.image else "")
        return
    planned = list(jobs(source_root, output_root, args.group))
    expected = {"full_pack": 102, "finished": 312, "base": 216, "parts": 384, "materials": 26}[args.group]
    if len(planned) != expected:
        raise RuntimeError(f"{args.group}: expected {expected} jobs, got {len(planned)}")
    print(f"LEA-177 {args.group}: {len(planned)} exports")
    if not args.dry_run:
        for index, (source, output, texture) in enumerate(planned, start=1):
            export(source, output, texture)
            print(f"[{index}/{len(planned)}] {output}")


if __name__ == "__main__":
    main()
