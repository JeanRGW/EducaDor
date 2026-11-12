#!/usr/bin/env python3
"""Offline authenticated encrypted dump packaging; never contacts a database."""
import argparse
import ctypes
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile

CHUNK = 40_000_000
MAX_TOTAL = 600_000_000
MAX_PLAIN = 600_000_000
MAX_COMPRESSED = 600_000_000
MAX_CHUNKS = (MAX_TOTAL + CHUNK - 1) // CHUNK
BLOCK = 65536


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fingerprint(value):
    if not re.fullmatch(r'[0-9A-F]{40}|[0-9A-F]{64}', value):
        raise ValueError('expected a full uppercase fingerprint')
    return value


def directory(path):
    """Walk every component using pinned directory descriptors, never following links."""
    path = os.path.abspath(os.fspath(path))
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for component in path.split('/'):
            if not component:
                continue
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def regular_at(parent, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=parent)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise ValueError('not a regular file')
    return os.fdopen(fd, 'rb')


def copy_bounded(src, out, limit):
    total = 0
    while True:
        data = src.read(min(BLOCK, limit - total + 1))
        if not data:
            return total
        total += len(data)
        if total > limit:
            raise ValueError('size limit exceeded')
        out.write(data)


class BoundedWriter:
    def __init__(self, stream, limit):
        self.stream, self.limit, self.total = stream, limit, 0

    def write(self, data):
        self.total += len(data)
        if self.total > self.limit:
            raise ValueError('size limit exceeded')
        return self.stream.write(data)

    def flush(self):
        self.stream.flush()


def read_bounded(parent, name, limit):
    from io import BytesIO
    out = BytesIO()
    with regular_at(parent, name) as src:
        copy_bounded(src, out, limit)
    return out.getvalue()


def run_output(args, out, limit):
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        copy_bounded(process.stdout, out, limit)
        if process.wait() != 0:
            raise subprocess.CalledProcessError(process.returncode, args)
    except BaseException:
        process.kill()
        process.wait()
        raise
    finally:
        process.stdout.close()


def no_replace(src, dst, parent_fd):
    # Linux renameat2 is atomic for directories as well as regular files.
    libc = ctypes.CDLL(None, use_errno=True)
    result = libc.renameat2(-100, os.fsencode(src), parent_fd, os.fsencode(dst), 1)
    if result:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def paths(destination):
    destination = Path(destination).absolute()
    if destination.name in ('', '.', '..'):
        raise ValueError('invalid destination')
    fd = directory(destination.parent)
    return fd, destination.name


def pack(source, destination, recipient, signer):
    fingerprint(recipient)
    fingerprint(signer)
    source = Path(source).absolute()
    source_fd = directory(source.parent)
    try:
        parent, name = paths(destination)
        try:
            # /proc pins the already verified parent even if its pathname is swapped.
            with tempfile.TemporaryDirectory(dir=f'/proc/{os.getpid()}/fd/{parent}', prefix='.backup-') as temp:
                root = Path(temp)
                compressed = root / 'dump.gz'
                with regular_at(source_fd, source.name) as src, compressed.open('wb') as raw:
                    with gzip.GzipFile(fileobj=BoundedWriter(raw, MAX_COMPRESSED), mode='wb', mtime=0) as out:
                        copy_bounded(src, out, MAX_PLAIN)
                if compressed.stat().st_size > MAX_COMPRESSED:
                    raise ValueError('compressed backup exceeds limit')
                encrypted = root / 'dump.gpg'
                with encrypted.open('wb') as out:
                    run_output(['gpg', '--no-options', '--batch', '--no-encrypt-to', '--trust-model', 'always', '--output', '-', '--encrypt', '--recipient', recipient, str(compressed)], out, MAX_TOTAL)
                parts = root / 'parts'
                parts.mkdir(mode=0o700)
                entries = []
                with encrypted.open('rb') as stream:
                    while data := stream.read(CHUNK):
                        name_part = f'{len(entries):04d}.gpgpart'
                        (parts / name_part).write_bytes(data)
                        entries.append({'name': name_part, 'size': len(data), 'sha256': digest(data)})
                if not entries:
                    raise ValueError('empty ciphertext')
                manifest = parts / 'manifest.json'
                manifest.write_text(json.dumps({'version': 2, 'parts': entries}, separators=(',', ':')) + '\n')
                with (parts / 'manifest.sig').open('wb') as out:
                    run_output(['gpg', '--batch', '--local-user', signer + '!', '--output', '-', '--detach-sign', str(manifest)], out, 65536)
                no_replace(parts, name, parent)
        finally:
            os.close(parent)
    finally:
        os.close(source_fd)


def unpack(source, destination, signer):
    fingerprint(signer)
    source_fd = directory(source)
    try:
        parent, name = paths(destination)
        try:
            with tempfile.TemporaryDirectory(dir=f'/proc/{os.getpid()}/fd/{parent}', prefix='.restore-') as temp:
                root = Path(temp)
                manifest_data = read_bounded(source_fd, 'manifest.json', 100000)
                signature = read_bounded(source_fd, 'manifest.sig', 65536)
                manifest_path, signature_path = root / 'manifest', root / 'signature'
                manifest_path.write_bytes(manifest_data)
                signature_path.write_bytes(signature)
                from io import BytesIO
                status = BytesIO()
                run_output(['gpg', '--batch', '--status-fd', '1', '--verify', str(signature_path), str(manifest_path)], status, 65536)
                valid = [line.split() for line in status.getvalue().decode('ascii').splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
                if len(valid) != 1 or valid[0][-1] != signer:
                    raise ValueError('untrusted signer')
                manifest = json.loads(manifest_data)
                if not isinstance(manifest, dict) or set(manifest) != {'version', 'parts'} or manifest['version'] != 2:
                    raise ValueError('invalid manifest')
                entries = manifest['parts']
                if not isinstance(entries, list) or not 1 <= len(entries) <= MAX_CHUNKS:
                    raise ValueError('invalid part count')
                encrypted = root / 'dump.gpg'
                total = 0
                with encrypted.open('wb') as out:
                    for index, entry in enumerate(entries):
                        if not isinstance(entry, dict) or set(entry) != {'name', 'size', 'sha256'}:
                            raise ValueError('invalid part entry')
                        size = entry['size']
                        if entry['name'] != f'{index:04d}.gpgpart' or type(size) is not int or not 0 < size <= CHUNK or not isinstance(entry['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', entry['sha256']):
                            raise ValueError('invalid part metadata')
                        total += size
                        if total > MAX_TOTAL:
                            raise ValueError('ciphertext exceeds limit')
                        data = read_bounded(source_fd, entry['name'], size)
                        if len(data) != size or digest(data) != entry['sha256']:
                            raise ValueError('part integrity mismatch')
                        out.write(data)
                compressed = root / 'dump.gz'
                with compressed.open('wb') as out:
                    run_output(['gpg', '--batch', '--decrypt', str(encrypted)], out, MAX_COMPRESSED)
                result = root / 'dump'
                with gzip.open(compressed, 'rb') as src, result.open('wb') as out:
                    copy_bounded(src, out, MAX_PLAIN)
                os.chmod(result, 0o600)
                no_replace(result, name, parent)
        finally:
            os.close(parent)
    finally:
        os.close(source_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('pack')
    create.add_argument('dump')
    create.add_argument('directory')
    create.add_argument('--recipient', required=True)
    create.add_argument('--signer', required=True)
    extract = sub.add_parser('unpack')
    extract.add_argument('directory')
    extract.add_argument('dump')
    extract.add_argument('--signer', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            pack(args.dump, args.directory, args.recipient, args.signer)
        else:
            unpack(args.directory, args.dump, args.signer)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, EOFError) as error:
        parser.exit(1, f'Archive operation failed ({type(error).__name__}).\n')


if __name__ == '__main__':
    main()
