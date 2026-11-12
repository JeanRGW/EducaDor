import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('archive', Path(__file__).with_name('archive.py'))
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'GNUPGHOME': str(self.root / 'gnupg')})
        self.env.start()
        self.addCleanup(self.env.stop)
        Path(os.environ['GNUPGHOME']).mkdir(mode=0o700)
        subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
                        'Backup Test <backup@example.invalid>', 'ed25519', 'default', '0'],
                       check=True, capture_output=True)
        keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys'], stderr=subprocess.DEVNULL).decode()
        self.fingerprint = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
        subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-add-key', self.fingerprint,
                        'cv25519', 'encr', '0'], check=True, capture_output=True)
        self.dump = self.root / 'input'
        self.dump.write_bytes(b'example database dump' * 100)
        self.parts = self.root / 'parts'
        self.output = self.root / 'output'
        archive.pack(self.dump, self.parts, self.fingerprint)

    def test_round_trip_and_no_overwrite(self):
        archive.unpack(self.parts, self.output)
        self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())
        with self.assertRaises(ValueError):
            archive.unpack(self.parts, self.output)

    def test_tamper_and_truncation(self):
        part = self.parts / '0000.gpgpart'
        original = part.read_bytes()
        for data in (original[:-1], bytes([original[0] ^ 1]) + original[1:]):
            part.write_bytes(data)
            with self.assertRaises(ValueError):
                archive.unpack(self.parts, self.output)
            self.assertFalse(self.output.exists())

    def test_ciphertext_authentication_even_if_hash_replaced(self):
        part = self.parts / '0000.gpgpart'
        data = bytearray(part.read_bytes())
        data[-10] ^= 1
        part.write_bytes(data)
        manifest = json.loads((self.parts / 'manifest.json').read_text())
        manifest['parts'][0]['sha256'] = archive.digest(data)
        (self.parts / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises(subprocess.CalledProcessError):
            archive.unpack(self.parts, self.output)
        self.assertFalse(self.output.exists())

    def test_oversize_missing_and_bad_names_fail(self):
        path = self.parts / 'manifest.json'
        original = json.loads(path.read_text())
        for field, value in [('size', archive.CHUNK + 1), ('name', '../other')]:
            manifest = json.loads(json.dumps(original))
            manifest['parts'][0][field] = value
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                archive.unpack(self.parts, self.output)
        path.write_text(json.dumps(original))
        (self.parts / '0000.gpgpart').unlink()
        with self.assertRaises(OSError):
            archive.unpack(self.parts, self.output)
        self.assertFalse(self.output.exists())

    def test_pack_failure_leaves_no_result_or_temp(self):
        target = self.root / 'failed'
        with patch.object(archive, 'MAX_TOTAL', 1):
            with self.assertRaises(ValueError):
                archive.pack(self.dump, target, self.fingerprint)
        self.assertFalse(target.exists())
        self.assertFalse(list(self.root.glob('.backup-*')))


if __name__ == '__main__':
    unittest.main()
