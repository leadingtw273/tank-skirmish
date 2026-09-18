"""Blender-only helper: import one staged source model and export a GLB."""
import sys
from pathlib import Path

import bpy


def main():
    marker = sys.argv.index("--")
    source, output = (Path(value).resolve() for value in sys.argv[marker + 1:marker + 3])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    if source.suffix.lower() == ".dae":
        bpy.ops.wm.collada_import(filepath=str(source))
    elif source.suffix.lower() == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source))
    else:
        raise ValueError(f"unsupported conversion source: {source}")
    bpy.ops.object.select_all(action="SELECT")
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", export_yup=True, use_selection=True,
        export_apply=True, export_materials="EXPORT", export_image_format="AUTO",
        export_draco_mesh_compression_enable=False,
    )


if __name__ == "__main__":
    main()
