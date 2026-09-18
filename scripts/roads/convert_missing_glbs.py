#!/usr/bin/env python3
"""Convert only the three unique road models absent from the upstream GLBs."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


BLENDER = Path("/home/markchou/.cache/tank-skirmish/toolchains/blender/4.5.12/blender-4.5.12-linux-x64/blender")
CONVERSIONS = (
    {"id": "Road5_Shoulder2", "pack": "parking", "archive": "[PLUS] Modular Roads - Parking.zip", "source": "PLUS/dae/Road5_Shoulder2.dae"},
    {"id": "SignCircle", "pack": "signs", "archive": "[PLUS] Modular Roads - Road Signs.zip", "source": "PLUS/Blank_Sign_Meshes/dae/SignCircle.dae"},
    {"id": "Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right", "pack": "racetrack", "archive": "[PLUS] Modular Roads - Racetrack.zip", "source": "PLUS/fbx/Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right.fbx"},
)


def safe_relative(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe ZIP path: {name!r}")
    return path


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def glb_materials(path: Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        raise ValueError(f"invalid GLB: {path}")
    _, version, length = struct.unpack_from("<4sII", raw)
    if version != 2 or length != len(raw):
        raise ValueError(f"invalid GLB length: {path}")
    json_length, chunk_type = struct.unpack_from("<I4s", raw, 12)
    if chunk_type != b"JSON":
        raise ValueError(f"GLB JSON chunk missing: {path}")
    document = json.loads(raw[20:20 + json_length].decode("utf-8").rstrip(" \t\r\n\0"))
    images, textures = document.get("images", []), document.get("textures", [])
    def image_name(info: Any) -> str:
        if not isinstance(info, dict) or not isinstance(info.get("index"), int): return ""
        texture_index = info["index"]
        if not 0 <= texture_index < len(textures): return ""
        image_index = textures[texture_index].get("source")
        if not isinstance(image_index, int) or not 0 <= image_index < len(images): return ""
        image = images[image_index]
        return str(image.get("name") or image.get("uri") or f"embedded_image_{image_index}")
    return [{"name": str(material.get("name") or f"material_{index}"), "image_name": image_name(material.get("pbrMetallicRoughness", {}).get("baseColorTexture")) or image_name(material.get("emissiveTexture"))} for index, material in enumerate(document.get("materials", []))]


def extract_archive(archive: zipfile.ZipFile, staging: Path) -> None:
    for info in archive.infolist():
        if info.is_dir(): continue
        target = staging / safe_relative(info.filename)
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, target.open("wb") as destination:
            shutil.copyfileobj(source, destination)


def convert(source_root: Path, project_root: Path, blender: Path = BLENDER) -> list[dict[str, Any]]:
    helper = Path(__file__).with_name("blender_convert_to_glb.py").resolve()
    output_root = project_root / "src" / "world" / "roads" / "generated" / "converted"
    models, source_manifest = [], []
    for item in CONVERSIONS:
        with zipfile.ZipFile(source_root / item["archive"]) as archive, tempfile.TemporaryDirectory() as temporary:
            if archive.testzip(): raise ValueError(f"CRC failure: {item['archive']}")
            staging = Path(temporary)
            extract_archive(archive, staging)
            source = staging / safe_relative(item["source"])
            source_digest = sha256_bytes(source.read_bytes())
            temporary_output = staging / f"{item['id']}.glb"
            subprocess.run([str(blender), "--background", "--disable-autoexec", "--python", str(helper), "--", str(source), str(temporary_output)], check=True)
            materials = glb_materials(temporary_output)
            target = output_root / item["pack"] / f"{item['id']}.glb"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(temporary_output, target)
            models.append({"id": item["id"], "pack": item["pack"], "path": "res://" + target.relative_to(project_root).as_posix(), "materials": materials})
            source_manifest.append({"id": item["id"], "pack": item["pack"], "source": item["source"], "sha256": source_digest})
    catalog = {"models": models}
    (project_root / "src" / "world" / "roads" / "converted_catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (project_root / "src" / "world" / "roads" / "converted_source_manifest.json").write_text(json.dumps({"sources": source_manifest}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return models


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--blender", type=Path, default=BLENDER)
    args = parser.parse_args()
    print(f"Converted {len(convert(args.source_root, args.project_root, args.blender))} missing GLBs.")


if __name__ == "__main__": main()
