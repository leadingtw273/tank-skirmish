#!/usr/bin/env python3
"""Safely import GLB, PNG, and licence evidence from Atomic Realm road ZIPs."""
from __future__ import annotations
import argparse, hashlib, json, struct, zipfile
from pathlib import Path, PurePosixPath
from typing import Any

PACKS = (("base", "[FREE] Modular Roads - Base.zip"), ("parking", "[PLUS] Modular Roads - Parking.zip"), ("ovaltrack", "[PLUS] Modular Roads - Ovaltrack.zip"), ("highway", "[PLUS] Modular Roads - Highway.zip"), ("dirt", "[PLUS] Modular Roads - Dirt roads.zip"), ("bridges", "[PLUS] Modular Roads - Bridges.zip"), ("signs", "[PLUS] Modular Roads - Road Signs.zip"), ("racetrack", "[PLUS] Modular Roads - Racetrack.zip"))
MODEL_SUFFIXES = {".glb", ".fbx", ".obj", ".dae"}

def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""): digest.update(chunk)
    return digest.hexdigest()

def safe_archive_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts: raise ValueError(f"unsafe ZIP entry path: {name!r}")
    return path

def should_extract(path: PurePosixPath) -> bool:
    return path.suffix.lower() in {".glb", ".png"} or "license" in path.name.lower()

def write_entry(archive: zipfile.ZipFile, info: zipfile.ZipInfo, target: Path) -> None:
    """Never overwrite: an existing source must be byte-identical to the ZIP entry."""
    payload = archive.read(info)
    if target.exists():
        if target.is_file() and sha256_path(target) == hashlib.sha256(payload).hexdigest(): return
        raise FileExistsError(f"refusing to overwrite non-matching source: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    if sha256_path(target) != hashlib.sha256(payload).hexdigest(): raise RuntimeError(f"extracted bytes differ from ZIP entry: {info.filename}")

def glb_materials(path: Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF": raise ValueError(f"invalid GLB header: {path}")
    _, version, total_length = struct.unpack_from("<4sII", raw)
    if version != 2 or total_length != len(raw): raise ValueError(f"unsupported or truncated GLB: {path}")
    json_length, chunk_type = struct.unpack_from("<I4s", raw, 12)
    if chunk_type != b"JSON": raise ValueError(f"GLB has no JSON chunk: {path}")
    document = json.loads(raw[20:20 + json_length].decode("utf-8").rstrip(" \t\r\n\0"))
    images, textures = document.get("images", []), document.get("textures", [])
    def image_name(texture_info: Any) -> str:
        if not isinstance(texture_info, dict): return ""
        texture_index = texture_info.get("index")
        if not isinstance(texture_index, int) or not 0 <= texture_index < len(textures): return ""
        image_index = textures[texture_index].get("source")
        if not isinstance(image_index, int) or not 0 <= image_index < len(images): return ""
        image = images[image_index]
        return str(image.get("name") or image.get("uri") or f"embedded_image_{image_index}")
    result = []
    for index, material in enumerate(document.get("materials", [])):
        pbr = material.get("pbrMetallicRoughness", {})
        image = image_name(pbr.get("baseColorTexture")) or image_name(material.get("emissiveTexture"))
        result.append({"name": str(material.get("name") or f"material_{index}"), "image_name": image})
    return result

def res_path(root: Path, path: Path) -> str: return "res://" + path.relative_to(root).as_posix()

def import_sources(source_root: Path, project_root: Path) -> dict[str, Any]:
    asset_root, packs, manifest_packs = project_root / "assets" / "AtomicRealmModularRoads", [], []
    for pack_id, archive_name in PACKS:
        archive_path = source_root / archive_name
        with zipfile.ZipFile(archive_path) as archive:
            corrupt = archive.testzip()
            if corrupt: raise ValueError(f"CRC failure in {archive_name}: {corrupt}")
            entries = [(info, safe_archive_path(info.filename)) for info in archive.infolist() if not info.is_dir()]
            for info, relative in entries:
                if should_extract(relative): write_entry(archive, info, asset_root / pack_id / relative)
            glb_stems = {p.stem.casefold() for _, p in entries if p.suffix.lower() == ".glb"}
            models, textures, missing = [], [], []
            for _, relative in entries:
                extracted = asset_root / pack_id / relative
                if relative.suffix.lower() == ".glb": models.append({"id": relative.stem, "path": res_path(project_root, extracted), "materials": glb_materials(extracted)})
                elif relative.suffix.lower() == ".png": textures.append({"name": relative.name, "path": res_path(project_root, extracted)})
                elif relative.suffix.lower() in MODEL_SUFFIXES and relative.stem.casefold() not in glb_stems: missing.append(relative.as_posix())
            checksum = sha256_path(archive_path)
            packs.append({"id": pack_id, "archive": archive_name, "sha256": checksum, "models": models, "textures": textures, "missing_glb": missing})
            manifest_packs.append({"id": pack_id, "archive": archive_name, "sha256": checksum, "crc_ok": True, "entries": [p.as_posix() for _, p in entries], "license_entries": [p.as_posix() for _, p in entries if "license" in p.name.lower()]})
    catalog = {"packs": packs}; asset_root.mkdir(parents=True, exist_ok=True)
    (asset_root / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (asset_root / "source-manifest.json").write_text(json.dumps({"packs": manifest_packs}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return catalog

def inventory_markdown(catalog: dict[str, Any], manifest: dict[str, Any]) -> str:
    lines = ["# Atomic Realm Modular Roads 來源盤點", "", "本報告記錄 2026-09-18 首次本機 SHA256 基準，不是官方簽章或授權驗證。每個 ZIP 已於匯入時以 `ZipFile.testzip()` 完成 CRC 檢查。", "", "| 包 | ZIP SHA256 | GLB | PNG | 缺少 GLB 的來源項目 | 授權證據 |", "| --- | --- | ---: | ---: | ---: | --- |"]
    manifest_by_id = {pack["id"]: pack for pack in manifest["packs"]}
    for pack in catalog["packs"]:
        evidence = manifest_by_id[pack["id"]]["license_entries"]
        licence = "、".join(f"`assets/AtomicRealmModularRoads/{pack['id']}/{path}`" for path in evidence) if evidence else "ZIP 內無名稱含 license 的檔案"
        lines.append(f"| {pack['id']} | `{pack['sha256']}` | {len(pack['models'])} | {len(pack['textures'])} | {len(pack['missing_glb'])} | {licence}；授權狀態未查證 |")
    return "\n".join(lines + ["", "完整 ZIP entry 清單與 CRC 結果：`assets/AtomicRealmModularRoads/source-manifest.json`。", "", "`missing_glb` 逐項清單位於 `assets/AtomicRealmModularRoads/catalog.json`；FBX/OBJ/DAE 保留在原始本機來源庫，未匯入 Godot。", ""])

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--source-root", type=Path, required=True); parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2]); args = parser.parse_args()
    catalog = import_sources(args.source_root, args.project_root)
    manifest = json.loads((args.project_root / "assets" / "AtomicRealmModularRoads" / "source-manifest.json").read_text(encoding="utf-8"))
    (args.project_root / "docs" / "maps" / "road-source-inventory.md").write_text(inventory_markdown(catalog, manifest), encoding="utf-8")
    print(f"Imported {sum(len(pack['models']) for pack in catalog['packs'])} GLBs from {len(catalog['packs'])} packs.")

if __name__ == "__main__": main()
