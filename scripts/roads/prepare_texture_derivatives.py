#!/usr/bin/env python3
"""Create valid PNG derivatives for road textures whose source extension is false."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path


PSD_MAGIC = b"8BPS"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
SKIP_IMPORT = '[remap]\n\nimporter="skip"\n'


def is_psd_payload(path: Path) -> bool:
    """Return whether a nominal PNG has Photoshop's PSD file signature."""
    with path.open("rb") as source:
        return source.read(len(PSD_MAGIC)) == PSD_MAGIC


def resource_path(project_root: Path, path: Path) -> str:
    return "res://" + path.relative_to(project_root).as_posix()


def find_mislabeled_pngs(asset_root: Path) -> list[Path]:
    return sorted(path for path in asset_root.rglob("*.png") if path.is_file() and is_psd_payload(path))


def convert_psd_to_png(source: Path, target: Path, ffmpeg: str = "/usr/bin/ffmpeg") -> None:
    """Decode to a temporary PNG, verify its magic, then atomically publish it."""
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.stem}.tmp.png")
    try:
        subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-frames:v", "1", str(temporary)],
            check=True,
        )
        if temporary.read_bytes()[:len(PNG_MAGIC)] != PNG_MAGIC:
            raise ValueError(f"ffmpeg did not create a PNG: {temporary}")
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()


def write_skip_import(source: Path) -> None:
    """Keep Godot from attempting PNG import of an upstream PSD payload."""
    sidecar = source.with_name(source.name + ".import")
    if sidecar.exists():
        existing = sidecar.read_text(encoding="utf-8")
        failed_texture_import = 'importer="texture"' in existing and "valid=false" in existing
        if existing != SKIP_IMPORT and not failed_texture_import:
            raise FileExistsError(f"refusing to replace existing import configuration: {sidecar}")
    sidecar.write_text(SKIP_IMPORT, encoding="utf-8")


def prepare_derivatives(project_root: Path, ffmpeg: str = "/usr/bin/ffmpeg") -> dict[str, str]:
    asset_root = project_root / "assets" / "AtomicRealmModularRoads"
    generated_root = project_root / "src" / "world" / "roads" / "generated" / "textures"
    derivatives: dict[str, str] = {}
    for source in find_mislabeled_pngs(asset_root):
        relative = source.relative_to(asset_root)
        pack = relative.parts[0]
        target = generated_root / pack / f"{source.stem}.png"
        convert_psd_to_png(source, target, ffmpeg)
        write_skip_import(source)
        derivatives[resource_path(project_root, source)] = resource_path(project_root, target)
    manifest = project_root / "src" / "world" / "roads" / "texture_derivatives.json"
    manifest.write_text(json.dumps(derivatives, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return derivatives


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ffmpeg", default="/usr/bin/ffmpeg")
    args = parser.parse_args()
    derivatives = prepare_derivatives(args.project_root, args.ffmpeg)
    print(f"Prepared {len(derivatives)} PNG texture derivatives.")


if __name__ == "__main__":
    main()
