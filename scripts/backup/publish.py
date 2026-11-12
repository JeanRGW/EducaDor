#!/usr/bin/env python3
"""Experimental S3 publication. Production workflow must remain disabled."""
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
MAX_RUNS = 32
MANIFEST_LIMIT = 100_000
# Fixed allowance for list responses, error bodies and protocol overhead. Not a provider-enforced cap.
NETWORK_ALLOWANCE = 10_000_000


def aws(*args):
    result = subprocess.run(['aws', '--endpoint-url', os.environ['BACKUP_S3_ENDPOINT'],
                             's3api', *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    return result.stdout


def inventory():
    # The CLI paginates automatically. This is not a server-side response-size limit.
    data = json.loads(aws('list-objects-v2', '--bucket', BUCKET, '--output', 'json', '--page-size', '100'))
    result = {}
    for obj in data.get('Contents', []):
        key, size = obj['Key'], obj['Size']
        if not isinstance(key, str) or type(size) is not int or size < 0 or key in result:
            raise ValueError('invalid inventory')
        result[key] = size
    if len(result) > MAX_RUNS * (archive.MAX_CHUNKS + 2):
        raise ValueError('inventory exceeds supported limit')
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
    if len(data) > MANIFEST_LIMIT:
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
    """Verify previously authenticated metadata and current listed keys/sizes, not current bytes."""
    base = PREFIX + run + '/'
    marker_key = base + 'complete.json'
    if marker_key not in objects or not 0 < objects[marker_key] <= MARKER_LIMIT:
        raise ValueError('missing marker')
    marker = json.loads(get(marker_key, objects[marker_key], root))
    if (not isinstance(marker, dict) or set(marker) != {'version', 'manifest_sha256', 'hmac_sha256'}
            or marker['version'] != 1 or not isinstance(marker['manifest_sha256'], str)
            or not HASH.fullmatch(marker['manifest_sha256']) or not isinstance(marker['hmac_sha256'], str)
            or not hmac.compare_digest(marker['hmac_sha256'], signature(secret, run, marker['manifest_sha256']))):
        raise ValueError('invalid marker')
    mk = base + 'manifest.json'
    if mk not in objects or not 0 < objects[mk] <= MANIFEST_LIMIT:
        raise ValueError('missing manifest')
    data = get(mk, objects[mk], root)
    if archive.digest(data) != marker['manifest_sha256']:
        raise ValueError('manifest mismatch')
    entries = validate_manifest(data)
    keys = {marker_key, mk} | {base + e['name'] for e in entries}
    if {k for k in objects if k.startswith(base)} != keys:
        raise ValueError('unexpected objects')
    for entry in entries:
        if objects[base + entry['name']] != entry['size']:
            raise ValueError('listed part size mismatch')
    return keys


def egress_estimate(entries, manifest_size):
    # Read each new part and manifest once, marker once, then all prior metadata at maxima.
    return (sum(e['size'] for e in entries) + manifest_size + MARKER_LIMIT
            + MAX_RUNS * (MANIFEST_LIMIT + MARKER_LIMIT) + NETWORK_ALLOWANCE)


def publish(directory, budget, reserve, egress_budget, secret, attestations):
    directory = Path(directory)
    manifest_path = directory / 'manifest.json'
    if manifest_path.is_symlink() or manifest_path.stat().st_size > MANIFEST_LIMIT:
        raise ValueError('invalid manifest')
    manifest = manifest_path.read_bytes()
    entries = validate_manifest(manifest)
    for entry in entries:
        path = directory / entry['name']
        if path.is_symlink() or path.stat().st_size != entry['size'] or archive.digest(path.read_bytes()) != entry['sha256']:
            raise ValueError('invalid local part')
    if (not 0 < budget <= 1_000_000_000 or reserve <= 0 or reserve >= budget or len(secret) < 32
            or attestations != ('true', 'true')):
        raise ValueError('invalid budget, key or operator attestations')
    if egress_budget < egress_estimate(entries, len(manifest)):
        raise ValueError('insufficient egress budget')
    # This listing cannot see incomplete multipart uploads. The reserve must include them;
    # operators must independently prohibit/inspect them and all other writers.
    objects = inventory()
    needed = sum(e['size'] for e in entries) + len(manifest) + MARKER_LIMIT
    if sum(objects.values()) + reserve + needed > budget:
        raise ValueError('insufficient reserved storage budget')
    runs = set()
    for key in objects:
        if not key.startswith(PREFIX):
            raise ValueError('unknown bucket object')
        segments = key[len(PREFIX):].split('/')
        if len(segments) != 2 or not RUN.fullmatch(segments[0]):
            raise ValueError('unknown bucket object')
        runs.add(segments[0])
    if len(runs) >= MAX_RUNS:
        raise ValueError('too many prior runs')
    run = uuid.uuid4().hex
    base = PREFIX + run + '/'
    if run in runs:
        raise ValueError('run collision')
    with tempfile.TemporaryDirectory(prefix='backup-publish-') as tmp:
        root = Path(tmp)
        for prior in runs:
            confirmed(prior, objects, secret, root)
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
        after = inventory()
        expected = dict(objects)
        expected.update({base + e['name']: e['size'] for e in entries})
        expected[base + 'manifest.json'] = len(manifest)
        expected[base + 'complete.json'] = len(marker)
        if after != expected:
            raise ValueError('inventory changed during publication')
        # No automatic deletion: trusted, replay-resistant ordering is not established.


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError('expected archive directory')
        endpoint = os.environ['BACKUP_S3_ENDPOINT']
        if not re.fullmatch(r'https://[a-z0-9-]+\.storage\.supabase\.co/storage/v1/s3/?', endpoint):
            raise ValueError('invalid endpoint')
        publish(sys.argv[1], int(os.environ['BACKUP_TOTAL_BUDGET_BYTES']),
                int(os.environ['BACKUP_NON_BACKUP_RESERVE_BYTES']),
                int(os.environ['BACKUP_EGRESS_BUDGET_BYTES']),
                bytes.fromhex(os.environ['BACKUP_HMAC_KEY_HEX']),
                (os.environ.get('BACKUP_EXCLUSIVE_WRITER_ATTESTED'),
                 os.environ.get('BACKUP_MULTIPART_RESERVE_ATTESTED')))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f'Backup publication failed ({type(error).__name__}).', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
