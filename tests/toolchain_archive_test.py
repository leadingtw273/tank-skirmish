"""Synthetic contract tests for the archive inspection adapter."""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "scripts" / "toolchain_archive.py"


class ToolchainArchiveTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.directory = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def request(self, archive: Path, archive_format: str, contract_value: dict, **extra: object):
        request = {
            "operation": "inspect",
            "archivePath": str(archive),
            "format": archive_format,
            "contract": contract_value,
            **extra,
        }
        return self.run_payload(request)

    def run_payload(self, request: object):
        return subprocess.run(
            [sys.executable, str(ADAPTER)],
            input=json.dumps(request),
            text=True,
            capture_output=True,
            cwd=ROOT,
            check=False,
        )

    def contract(self, **overrides: object) -> dict:
        return {
            "memberCount": 2,
            "topLevelDirectory": "pack",
            "exactMemberNames": ["pack/a.txt", "pack/b.txt"],
            "allowedEntryTypes": ["regular"],
            **overrides,
        }

    def assert_failure(self, result, code: str, path: str) -> None:
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(json.loads(result.stderr), {"ok": False, "code": code, "path": path})

    def make_zip(self, entries: list[tuple[str, bytes]]) -> Path:
        archive = self.directory / "fixture.zip"
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", message="Duplicate name:.*", category=UserWarning)
            with zipfile.ZipFile(archive, "w") as handle:
                for name, data in entries:
                    handle.writestr(name, data)
        return archive

    def insert_zip_nul(self, archive: Path, original: bytes, replacement: bytes) -> None:
        self.assertEqual(len(original), len(replacement))
        content = archive.read_bytes()
        self.assertGreaterEqual(content.count(original), 2)
        archive.write_bytes(content.replace(original, replacement))

    def mark_zip_encrypted(self, archive: Path) -> None:
        content = bytearray(archive.read_bytes())
        for signature, offset in [(b"PK\x03\x04", 6), (b"PK\x01\x02", 8)]:
            position = content.find(signature)
            self.assertNotEqual(position, -1)
            content[position + offset] |= 0x01
        archive.write_bytes(content)

    def make_tar(self, entries: list[tarfile.TarInfo]) -> Path:
        archive = self.directory / "fixture.tar.xz"
        with tarfile.open(archive, "w:xz") as handle:
            for item in entries:
                payload = io.BytesIO(b"x") if item.isreg() else None
                if payload is not None:
                    item.size = 1
                handle.addfile(item, payload)
        return archive

    def tar_regular(self, name: str) -> tarfile.TarInfo:
        item = tarfile.TarInfo(name)
        item.type = tarfile.REGTYPE
        return item

    def test_inspects_safe_zip_and_tar_xz(self) -> None:
        zip_result = self.request(
            self.make_zip([("pack/a.txt", b"a"), ("pack/b.txt", b"b")]),
            "zip",
            self.contract(),
        )
        self.assertEqual(zip_result.returncode, 0, zip_result.stderr)
        self.assertEqual(
            json.loads(zip_result.stdout),
            {"ok": True, "members": [
                {"path": "pack/a.txt", "type": "regular", "linkTarget": None},
                {"path": "pack/b.txt", "type": "regular", "linkTarget": None},
            ]},
        )

        directory = tarfile.TarInfo("pack")
        directory.type = tarfile.DIRTYPE
        link = tarfile.TarInfo("pack/current")
        link.type = tarfile.SYMTYPE
        link.linkname = "a.txt"
        tar_result = self.request(
            self.make_tar([directory, self.tar_regular("pack/a.txt"), link]),
            "tar.xz",
            self.contract(
                memberCount=3,
                exactMemberNames=["pack", "pack/a.txt", "pack/current"],
                allowedEntryTypes=["regular", "directory", "symlink"],
            ),
        )
        self.assertEqual(tar_result.returncode, 0, tar_result.stderr)
        self.assertEqual(
            json.loads(tar_result.stdout)["members"],
            [
                {"path": "pack", "type": "directory", "linkTarget": None},
                {"path": "pack/a.txt", "type": "regular", "linkTarget": None},
                {"path": "pack/current", "type": "symlink", "linkTarget": "a.txt"},
            ],
        )

    def test_accepts_nullable_contract_values(self) -> None:
        result = self.request(
            self.make_zip([("a.txt", b"a"), ("b.txt", b"b")]),
            "zip",
            self.contract(topLevelDirectory=None, exactMemberNames=None),
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_invalid_request_schema_and_operation_fields(self) -> None:
        archive = self.make_zip([("pack/a.txt", b"a"), ("pack/b.txt", b"b")])
        for mutation, path in [
            ({"operation": "extract"}, "operation"),
            ({"stagingRoot": "/tmp/stage"}, "stagingRoot"),
            ({"unknown": True}, "unknown"),
            ({"contract": {"memberCount": 2}}, "contract"),
            ({"contract": self.contract(exactMemberNames=[])}, "contract.exactMemberNames"),
            ({"contract": self.contract(topLevelDirectory="../pack")}, "contract.topLevelDirectory"),
            ({"contract": self.contract(exactMemberNames=["pack/a.txt", "bad\\path"])}, "contract.exactMemberNames"),
        ]:
            result = self.request(archive, "zip", self.contract(), **mutation)
            self.assert_failure(result, "request_invalid", path)

        base = {
            "operation": "inspect",
            "archivePath": str(archive),
            "format": "zip",
            "contract": self.contract(),
        }
        missing_root = dict(base)
        missing_root.pop("format")
        self.assert_failure(self.run_payload(missing_root), "request_invalid", "request")
        missing_contract = dict(base)
        missing_contract["contract"] = {key: value for key, value in self.contract().items() if key != "memberCount"}
        self.assert_failure(self.run_payload(missing_contract), "request_invalid", "contract")
        unknown_contract = dict(base)
        unknown_contract["contract"] = self.contract(extra=True)
        self.assert_failure(self.run_payload(unknown_contract), "request_invalid", "contract")

    def test_rejects_bad_zip_entries(self) -> None:
        cases = [
            (["/pack/a.txt", "pack/b.txt"], "unsafe_entry", "/pack/a.txt"),
            (["pack/../a.txt", "pack/b.txt"], "unsafe_entry", "pack/../a.txt"),
            (["pack\\a.txt", "pack/b.txt"], "unsafe_entry", "pack\\a.txt"),
            (["pack/a.txt", "pack/a.txt"], "archive_invalid", "pack/a.txt"),
        ]
        for names, code, path in cases:
            with self.subTest(names=names):
                result = self.request(self.make_zip([(name, b"x") for name in names]), "zip", self.contract())
                self.assert_failure(result, code, path)

        archive = self.make_zip([("pack/a.txt", b"x"), ("pack/b.txt", b"x")])
        self.insert_zip_nul(archive, b"pack/a.txt", b"pack/a\x00txt")
        self.assert_failure(self.request(archive, "zip", self.contract()), "unsafe_entry", "pack/a\x00txt")

        archive = self.make_zip([("pack/a.txt", b"x"), ("pack/b.txt", b"x")])
        with zipfile.ZipFile(archive, "a") as handle:
            item = zipfile.ZipInfo("pack/link")
            item.create_system = 3
            item.external_attr = (0o120777 << 16)
            handle.writestr(item, b"target")
        self.assert_failure(self.request(archive, "zip", self.contract(memberCount=3)), "archive_invalid", "pack/link")

    def test_rejects_encrypted_and_directory_zip_entries(self) -> None:
        archive = self.make_zip([("pack/a.txt", b"x"), ("pack/b.txt", b"x")])
        self.mark_zip_encrypted(archive)
        self.assert_failure(self.request(archive, "zip", self.contract()), "archive_invalid", "pack/a.txt")

        archive = self.make_zip([("pack/", b""), ("pack/a.txt", b"x")])
        self.assert_failure(
            self.request(archive, "zip", self.contract(exactMemberNames=["pack", "pack/a.txt"])),
            "unsafe_entry",
            "pack/",
        )

    def test_rejects_bad_tar_entries_and_links(self) -> None:
        for name, entry_type in [
            ("hard", tarfile.LNKTYPE),
            ("character", tarfile.CHRTYPE),
            ("block", tarfile.BLKTYPE),
            ("fifo", tarfile.FIFOTYPE),
            ("socket", b"s"),
            ("sparse", tarfile.GNUTYPE_SPARSE),
        ]:
            with self.subTest(entry_type=name):
                bad_type = tarfile.TarInfo(f"pack/{name}")
                bad_type.type = entry_type
                result = self.request(
                    self.make_tar([self.tar_regular("pack/a.txt"), bad_type]), "tar.xz", self.contract()
                )
                self.assert_failure(result, "archive_invalid", f"pack/{name}")

        for mode in [0o4755, 0o2755]:
            with self.subTest(mode=mode):
                elevated = self.tar_regular("pack/a.txt")
                elevated.mode = mode
                result = self.request(
                    self.make_tar([elevated, self.tar_regular("pack/b.txt")]), "tar.xz", self.contract()
                )
                self.assert_failure(result, "archive_invalid", "pack/a.txt")

        duplicate = self.request(
            self.make_tar([self.tar_regular("pack/a.txt"), self.tar_regular("pack/a.txt")]),
            "tar.xz",
            self.contract(),
        )
        self.assert_failure(duplicate, "archive_invalid", "pack/a.txt")
        unsafe = self.request(
            self.make_tar([self.tar_regular("pack/../a.txt"), self.tar_regular("pack/b.txt")]),
            "tar.xz",
            self.contract(),
        )
        self.assert_failure(unsafe, "unsafe_entry", "pack/../a.txt")

        for target in ["/outside", "../../outside", "bad\\target", "bad\x00target"]:
            with self.subTest(target=target):
                link = tarfile.TarInfo("pack/link")
                link.type = tarfile.SYMTYPE
                link.linkname = target
                result = self.request(
                    self.make_tar([self.tar_regular("pack/a.txt"), link]),
                    "tar.xz",
                    self.contract(
                        exactMemberNames=["pack/a.txt", "pack/link"],
                        allowedEntryTypes=["regular", "symlink"],
                    ),
                )
                self.assert_failure(result, "unsafe_entry", "pack/link")

        link = tarfile.TarInfo("pack/link")
        link.type = tarfile.SYMTYPE
        link.linkname = "a.txt"
        result = self.request(
            self.make_tar([link, self.tar_regular("pack/link/child")]),
            "tar.xz",
            self.contract(
                exactMemberNames=["pack/link", "pack/link/child"],
                allowedEntryTypes=["regular", "symlink"],
            ),
        )
        self.assert_failure(result, "unsafe_entry", "pack/link/child")

    def test_rejects_contract_mismatches_and_io_failures(self) -> None:
        archive = self.make_zip([("pack/a.txt", b"a"), ("pack/b.txt", b"b")])
        for contract, path in [
            (self.contract(memberCount=1), "memberCount"),
            (self.contract(topLevelDirectory=None), "topLevelDirectory"),
            (self.contract(exactMemberNames=["pack/a.txt", "pack/c.txt"]), "exactMemberNames"),
            (self.contract(allowedEntryTypes=[]), "contract.allowedEntryTypes"),
            (self.contract(allowedEntryTypes=["regular", "symlink"]), "allowedEntryTypes"),
        ]:
            with self.subTest(contract=contract):
                expected_code = "request_invalid" if not contract["allowedEntryTypes"] else "contract_mismatch"
                self.assert_failure(self.request(archive, "zip", contract), expected_code, path)

        self.assert_failure(
            self.request(self.directory / "missing.zip", "zip", self.contract()),
            "io_error",
            str(self.directory / "missing.zip"),
        )
        self.assert_failure(
            self.request(self.directory / "missing.tar.xz", "tar.xz", self.contract()),
            "io_error",
            str(self.directory / "missing.tar.xz"),
        )
        broken = self.directory / "broken.zip"
        broken.write_bytes(b"not a zip")
        self.assert_failure(self.request(broken, "zip", self.contract()), "archive_invalid", "archivePath")


if __name__ == "__main__":
    unittest.main()
