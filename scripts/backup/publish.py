#!/usr/bin/env python3
"""Experimental S3 publication. Production workflow must remain disabled."""
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import resource
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
SIGNATURE_LIMIT = 65_536
# Fixed allowance for list responses, error bodies and protocol overhead. Not a provider-enforced cap.
NETWORK_ALLOWANCE = 10_000_000


CLI_ENV = ('PATH', 'HOME', 'AWS_CONFIG_FILE', 'AWS_SHARED_CREDENTIALS_FILE',
           'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION',
           'AWS_EC2_METADATA_DISABLED', 'AWS_MAX_ATTEMPTS', 'AWS_RETRY_MODE',
           'AWS_PAGER', 'NO_PROXY', 'no_proxy', 'SSL_CERT_FILE', 'SSL_CERT_DIR')
# Never echoed even when the CLI fails; subprocesses also do not inherit these.
SECRET_ENV = ('BACKUP_DATABASE_URL', 'BACKUP_SIGNING_PRIVATE_KEY', 'BACKUP_HMAC_KEY_HEX',
              'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'BACKUP_PUBLIC_KEY',
              'BACKUP_SIGNING_PUBLIC_KEY')


def diagnose(errors):
    """Best-effort bounded CLI stderr with known secret values removed."""
    errors.seek(0)
    text = errors.read(4096).decode('utf-8', 'replace')
    for name in SECRET_ENV:
        value = os.environ.get(name)
        if value:
            text = text.replace(value, '[redacted]')
    print('AWS CLI diagnostic (truncated):\n' + text, file=sys.stderr)


def aws(*args):
    # Bound CLI output and downloaded files locally; this is not a network traffic cap.
    def limit_files():
        resource.setrlimit(resource.RLIMIT_FSIZE, (archive.CHUNK + 1_000_000, archive.CHUNK + 1_000_000))
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        try:
            subprocess.run(['aws', '--endpoint-url', os.environ['BACKUP_S3_ENDPOINT'],
                            's3api', *args], stdout=output, stderr=errors,
                           check=True, preexec_fn=limit_files,
                           env={k: os.environ[k] for k in CLI_ENV if k in os.environ})
        except subprocess.CalledProcessError:
            diagnose(errors)
            raise
        output.seek(0)
        data = output.read(1_000_001)
        if len(data) > 1_000_000:
            raise ValueError('CLI output exceeds limit')
        return data


def inventory():
    # The CLI paginates automatically. This is not a server-side response-size limit.
    data = json.loads(aws('list-objects-v2', '--bucket', BUCKET, '--output', 'json', '--page-size', '100'))
    result = {}
    for obj in data.get('Contents', []):
        key, size = obj['Key'], obj['Size']
        if not isinstance(key, str) or type(size) is not int or size < 0 or key in result:
            raise ValueError('invalid inventory')
        result[key] = size
    if len(result) > MAX_RUNS * (archive.MAX_CHUNKS + 3):
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
    if not isinstance(manifest, dict) or set(manifest) != {'version', 'parts'} or manifest['version'] != 2:
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


def signature(secret, run, manifest_hash, signature_hash):
    return hmac.new(secret, (run + ':' + manifest_hash + ':' + signature_hash).encode(), hashlib.sha256).hexdigest()


def marker_signature(secret, marker):
    body = {k: v for k, v in marker.items() if k != 'hmac_sha256'}
    return hmac.new(secret, json.dumps(body, sort_keys=True, separators=(',', ':')).encode(), hashlib.sha256).hexdigest()


def confirmed(run, objects, secret, signer, root, *, require_v3=False):
    """Verify metadata and listed keys/sizes; caller must verify part bytes."""
    base = PREFIX + run + '/'
    marker_key = base + 'complete.json'
    if marker_key not in objects or not 0 < objects[marker_key] <= MARKER_LIMIT:
        raise ValueError('missing marker')
    marker = json.loads(get(marker_key, objects[marker_key], root))
    if not isinstance(marker, dict):
        raise ValueError('invalid marker')
    common = {'version', 'manifest_sha256', 'signature_sha256', 'hmac_sha256'}
    if marker.get('version') == 3 and set(marker) == common | {'run_id', 'created_utc'}:
        if marker['run_id'] != run or not isinstance(marker['created_utc'], str):
            raise ValueError('invalid marker identity')
        try:
            timestamp = datetime.strptime(marker['created_utc'], '%Y-%m-%dT%H:%M:%S.%fZ')
            if timestamp.strftime('%Y-%m-%dT%H:%M:%S.%fZ') != marker['created_utc']:
                raise ValueError('noncanonical timestamp')
        except ValueError as error:
            raise ValueError('invalid marker time') from error
        expected_hmac = marker_signature(secret, marker)
    elif not require_v3 and marker.get('version') == 2 and set(marker) == common:
        expected_hmac = signature(secret, run, marker.get('manifest_sha256', ''), marker.get('signature_sha256', ''))
    else:
        raise ValueError('unsupported marker')
    if (not isinstance(marker['manifest_sha256'], str) or not HASH.fullmatch(marker['manifest_sha256'])
            or not isinstance(marker['signature_sha256'], str) or not HASH.fullmatch(marker['signature_sha256'])
            or not isinstance(marker['hmac_sha256'], str)
            or not hmac.compare_digest(marker['hmac_sha256'], expected_hmac)):
        raise ValueError('invalid marker')
    mk = base + 'manifest.json'
    if mk not in objects or not 0 < objects[mk] <= MANIFEST_LIMIT:
        raise ValueError('missing manifest')
    data = get(mk, objects[mk], root)
    if archive.digest(data) != marker['manifest_sha256']:
        raise ValueError('manifest mismatch')
    sk = base + 'manifest.sig'
    if sk not in objects or not 0 < objects[sk] <= SIGNATURE_LIMIT:
        raise ValueError('missing signature')
    sig = get(sk, objects[sk], root)
    if archive.digest(sig) != marker['signature_sha256']:
        raise ValueError('signature mismatch')
    archive.verify_signature(data, sig, signer, root)
    entries = validate_manifest(data)
    keys = {marker_key, mk, sk} | {base + e['name'] for e in entries}
    if {k for k in objects if k.startswith(base)} != keys:
        raise ValueError('unexpected objects')
    for entry in entries:
        if objects[base + entry['name']] != entry['size']:
            raise ValueError('listed part size mismatch')
    return (entries, marker['created_utc']) if require_v3 else entries


def egress_estimate(entries, manifest_size, signature_size=SIGNATURE_LIMIT, prior_bytes=0):
    # Every prior object is read once; the storage allocation bounds their combined size.
    return (sum(e['size'] for e in entries) + manifest_size + signature_size + MARKER_LIMIT
            + prior_bytes + NETWORK_ALLOWANCE)


def survivors_for(times, daily, weekly):
    if daily < 1 or weekly < 1 or daily > MAX_RUNS or weekly > MAX_RUNS:
        raise ValueError('invalid retention')
    days, weeks, survivors = set(), set(), set()
    for run in sorted(times, key=times.get, reverse=True):
        timestamp = datetime.strptime(times[run], '%Y-%m-%dT%H:%M:%S.%fZ')
        day, week = timestamp.date(), timestamp.isocalendar()[:2]
        if day not in days and len(days) < daily:
            days.add(day)
            survivors.add(run)
        if week not in weeks and len(weeks) < weekly:
            weeks.add(week)
            survivors.add(run)
    return survivors


def verify_parts(run, entries, root):
    for entry in entries:
        if archive.digest(get(PREFIX + run + '/' + entry['name'], entry['size'], root)) != entry['sha256']:
            raise ValueError('prior part mismatch')


def publish(directory, budget, reserve, egress_budget, secret, attestations, signer, daily=7, weekly=4):
    directory = Path(directory)
    manifest_path = directory / 'manifest.json'
    if manifest_path.is_symlink() or manifest_path.stat().st_size > MANIFEST_LIMIT:
        raise ValueError('invalid manifest')
    manifest = manifest_path.read_bytes()
    entries = validate_manifest(manifest)
    sig_path = directory / 'manifest.sig'
    if sig_path.is_symlink() or not 0 < sig_path.stat().st_size <= SIGNATURE_LIMIT:
        raise ValueError('invalid signature')
    sig = sig_path.read_bytes()
    with tempfile.TemporaryDirectory(prefix='backup-verify-') as tmp:
        archive.verify_signature(manifest, sig, signer, Path(tmp))
    for entry in entries:
        path = directory / entry['name']
        if path.is_symlink() or path.stat().st_size != entry['size'] or archive.digest(path.read_bytes()) != entry['sha256']:
            raise ValueError('invalid local part')
    survivors_for({}, daily, weekly)
    if (not 0 < budget <= 9_000_000_000 or reserve <= 0 or reserve >= budget or len(secret) < 32
            or attestations != ('true', 'true', 'true')):
        raise ValueError('invalid budget, key or operator attestations')
    needed = sum(e['size'] for e in entries) + len(manifest) + len(sig) + MARKER_LIMIT
    if needed + reserve > budget:
        raise ValueError('insufficient reserved storage budget')
    metadata = MAX_RUNS * (MARKER_LIMIT + MANIFEST_LIMIT + SIGNATURE_LIMIT)
    if egress_budget < (needed + min(archive.MAX_TOTAL, budget - reserve - needed)
                        + 2 * metadata + 2 * NETWORK_ALLOWANCE):
        raise ValueError('insufficient egress budget')
    # This listing cannot see incomplete multipart uploads. The reserve must include them;
    # operators must independently prohibit/inspect them and all other writers.
    objects = inventory()
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
        # Authenticate every candidate before selecting retention; only the newest
        # previous archive is read in full on this path.
        times, prior_entries = {}, {}
        for previous in sorted(runs):
            prior_entries[previous], times[previous] = confirmed(previous, objects, secret, signer, root, require_v3=True)
        if times:
            newest_previous = max(times, key=times.get)
            verify_parts(newest_previous, prior_entries[newest_previous], root)
        created = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        if len(set(times.values())) != len(times) or any(t >= created for t in times.values()):
            raise ValueError('ambiguous or non-monotonic creation time')
        if inventory() != objects:
            raise ValueError('inventory changed during verification')
        for entry in entries:
            key = base + entry['name']
            put(key, directory / entry['name'])
            if archive.digest(get(key, entry['size'], root)) != entry['sha256']:
                raise ValueError('part readback mismatch')
        put(base + 'manifest.json', manifest_path)
        if get(base + 'manifest.json', len(manifest), root) != manifest:
            raise ValueError('manifest readback mismatch')
        put(base + 'manifest.sig', sig_path)
        if get(base + 'manifest.sig', len(sig), root) != sig:
            raise ValueError('signature readback mismatch')
        marker_data = {'version': 3, 'run_id': run, 'created_utc': created,
                       'manifest_sha256': archive.digest(manifest), 'signature_sha256': archive.digest(sig)}
        marker_data['hmac_sha256'] = marker_signature(secret, marker_data)
        marker = json.dumps(marker_data).encode()
        marker_path = root / 'marker'
        marker_path.write_bytes(marker)
        put(base + 'complete.json', marker_path)
        if get(base + 'complete.json', len(marker), root) != marker:
            raise ValueError('marker readback mismatch')
        after = inventory()
        expected = dict(objects)
        expected.update({base + e['name']: e['size'] for e in entries})
        expected[base + 'manifest.json'] = len(manifest)
        expected[base + 'manifest.sig'] = len(sig)
        expected[base + 'complete.json'] = len(marker)
        if after != expected:
            raise ValueError('inventory changed during publication')
        # Stateless ordering is safe only under the separately attested no-rollback model.
        all_times = dict(times, **{run: created})
        survivors = {run} | survivors_for(all_times, daily, weekly)
        if times:
            survivors.add(newest_previous)
        # Reauthenticate deletion candidates before any deletion.
        for old in sorted(runs - survivors):
            _, verified_time = confirmed(old, expected, secret, signer, root, require_v3=True)
            if verified_time != times[old]:
                raise ValueError('marker changed before pruning')
        if inventory() != expected:
            raise ValueError('inventory changed before pruning')
        # Delete only known obsolete keys. Interruption leaves unknown/incomplete runs,
        # which block the next publication; never target any survivor.
        for old in sorted(runs - survivors, key=times.get):
            old_base = PREFIX + old + '/'
            keys = sorted(k for k in expected if k.startswith(old_base))
            # Remove the marker first so an interrupted prune reads as an
            # obviously incomplete run instead of a corrupt candidate.
            keys.sort(key=lambda k: not k.endswith('/complete.json'))
            for key in keys:
                if inventory() != expected:
                    raise ValueError('inventory changed during pruning')
                aws('delete-object', '--bucket', BUCKET, '--key', key)
                del expected[key]
                if inventory() != expected:
                    raise ValueError('inventory changed after deletion')


def audit(egress_budget, secret, signer):
    if len(secret) < 32:
        raise ValueError('invalid key')
    if egress_budget < 2 * NETWORK_ALLOWANCE:
        raise ValueError('insufficient egress budget')
    objects = inventory()
    if egress_budget < sum(objects.values()) + 2 * NETWORK_ALLOWANCE:
        raise ValueError('insufficient egress budget')
    runs = set()
    for key in objects:
        if not key.startswith(PREFIX):
            raise ValueError('unknown bucket object')
        segments = key[len(PREFIX):].split('/')
        if len(segments) != 2 or not RUN.fullmatch(segments[0]):
            raise ValueError('unknown bucket object')
        runs.add(segments[0])
    if len(runs) > MAX_RUNS:
        raise ValueError('too many runs')
    with tempfile.TemporaryDirectory(prefix='backup-audit-') as tmp:
        root = Path(tmp)
        times = []
        for run in sorted(runs):
            entries, timestamp = confirmed(run, objects, secret, signer, root, require_v3=True)
            times.append(timestamp)
            verify_parts(run, entries, root)
        if len(set(times)) != len(times) or any(t >= datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ') for t in times):
            raise ValueError('ambiguous or non-monotonic creation time')
        if inventory() != objects:
            raise ValueError('inventory changed during audit')


def retrieve(run, destination, egress_budget, secret, signer):
    if not RUN.fullmatch(run) or len(secret) < 32:
        raise ValueError('invalid run or key')
    # A list response is not provider-bounded; this is an estimate, not a network cap.
    if egress_budget < archive.MAX_TOTAL + 2 * (MANIFEST_LIMIT + SIGNATURE_LIMIT) + MARKER_LIMIT + NETWORK_ALLOWANCE:
        raise ValueError('insufficient egress budget')
    destination = Path(destination).absolute()
    parent, name = archive.paths(destination)
    try:
        with tempfile.TemporaryDirectory(dir=f'/proc/{os.getpid()}/fd/{parent}', prefix='.retrieve-') as tmp:
            root = Path(tmp)
            objects = inventory()
            confirmed(run, objects, secret, signer, root)
            base = PREFIX + run + '/'
            manifest = get(base + 'manifest.json', objects[base + 'manifest.json'], root)
            sig = get(base + 'manifest.sig', objects[base + 'manifest.sig'], root)
            archive.verify_signature(manifest, sig, signer, root)
            entries = validate_manifest(manifest)
            parts = root / 'parts'
            parts.mkdir(mode=0o700)
            (parts / 'manifest.json').write_bytes(manifest)
            (parts / 'manifest.sig').write_bytes(sig)
            for entry in entries:
                data = get(base + entry['name'], entry['size'], root)
                if archive.digest(data) != entry['sha256']:
                    raise ValueError('part mismatch')
                (parts / entry['name']).write_bytes(data)
            archive.no_replace(parts, name, parent)
    finally:
        os.close(parent)


def main():
    try:
        if len(sys.argv) not in (2, 4) or (len(sys.argv) == 4 and sys.argv[1] != 'retrieve'):
            raise ValueError('expected archive directory or retrieve RUN DIRECTORY')
        endpoint = os.environ['BACKUP_S3_ENDPOINT']
        match = re.fullmatch(r'https://s3\.([a-z0-9-]+)\.backblazeb2\.com/?', endpoint)
        if not match or os.environ.get('AWS_DEFAULT_REGION') != match.group(1):
            raise ValueError('invalid endpoint or mismatched region')
        if len(sys.argv) == 2 and sys.argv[1] == 'audit':
            audit(int(os.environ['BACKUP_EGRESS_BUDGET_BYTES']),
                  bytes.fromhex(os.environ['BACKUP_HMAC_KEY_HEX']), os.environ['BACKUP_SIGNER_FINGERPRINT'])
            return
        if len(sys.argv) == 4:
            retrieve(sys.argv[2], sys.argv[3], int(os.environ['BACKUP_EGRESS_BUDGET_BYTES']),
                     bytes.fromhex(os.environ['BACKUP_HMAC_KEY_HEX']), os.environ['BACKUP_SIGNER_FINGERPRINT'])
            return
        publish(sys.argv[1], int(os.environ['BACKUP_TOTAL_BUDGET_BYTES']),
                int(os.environ['BACKUP_NON_BACKUP_RESERVE_BYTES']),
                int(os.environ['BACKUP_EGRESS_BUDGET_BYTES']),
                bytes.fromhex(os.environ['BACKUP_HMAC_KEY_HEX']),
                (os.environ.get('BACKUP_EXCLUSIVE_WRITER_ATTESTED'),
                 os.environ.get('BACKUP_MULTIPART_RESERVE_ATTESTED'),
                 os.environ.get('BACKUP_NO_ROLLBACK_CLOCK_ATTESTED')),
                os.environ['BACKUP_SIGNER_FINGERPRINT'],
                int(os.environ.get('BACKUP_DAILY_RETENTION', '7')),
                int(os.environ.get('BACKUP_WEEKLY_RETENTION', '4')))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f'Backup publication failed ({type(error).__name__}).', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
