import concurrent.futures
import importlib.util
import threading
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

    def sign_manifest(self, data):
        path = self.parts / 'manifest.json'
        path.write_bytes(data)
        subprocess.run(['gpg', '--batch', '--yes', '--local-user', self.signer + '!',
                        '--output', str(self.parts / 'manifest.sig'), '--detach-sign', str(path)],
                       check=True, capture_output=True)

    def test_round_trip_and_no_overwrite(self):
        archive.unpack(self.parts, self.output, self.signer)
        self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())
        with self.assertRaises((ValueError, OSError)):
            archive.unpack(self.parts, self.output, self.signer)

    def test_passphrase_protected_recipient(self):
        passfile = self.root / 'passphrase'
        passfile.write_text('throwaway secret\n')
        passfile.chmod(0o600)
        private_home = self.root / 'private-home'
        private_home.mkdir(mode=0o700)
        private_env = dict(os.environ, GNUPGHOME=str(private_home))
        subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-file', str(passfile),
                        '--quick-generate-key', 'Protected <protected@example.invalid>', 'rsa2048', 'encr', '0'],
                       env=private_env, check=True, capture_output=True)
        keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys'], env=private_env)
        recipient = next(line.split(':')[9] for line in keys.decode().splitlines() if line.startswith('fpr:'))
        public = subprocess.check_output(['gpg', '--export', recipient], env=private_env)
        subprocess.run(['gpg', '--batch', '--import'], input=public, check=True, capture_output=True)
        target = self.root / 'protected-parts'
        archive.pack(self.dump, target, recipient, self.signer)
        signer_public = subprocess.check_output(['gpg', '--export', self.signer])
        subprocess.run(['gpg', '--batch', '--import'], input=signer_public, env=private_env, check=True, capture_output=True)
        subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=private_env, check=True)
        with patch.dict(os.environ, {'GNUPGHOME': str(private_home)}, clear=False):
            with patch.dict(os.environ):
                os.environ.pop('BACKUP_GPG_PASSPHRASE_FILE', None)
                with self.assertRaisesRegex(archive.MissingPassphraseError, 'BACKUP_GPG_PASSPHRASE_FILE'):
                    archive.unpack(target, self.output, self.signer)
            link = self.root / 'pass-link'
            link.symlink_to(passfile)
            for path in (link, passfile):
                if path == passfile:
                    passfile.chmod(0o644)
                with patch.dict(os.environ, {'BACKUP_GPG_PASSPHRASE_FILE': str(path)}):
                    with self.assertRaises((OSError, ValueError)):
                        archive.unpack(target, self.output, self.signer)
            passfile.chmod(0o600)
            with patch.dict(os.environ, {'BACKUP_GPG_PASSPHRASE_FILE': str(passfile)}):
                archive.unpack(target, self.output, self.signer)
            self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())
        subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=private_env, check=True)

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
        self.sign_manifest(json.dumps(manifest).encode())
        with self.assertRaises(archive.MissingPassphraseError):
            archive.unpack(self.parts, self.output, self.signer)
        self.assertFalse(self.output.exists())

    def test_oversize_missing_and_bad_names_fail(self):
        path = self.parts / 'manifest.json'
        original_bytes = path.read_bytes()
        original = json.loads(original_bytes)
        for field, value in [('size', archive.CHUNK + 1), ('name', '../other')]:
            manifest = json.loads(json.dumps(original))
            manifest['parts'][0][field] = value
            self.sign_manifest(json.dumps(manifest).encode())
            with self.assertRaisesRegex(ValueError, 'invalid part metadata'):
                archive.unpack(self.parts, self.output, self.signer)
        self.sign_manifest(original_bytes)
        with patch.object(archive, 'MAX_TOTAL', original['parts'][0]['size'] - 1):
            with self.assertRaisesRegex(ValueError, 'ciphertext exceeds limit'):
                archive.unpack(self.parts, self.output, self.signer)
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

    def test_configured_extra_recipients_cannot_decrypt(self):
        other_home = self.root / 'other-gnupg'
        other_home.mkdir(mode=0o700)
        other_env = dict(os.environ, GNUPGHOME=str(other_home))
        subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
                        'Extra <extra@example.invalid>', 'rsa2048', 'encr', '0'],
                       env=other_env, check=True, capture_output=True)
        keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys'],
                                       env=other_env, stderr=subprocess.DEVNULL).decode()
        extra = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
        public = subprocess.check_output(['gpg', '--export', extra], env=other_env)
        subprocess.run(['gpg', '--batch', '--import'], input=public, check=True, capture_output=True)
        config = Path(os.environ['GNUPGHOME']) / 'gpg.conf'
        config.write_text(f'encrypt-to {extra}\nhidden-encrypt-to {extra}\n')
        # Prove the hostile configuration would otherwise add the extra key.
        control = subprocess.check_output(['gpg', '--batch', '--trust-model', 'always',
                                           '--encrypt', '--recipient', self.fingerprint],
                                          input=b'control', stderr=subprocess.DEVNULL)
        decrypted = subprocess.run(['gpg', '--batch', '--decrypt'], input=control,
                                   env=other_env, capture_output=True)
        self.assertEqual(decrypted.returncode, 0)
        self.assertEqual(decrypted.stdout, b'control')
        target = self.root / 'configured'
        archive.pack(self.dump, target, self.fingerprint, self.signer)
        ciphertext = b''.join((target / item['name']).read_bytes() for item in
                              json.loads((target / 'manifest.json').read_text())['parts'])
        decrypted = subprocess.run(['gpg', '--batch', '--decrypt'], input=ciphertext,
                                   env=other_env, capture_output=True)
        self.assertNotEqual(decrypted.returncode, 0)
        self.assertEqual(decrypted.stdout, b'')
        archive.unpack(target, self.output, self.signer)
        self.assertEqual(self.output.read_bytes(), self.dump.read_bytes())

    def test_compressed_and_ciphertext_stream_limits(self):
        with patch.object(archive, 'MAX_COMPRESSED', 10):
            with self.assertRaisesRegex(ValueError, 'size limit exceeded'):
                archive.pack(self.dump, self.root / 'compressed-limit', self.fingerprint, self.signer)
            with self.assertRaisesRegex(ValueError, 'size limit exceeded'):
                archive.unpack(self.parts, self.output, self.signer)
        # This limit is checked while reading GPG output, not after it has been written.
        with patch.object(archive, 'MAX_TOTAL', 10):
            with self.assertRaisesRegex(ValueError, 'size limit exceeded'):
                archive.pack(self.dump, self.root / 'cipher-limit', self.fingerprint, self.signer)
            with self.assertRaisesRegex(ValueError, 'ciphertext exceeds limit'):
                archive.unpack(self.parts, self.output, self.signer)
        self.assertFalse(self.output.exists())
        self.assertFalse((self.root / 'compressed-limit').exists())
        self.assertFalse((self.root / 'cipher-limit').exists())

    def test_concurrent_publication_never_clobbers(self):
        for mode in ('pack', 'unpack'):
            target = self.root / ('race-' + mode)
            barrier = threading.Barrier(2, timeout=30)
            original = archive.no_replace

            def synchronized(src, dst, parent_fd):
                barrier.wait()
                return original(src, dst, parent_fd)

            def publish():
                try:
                    if mode == 'pack':
                        archive.pack(self.dump, target, self.fingerprint, self.signer)
                    else:
                        archive.unpack(self.parts, target, self.signer)
                    return 'published'
                except FileExistsError:
                    return 'exists'

            with patch.object(archive, 'no_replace', side_effect=synchronized):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    results = list(pool.map(lambda _: publish(), range(2)))
            self.assertCountEqual(results, ['published', 'exists'])
            if mode == 'pack':
                archive.unpack(target, self.root / 'race-verified', self.signer)
                self.assertEqual((self.root / 'race-verified').read_bytes(), self.dump.read_bytes())
            else:
                self.assertEqual(target.read_bytes(), self.dump.read_bytes())

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
