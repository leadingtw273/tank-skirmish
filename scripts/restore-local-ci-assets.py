#!/usr/bin/env python3
"""Restore the locked local CI asset archive without publishing source art."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import time


def digest(data):
    return hashlib.sha256(data).hexdigest()


def restore(project, lock_file, archive):
    project = project.resolve()
    lock = json.loads(lock_file.read_text())
    assert lock['schemaVersion'] == 1, 'Unsupported local asset lock schema'
    rows = lock['files']
    assert rows and len(rows) == lock['fileCount'], 'Invalid locked asset count'
    names = [row['path'] for row in rows]
    assert len(names) == len(set(names)), 'Duplicate locked asset path'
    tracked = set(subprocess.check_output(
        ['git', '-C', str(project), 'ls-files', '-z']
    ).decode().rstrip('\0').split('\0'))
    for name in names:
        path = PurePosixPath(name)
        assert not path.is_absolute() and '..' not in path.parts, 'Unsafe locked path'
        assert path.as_posix() == name and name not in tracked, 'Asset path is not local-only'
        target = project / name
        assert target.resolve().is_relative_to(project), 'Asset path escapes checkout'
        assert not target.is_symlink(), 'Asset target must not be a symlink'
    assert digest(archive.read_bytes()) == lock['archiveSha256'], 'Local asset archive SHA mismatch'
    payloads = {}
    with tarfile.open(archive, 'r:*') as bundle:
        members = bundle.getmembers()
        assert len(members) == len(rows), 'Unexpected local archive member count'
        by_name = {member.name: member for member in members}
        assert len(by_name) == len(members) and set(by_name) == set(names), 'Archive allowlist mismatch'
        for row in rows:
            member = by_name[row['path']]
            assert member.isfile(), 'Local archive must contain regular files only'
            assert member.size == row['bytes'], 'Local asset size mismatch'
            stream = bundle.extractfile(member)
            assert stream is not None, 'Local asset payload missing'
            data = stream.read()
            assert digest(data) == row['sha256'], 'Local asset payload SHA mismatch'
            payloads[row['path']] = data
    # Validate every member before writing any asset into the fresh checkout.
    for name, data in payloads.items():
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        assert digest(target.read_bytes()) == digest(data), 'Restored asset readback mismatch'
    print(f'Local CI asset restore passed: {len(payloads)} locked files; source art remains local.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--lock', type=Path, default=Path('docs/assets/local-ci-assets-lock.json'))
    parser.add_argument('--archive', type=Path, default=os.environ.get('TANK_CI_ASSET_ARCHIVE'))
    parser.add_argument('--wait-seconds', type=float, default=0)
    args = parser.parse_args()
    assert args.archive is not None, 'TANK_CI_ASSET_ARCHIVE or --archive is required'
    assert 0 <= args.wait_seconds <= 120, 'Invalid local asset gate timeout'
    deadline = time.monotonic() + args.wait_seconds
    while not args.archive.is_file() and time.monotonic() < deadline:
        time.sleep(0.25)
    assert args.archive.is_file(), 'Verified local asset gate was not released'
    restore(args.project, args.lock, args.archive)


if __name__ == '__main__':
    main()
