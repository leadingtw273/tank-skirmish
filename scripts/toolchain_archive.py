#!/usr/bin/env python3
"""Inspect ZIP and TAR.XZ archives without extracting their contents."""

from __future__ import annotations

import json
import lzma
import posixpath
import stat
import sys
import tarfile
import zipfile
from pathlib import Path
from typing import Any, NoReturn


REQUEST_FIELDS = {"operation", "archivePath", "format", "contract"}
CONTRACT_FIELDS = {
    "memberCount",
    "topLevelDirectory",
    "exactMemberNames",
    "allowedEntryTypes",
}
FORMAT_TYPES = {
    "zip": {"regular"},
    "tar.xz": {"regular", "directory", "symlink"},
}


class InspectionFailure(Exception):
    def __init__(self, code: str, path: str) -> None:
        self.code = code
        self.path = path


def fail(code: str, path: str) -> NoReturn:
    raise InspectionFailure(code, path)


def is_plain_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def safe_member_path(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        fail("request_invalid", field)
    if "\x00" in value or "\\" in value or value.startswith("/"):
        fail("request_invalid", field)
    if any(segment in {"", ".", ".."} for segment in value.split("/")):
        fail("request_invalid", field)
    return value


def validate_contract(value: Any, archive_format: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != CONTRACT_FIELDS:
        fail("request_invalid", "contract")
    member_count = value["memberCount"]
    if not is_plain_int(member_count) or member_count < 0:
        fail("request_invalid", "contract.memberCount")
    top_level = value["topLevelDirectory"]
    if top_level is not None:
        if not isinstance(top_level, str) or not top_level or any(
            character in top_level for character in ("/", "\\", "\x00")
        ) or top_level in {".", ".."}:
            fail("request_invalid", "contract.topLevelDirectory")
    exact_names = value["exactMemberNames"]
    if exact_names is not None:
        if not isinstance(exact_names, list) or not exact_names:
            fail("request_invalid", "contract.exactMemberNames")
        for name in exact_names:
            safe_member_path(name, "contract.exactMemberNames")
        if len(set(exact_names)) != len(exact_names):
            fail("request_invalid", "contract.exactMemberNames")
    allowed_types = value["allowedEntryTypes"]
    if not isinstance(allowed_types, list) or not allowed_types:
        fail("request_invalid", "contract.allowedEntryTypes")
    if any(not isinstance(entry, str) for entry in allowed_types) or len(set(allowed_types)) != len(allowed_types):
        fail("request_invalid", "contract.allowedEntryTypes")
    if not set(allowed_types).issubset(FORMAT_TYPES[archive_format]):
        fail("contract_mismatch", "allowedEntryTypes")
    return value


def validate_request(value: Any) -> tuple[Path, str, dict[str, Any]]:
    if not isinstance(value, dict) or set(value) != REQUEST_FIELDS:
        if isinstance(value, dict):
            unknown = next((key for key in value if key not in REQUEST_FIELDS), "request")
            fail("request_invalid", unknown)
        fail("request_invalid", "request")
    if value["operation"] != "inspect":
        fail("request_invalid", "operation")
    if not isinstance(value["archivePath"], str) or not value["archivePath"] or "\x00" in value["archivePath"]:
        fail("request_invalid", "archivePath")
    archive_format = value["format"]
    if not isinstance(archive_format, str) or archive_format not in FORMAT_TYPES:
        fail("request_invalid", "format")
    return Path(value["archivePath"]), archive_format, validate_contract(value["contract"], archive_format)


def archive_member_path(value: str) -> str:
    if not value or "\x00" in value or "\\" in value or value.startswith("/"):
        fail("unsafe_entry", value)
    if any(segment in {"", ".", ".."} for segment in value.split("/")):
        fail("unsafe_entry", value)
    return value


def validate_link_target(member_path: str, target: str) -> None:
    if not target or "\x00" in target or "\\" in target or target.startswith("/"):
        fail("unsafe_entry", member_path)
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(member_path), target))
    if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
        fail("unsafe_entry", member_path)


def inspect_zip(archive: Path) -> list[dict[str, Any]]:
    try:
        with zipfile.ZipFile(archive, "r") as handle:
            result: list[dict[str, Any]] = []
            seen: set[str] = set()
            for item in handle.infolist():
                path = archive_member_path(item.orig_filename)
                if item.flag_bits & 0x1:
                    fail("archive_invalid", path)
                if path in seen:
                    fail("archive_invalid", path)
                seen.add(path)
                mode = item.external_attr >> 16
                file_type = stat.S_IFMT(mode)
                if item.is_dir() or (file_type not in {0, stat.S_IFREG}):
                    fail("archive_invalid", path)
                result.append({"path": path, "type": "regular", "linkTarget": None})
            return result
    except InspectionFailure:
        raise
    except (zipfile.BadZipFile, zipfile.LargeZipFile):
        fail("archive_invalid", "archivePath")
    except OSError:
        fail("io_error", str(archive))


def is_sparse(item: tarfile.TarInfo) -> bool:
    method = getattr(item, "issparse", None)
    if callable(method) and method():
        return True
    return bool(getattr(item, "sparse", None))


def raw_tar_name(field: bytes) -> str:
    return field.rstrip(b"\0").decode("utf-8", "surrogateescape")


def reject_embedded_tar_nuls(archive: Path) -> None:
    """Reject text header fields containing data after a NUL terminator.

    ``tarfile`` intentionally truncates those fields before exposing TarInfo,
    so this lightweight header pass closes that ambiguity without extraction.
    """
    try:
        with lzma.open(archive, "rb") as stream:
            while True:
                header = stream.read(tarfile.BLOCKSIZE)
                if not header:
                    return
                if len(header) != tarfile.BLOCKSIZE:
                    fail("archive_invalid", "archivePath")
                if header == b"\0" * tarfile.BLOCKSIZE:
                    return
                name = header[0:100]
                prefix = header[345:500]
                link = header[157:257]
                display_path = raw_tar_name(prefix) + ("/" if prefix.rstrip(b"\0") else "") + raw_tar_name(name)
                for field in (name, prefix, link):
                    terminator = field.find(b"\0")
                    if terminator >= 0 and any(field[terminator + 1 :]):
                        fail("unsafe_entry", display_path)
                size_field = header[124:136].rstrip(b"\0 ")
                try:
                    size = int(size_field or b"0", 8)
                except ValueError:
                    fail("archive_invalid", "archivePath")
                skipped = stream.read((size + tarfile.BLOCKSIZE - 1) // tarfile.BLOCKSIZE * tarfile.BLOCKSIZE)
                if len(skipped) != (size + tarfile.BLOCKSIZE - 1) // tarfile.BLOCKSIZE * tarfile.BLOCKSIZE:
                    fail("archive_invalid", "archivePath")
    except InspectionFailure:
        raise
    except OSError:
        raise
    except lzma.LZMAError:
        fail("archive_invalid", "archivePath")


def inspect_tar_xz(archive: Path) -> list[dict[str, Any]]:
    try:
        reject_embedded_tar_nuls(archive)
        with tarfile.open(archive, "r:xz") as handle:
            result: list[dict[str, Any]] = []
            seen: set[str] = set()
            symlinks: set[str] = set()
            for item in handle.getmembers():
                path = archive_member_path(item.name.rstrip("/") if item.isdir() else item.name)
                if path in seen:
                    fail("archive_invalid", path)
                seen.add(path)
                if is_sparse(item) or item.mode & 0o6000:
                    fail("archive_invalid", path)
                if item.isreg():
                    entry_type, target = "regular", None
                elif item.isdir():
                    entry_type, target = "directory", None
                elif item.issym():
                    entry_type, target = "symlink", item.linkname
                    validate_link_target(path, target)
                    symlinks.add(path)
                else:
                    fail("archive_invalid", path)
                result.append({"path": path, "type": entry_type, "linkTarget": target})
            for item in result:
                if any(item["path"].startswith(link + "/") for link in symlinks):
                    fail("unsafe_entry", item["path"])
            return result
    except InspectionFailure:
        raise
    except tarfile.TarError:
        fail("archive_invalid", "archivePath")
    except OSError:
        fail("io_error", str(archive))


def inferred_top_level(members: list[dict[str, Any]]) -> str | None:
    first_segments = {member["path"].split("/", 1)[0] for member in members}
    if len(first_segments) != 1:
        return None
    candidate = next(iter(first_segments))
    if any(member["path"].startswith(candidate + "/") for member in members):
        return candidate
    return candidate if any(member["path"] == candidate and member["type"] == "directory" for member in members) else None


def validate_members(members: list[dict[str, Any]], contract: dict[str, Any]) -> None:
    if len(members) != contract["memberCount"]:
        fail("contract_mismatch", "memberCount")
    if inferred_top_level(members) != contract["topLevelDirectory"]:
        fail("contract_mismatch", "topLevelDirectory")
    names = [member["path"] for member in members]
    if contract["exactMemberNames"] is not None and names != contract["exactMemberNames"]:
        fail("contract_mismatch", "exactMemberNames")
    allowed_types = set(contract["allowedEntryTypes"])
    for member in members:
        if member["type"] not in allowed_types:
            fail("contract_mismatch", member["path"])


def main() -> int:
    try:
        try:
            request = json.load(sys.stdin)
        except (json.JSONDecodeError, OSError):
            fail("request_invalid", "request")
        archive, archive_format, contract = validate_request(request)
        members = inspect_zip(archive) if archive_format == "zip" else inspect_tar_xz(archive)
        validate_members(members, contract)
        print(json.dumps({"ok": True, "members": members}, separators=(",", ":")))
        return 0
    except InspectionFailure as error:
        print(json.dumps({"ok": False, "code": error.code, "path": error.path}, separators=(",", ":")), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
