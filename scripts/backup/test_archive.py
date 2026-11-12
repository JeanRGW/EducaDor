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
        subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
                        'Signer Test <signer@example.invalid>', 'ed25519', 'sign', '0'],
                       check=True, capture_output=True)
        keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys', 'signer@example.invalid'], stderr=subprocess.DEVNULL).decode()
        self.signer = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
        self.dump = self.root / 'input'
        self.dump.write_bytes(b'example database dump' * 100)
        self.parts = self.root / 'parts'
        self.output = self.root / 'output'
        archive.pack(self.dump, self.parts, self.fingerprint, self.signer)

    def test_round_trip_and_no_overwrite(self):
        archive.unpack(self.parts, self.output, self.signer)
        self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())
        with self.assertRaises((ValueError, OSError)):
            archive.unpack(self.parts, self.output, self.signer)

    def test_tamper_and_truncation(self):
        part = self.parts / '0000.gpgpart'
        original = part.read_bytes()
        for data in (original[:-1], bytes([original[0] ^ 1]) + original[1:]):
            part.write_bytes(data)
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                archive.unpack(self.parts, self.output, self.signer)
            self.assertFalse(self.output.exists())

    def test_ciphertext_authentication_even_if_hash_replaced(self):
        part = self.parts / '0000.gpgpart'
        data = bytearray(part.read_bytes())
        data[-10] ^= 1
        part.write_bytes(data)
        manifest = json.loads((self.parts / 'manifest.json').read_text())
        manifest['parts'][0]['sha256'] = archive.digest(data)
        (self.parts / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
            archive.unpack(self.parts, self.output, self.signer)
        self.assertFalse(self.output.exists())

    def test_oversize_missing_and_bad_names_fail(self):
        path = self.parts / 'manifest.json'
        original_bytes = path.read_bytes()
        original = json.loads(original_bytes)
        for field, value in [('size', archive.CHUNK + 1), ('name', '../other')]:
            manifest = json.loads(json.dumps(original))
            manifest['parts'][0][field] = value
            path.write_text(json.dumps(manifest))
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                archive.unpack(self.parts, self.output, self.signer)
        path.write_bytes(original_bytes)
        (self.parts / '0000.gpgpart').unlink()
        with self.assertRaises(OSError):
            archive.unpack(self.parts, self.output, self.signer)
        self.assertFalse(self.output.exists())

    def test_untrusted_signer_and_signature(self):
        with self.assertRaises(ValueError):
            archive.unpack(self.parts, self.output, self.fingerprint)
        sig = self.parts / 'manifest.sig'
        sig.write_bytes(b'invalid')
        with self.assertRaises(subprocess.CalledProcessError):
            archive.unpack(self.parts, self.output, self.signer)
        self.assertFalse(self.output.exists())

    def test_whole_archive_substitution(self):
        other = self.root / 'other'
        archive.pack(self.dump, other, self.fingerprint, self.fingerprint)
        with self.assertRaises(ValueError):
            archive.unpack(other, self.output, self.signer)
        self.assertFalse(self.output.exists())

    def test_limits_and_symlinks(self):
        with patch.object(archive, 'MAX_PLAIN', 100):
            with self.assertRaises(ValueError):
                archive.unpack(self.parts, self.output, self.signer)
            with self.assertRaises(ValueError):
                archive.pack(self.dump, self.root / 'oversize', self.fingerprint, self.signer)
        link = self.root / 'link'
        link.symlink_to(self.parts, target_is_directory=True)
        with self.assertRaises(OSError):
            archive.unpack(link, self.output, self.signer)
        part = self.parts / '0000.gpgpart'
        data = part.read_bytes()
        part.unlink()
        (self.root / 'real').write_bytes(data)
        part.symlink_to(self.root / 'real')
        with self.assertRaises(OSError):
            archive.unpack(self.parts, self.output, self.signer)

    def test_growth_is_bounded(self):
        from io import BytesIO
        with self.assertRaises(ValueError):
            archive.copy_bounded(BytesIO(b'x' * 101), BytesIO(), 100)

    def test_pack_failure_leaves_no_result_or_temp(self):
        target = self.root / 'failed'
        with patch.object(archive, 'MAX_TOTAL', 1):
            with self.assertRaises(ValueError):
                archive.pack(self.dump, target, self.fingerprint, self.signer)
        self.assertFalse(target.exists())
        self.assertFalse(list(self.root.glob('.backup-*')))


if __name__ == '__main__':
    unittest.main()
