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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def restore(project, lock_file, archive):
    project = project.resolve()
    lock = json.loads(lock_file.read_text())
    require(lock['schemaVersion'] == 1, 'Unsupported local asset lock schema')
    rows = lock['files']
    require(rows and len(rows) == lock['fileCount'], 'Invalid locked asset count')
    names = [row['path'] for row in rows]
    require(len(names) == len(set(names)), 'Duplicate locked asset path')
    tracked = set(subprocess.check_output(
        ['git', '-C', str(project), 'ls-files', '-z']
    ).decode().rstrip('\0').split('\0'))
    for name in names:
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts, 'Unsafe locked path')
        require(path.as_posix() == name and name not in tracked, 'Asset path is not local-only')
        target = project / name
        require(target.resolve().is_relative_to(project), 'Asset path escapes checkout')
        require(not target.is_symlink(), 'Asset target must not be a symlink')
    require(digest(archive.read_bytes()) == lock['archiveSha256'], 'Local asset archive SHA mismatch')
    payloads = {}
    with tarfile.open(archive, 'r:*') as bundle:
        members = bundle.getmembers()
        require(len(members) == len(rows), 'Unexpected local archive member count')
        by_name = {member.name: member for member in members}
        require(len(by_name) == len(members) and set(by_name) == set(names), 'Archive allowlist mismatch')
        for row in rows:
            member = by_name[row['path']]
            require(member.isfile(), 'Local archive must contain regular files only')
            require(member.size == row['bytes'], 'Local asset size mismatch')
            stream = bundle.extractfile(member)
            require(stream is not None, 'Local asset payload missing')
            data = stream.read()
            require(digest(data) == row['sha256'], 'Local asset payload SHA mismatch')
            payloads[row['path']] = data
    # Validate every member before writing any asset into the fresh checkout.
    for name, data in payloads.items():
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        require(digest(target.read_bytes()) == digest(data), 'Restored asset readback mismatch')
    print(f'Local CI asset restore passed: {len(payloads)} locked files; source art remains local.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--lock', type=Path, default=Path('docs/assets/local-ci-assets-lock.json'))
    parser.add_argument('--archive', type=Path, default=os.environ.get('TANK_CI_ASSET_ARCHIVE'))
    parser.add_argument('--wait-seconds', type=float, default=0)
    args = parser.parse_args()
    require(args.archive is not None, 'TANK_CI_ASSET_ARCHIVE or --archive is required')
    require(0 <= args.wait_seconds <= 120, 'Invalid local asset gate timeout')
    deadline = time.monotonic() + args.wait_seconds
    while not args.archive.is_file() and time.monotonic() < deadline:
        time.sleep(0.25)
    require(args.archive.is_file(), 'Verified local asset gate was not released')
    restore(args.project, args.lock, args.archive)


if __name__ == '__main__':
    main()
