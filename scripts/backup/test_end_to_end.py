import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import archive
import publish
from test_archive import ArchiveTest


class EndToEndTest(ArchiveTest):
    def test_signed_publish_retrieve_unpack_and_tamper(self):
        objects = {}
        def inventory():
            return {key: len(value) for key, value in objects.items()}
        def put(key, path):
            objects[key] = Path(path).read_bytes()
        def get(key, size, root):
            data = objects[key]
            if len(data) != size:
                raise ValueError('size mismatch')
            return data
        with patch.object(publish, 'inventory', inventory), patch.object(publish, 'put', put), patch.object(publish, 'get', get):
            secret = b'x' * 32
            publish.publish(self.parts, 100000, 100, 32_000_000, secret, ('true', 'true', 'true'), self.signer)
            run = next(iter(objects)).split('/')[2]
            target = self.root / 'retrieved'
            def retrieve():
                publish.retrieve(run, target, 620_000_000, secret, self.signer)
            retrieve()
            archive.unpack(target, self.output, self.signer)
            self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())
            import shutil
            shutil.rmtree(target)
            sigkey = publish.PREFIX + run + '/manifest.sig'
            sig = objects.pop(sigkey)
            with self.assertRaises(ValueError):
                retrieve()
            objects[sigkey] = sig
            partkey = publish.PREFIX + run + '/0000.gpgpart'
            original_part = objects[partkey]
            objects[partkey] = bytes([original_part[0] ^ 1]) + original_part[1:]
            with self.assertRaises(ValueError):
                retrieve()
            self.assertFalse(target.exists())
            objects[partkey] = original_part
            # Even a forged marker with a known HMAC key cannot substitute a new signer.
            manifestkey = publish.PREFIX + run + '/manifest.json'
            markerkey = publish.PREFIX + run + '/complete.json'
            subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
                            'Attacker <attacker@example.invalid>', 'ed25519', 'sign', '0'],
                           check=True, capture_output=True)
            keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys', 'attacker@example.invalid'], stderr=subprocess.DEVNULL).decode()
            attacker = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
            forged = self.root / 'forged'
            subprocess.run(['gpg', '--batch', '--local-user', attacker + '!', '--output', str(forged),
                            '--detach-sign', str(self.parts / 'manifest.json')], check=True, capture_output=True)
            objects[sigkey] = forged.read_bytes()
            mh, sh = archive.digest(objects[manifestkey]), archive.digest(objects[sigkey])
            objects[markerkey] = json.dumps({'version': 2, 'manifest_sha256': mh, 'signature_sha256': sh,
                                             'hmac_sha256': publish.signature(secret, run, mh, sh)}).encode()
            with self.assertRaises(ValueError):
                retrieve()
            self.assertFalse(target.exists())
