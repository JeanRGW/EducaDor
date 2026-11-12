#!/usr/bin/env python3
"""Offline encrypted dump packaging; does not contact or restore any database."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

CHUNK = 40_000_000
MAX_TOTAL = 600_000_000
MAX_CHUNKS = (MAX_TOTAL + CHUNK - 1) // CHUNK


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack(source, destination, recipient):
    if not re.fullmatch(r'[0-9A-F]{40}|[0-9A-F]{64}', recipient):
        raise ValueError('recipient must be a full uppercase fingerprint')
    destination = Path(destination)
    if destination.exists():
        raise ValueError('destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix='.backup-') as temp:
        root = Path(temp)
        compressed = root / 'dump.gz'
        encrypted = root / 'dump.gpg'
        with open(source, 'rb') as src, open(compressed, 'wb') as raw:
            with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0) as out:
                shutil.copyfileobj(src, out)
        subprocess.run(['gpg', '--batch', '--yes', '--trust-model', 'always', '--output', str(encrypted),
                        '--encrypt', '--recipient', recipient, str(compressed)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        size = encrypted.stat().st_size
        if not 0 < size <= MAX_TOTAL:
            raise ValueError('encrypted backup exceeds local budget or is empty')
        parts = root / 'parts'
        parts.mkdir(mode=0o700)
        entries = []
        with encrypted.open('rb') as stream:
            while data := stream.read(CHUNK):
                name = f'{len(entries):04d}.gpgpart'
                (parts / name).write_bytes(data)
                entries.append({'name': name, 'size': len(data), 'sha256': digest(data)})
        (parts / 'manifest.json').write_text(json.dumps({'version': 1, 'parts': entries}) + '\n')
        os.rename(parts, destination)


def unpack(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists():
        raise ValueError('destination already exists')
    manifest_file = source / 'manifest.json'
    if manifest_file.is_symlink() or manifest_file.stat().st_size > 100_000:
        raise ValueError('invalid manifest')
    manifest = json.loads(manifest_file.read_text())
    if set(manifest) != {'version', 'parts'} or manifest['version'] != 1:
        raise ValueError('invalid manifest')
    entries = manifest['parts']
    if not isinstance(entries, list) or not 1 <= len(entries) <= MAX_CHUNKS:
        raise ValueError('invalid part count')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix='.restore-') as temp:
        root = Path(temp)
        encrypted = root / 'dump.gpg'
        total = 0
        with encrypted.open('wb') as out:
            for index, entry in enumerate(entries):
                if not isinstance(entry, dict) or set(entry) != {'name', 'size', 'sha256'}:
                    raise ValueError('invalid part entry')
                if entry['name'] != f'{index:04d}.gpgpart' or type(entry['size']) is not int or not 0 < entry['size'] <= CHUNK:
                    raise ValueError('invalid part name or size')
                path = source / entry['name']
                if path.is_symlink() or path.stat().st_size != entry['size']:
                    raise ValueError('part size mismatch')
                data = path.read_bytes()
                total += len(data)
                if total > MAX_TOTAL or digest(data) != entry['sha256']:
                    raise ValueError('part integrity mismatch')
                out.write(data)
        compressed = root / 'dump.gz'
        subprocess.run(['gpg', '--batch', '--output', str(compressed), '--decrypt', str(encrypted)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        result = root / 'dump'
        with gzip.open(compressed, 'rb') as src, result.open('wb') as out:
            os.chmod(result, 0o600)
            shutil.copyfileobj(src, out)
        # Do not overwrite an existing destination, even if it appeared during verification.
        os.link(result, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('pack')
    create.add_argument('dump')
    create.add_argument('directory')
    create.add_argument('--recipient', required=True)
    extract = sub.add_parser('unpack')
    extract.add_argument('directory')
    extract.add_argument('dump')
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            pack(args.dump, args.directory, args.recipient)
        else:
            unpack(args.directory, args.dump)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, EOFError) as error:
        parser.exit(1, f'Archive operation failed ({type(error).__name__}).\n')


if __name__ == '__main__':
    main()
