#!/usr/bin/env python3
"""Publish an encrypted archive to the dedicated S3 bucket. Requires exclusive operator access."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

import archive

BUCKET = 'educador-backups'
PREFIX = 'database/v1/'
RUN = re.compile(r'[0-9a-f]{32}\Z')
HASH = re.compile(r'[0-9a-f]{64}\Z')
MARKER_LIMIT = 1000


def aws(*args):
    result = subprocess.run(['aws', '--no-cli-pager', '--endpoint-url', os.environ['BACKUP_S3_ENDPOINT'],
                             's3api', *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    return result.stdout


def inventory():
    # AWS CLI automatically paginates list-objects-v2 unless explicitly disabled.
    data = json.loads(aws('list-objects-v2', '--bucket', BUCKET, '--output', 'json'))
    result = {}
    for obj in data.get('Contents', []):
        key, size, modified = obj['Key'], obj['Size'], obj['LastModified']
        if not isinstance(key, str) or type(size) is not int or size < 0 or key in result:
            raise ValueError('invalid inventory')
        result[key] = (size, modified)
    return result


def get(key, expected_size, root):
    path = root / uuid.uuid4().hex
    aws('get-object', '--bucket', BUCKET, '--key', key, str(path))
    if path.stat().st_size != expected_size:
        raise ValueError('readback size mismatch')
    data = path.read_bytes()
    path.unlink()
    return data


def put(key, path):
    aws('put-object', '--bucket', BUCKET, '--key', key, '--body', str(path),
        '--content-type', 'application/octet-stream')


def validate_manifest(data):
    if len(data) > 100_000:
        raise ValueError('manifest too large')
    manifest = json.loads(data)
    if not isinstance(manifest, dict) or set(manifest) != {'version', 'parts'} or manifest['version'] != 1:
        raise ValueError('invalid manifest')
    entries = manifest['parts']
    if not isinstance(entries, list) or not 1 <= len(entries) <= archive.MAX_CHUNKS:
        raise ValueError('invalid parts')
    total = 0
    for i, entry in enumerate(entries):
        if (not isinstance(entry, dict) or set(entry) != {'name', 'size', 'sha256'}
                or entry['name'] != f'{i:04d}.gpgpart' or type(entry['size']) is not int
                or not 0 < entry['size'] <= archive.CHUNK or not isinstance(entry['sha256'], str)
                or not HASH.fullmatch(entry['sha256'])):
            raise ValueError('invalid part')
        total += entry['size']
    if total > archive.MAX_TOTAL:
        raise ValueError('archive too large')
    return entries


def signature(secret, run, manifest_hash):
    return hmac.new(secret, (run + ':' + manifest_hash).encode(), hashlib.sha256).hexdigest()


def confirmed(run, objects, secret, root):
    base = PREFIX + run + '/'
    marker_key = base + 'complete.json'
    if marker_key not in objects or not 0 < objects[marker_key][0] <= MARKER_LIMIT:
        return None
    marker = json.loads(get(marker_key, objects[marker_key][0], root))
    if (not isinstance(marker, dict) or set(marker) != {'version', 'manifest_sha256', 'hmac_sha256'}
            or marker['version'] != 1 or not isinstance(marker['manifest_sha256'], str)
            or not HASH.fullmatch(marker['manifest_sha256']) or not isinstance(marker['hmac_sha256'], str)
            or not hmac.compare_digest(marker['hmac_sha256'], signature(secret, run, marker['manifest_sha256']))):
        return None
    mk = base + 'manifest.json'
    if mk not in objects or not 0 < objects[mk][0] <= 100_000:
        return None
    data = get(mk, objects[mk][0], root)
    if archive.digest(data) != marker['manifest_sha256']:
        return None
    entries = validate_manifest(data)
    keys = {marker_key, mk} | {base + e['name'] for e in entries}
    if {k for k in objects if k.startswith(base)} != keys:
        return None
    for entry in entries:
        key = base + entry['name']
        if objects[key][0] != entry['size'] or archive.digest(get(key, entry['size'], root)) != entry['sha256']:
            return None
    return keys


def publish(directory, budget, reserve, secret):
    directory = Path(directory)
    manifest_path = directory / 'manifest.json'
    if manifest_path.is_symlink() or manifest_path.stat().st_size > 100_000:
        raise ValueError('invalid manifest')
    manifest = manifest_path.read_bytes()
    entries = validate_manifest(manifest)
    for entry in entries:
        path = directory / entry['name']
        if path.is_symlink() or path.stat().st_size != entry['size'] or archive.digest(path.read_bytes()) != entry['sha256']:
            raise ValueError('invalid local part')
    if not 0 < budget <= 1_000_000_000 or reserve <= 0 or reserve >= budget or len(secret) < 32:
        raise ValueError('invalid budget or authentication key')
    objects = inventory()
    # Reserve is a conservative upper bound for all non-backup usage and concurrent growth.
    needed = sum(e['size'] for e in entries) + len(manifest) + MARKER_LIMIT
    if sum(size for size, _ in objects.values()) + reserve + needed > budget:
        raise ValueError('insufficient reserved storage budget')
    run = uuid.uuid4().hex
    base = PREFIX + run + '/'
    if any(key.startswith(base) for key in objects):
        raise ValueError('run collision')
    with tempfile.TemporaryDirectory(prefix='backup-publish-') as tmp:
        root = Path(tmp)
        for entry in entries:
            key = base + entry['name']
            put(key, directory / entry['name'])
            if archive.digest(get(key, entry['size'], root)) != entry['sha256']:
                raise ValueError('part readback mismatch')
        put(base + 'manifest.json', manifest_path)
        if get(base + 'manifest.json', len(manifest), root) != manifest:
            raise ValueError('manifest readback mismatch')
        marker = json.dumps({'version': 1, 'manifest_sha256': archive.digest(manifest),
                             'hmac_sha256': signature(secret, run, archive.digest(manifest))}).encode()
        marker_path = root / 'marker'
        marker_path.write_bytes(marker)
        put(base + 'complete.json', marker_path)
        if get(base + 'complete.json', len(marker), root) != marker:
            raise ValueError('marker readback mismatch')
        objects = inventory()
        if confirmed(run, objects, secret, root) is None:
            raise ValueError('published backup not confirmed')
        runs = {k[len(PREFIX):].split('/')[0] for k in objects if k.startswith(PREFIX)}
        valid = []
        for candidate in runs:
            if not RUN.fullmatch(candidate):
                continue
            try:
                keys = confirmed(candidate, objects, secret, root)
            except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError):
                continue
            if keys:
                valid.append((objects[PREFIX + candidate + '/complete.json'][1], candidate, keys))
        valid.sort(reverse=True)
        # Never prune unless the just-published run is among the three newest.
        if run not in [item[1] for item in valid[:3]]:
            raise ValueError('unexpected completion ordering')
        for _, _, keys in valid[3:]:
            # Delete marker first: interrupted deletion can never look complete.
            marker_key = next(k for k in keys if k.endswith('/complete.json'))
            for key in [marker_key] + sorted(keys - {marker_key}):
                aws('delete-object', '--bucket', BUCKET, '--key', key)


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError('expected archive directory')
        endpoint = os.environ['BACKUP_S3_ENDPOINT']
        if not re.fullmatch(r'https://[a-z0-9-]+\.storage\.supabase\.co/storage/v1/s3/?', endpoint):
            raise ValueError('invalid endpoint')
        publish(sys.argv[1], int(os.environ['BACKUP_TOTAL_BUDGET_BYTES']),
                int(os.environ['BACKUP_NON_BACKUP_RESERVE_BYTES']),
                bytes.fromhex(os.environ['BACKUP_HMAC_KEY_HEX']))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f'Backup publication failed ({type(error).__name__}).', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
