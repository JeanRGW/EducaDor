"""Opt-in isolated restore test; starts an unexposed, network-disabled disposable DB."""
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid

from test_archive import ArchiveTest
import archive


@unittest.skipUnless(os.environ.get('BACKUP_DOCKER_TEST') == '1', 'set BACKUP_DOCKER_TEST=1')
class RestoreTest(ArchiveTest):
    def test_disposable_postgres_restore(self):
        name = 'educador-backup-test-' + uuid.uuid4().hex
        subprocess.run(['docker', 'run', '-d', '--name', name, '--network', 'none',
                        '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:16'],
                       check=True, stdout=subprocess.DEVNULL)
        self.addCleanup(lambda: subprocess.run(['docker', 'rm', '-f', name],
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        for _ in range(60):
            ready = subprocess.run(['docker', 'exec', name, 'pg_isready', '-U', 'postgres'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if ready.returncode == 0:
                break
            time.sleep(1)
        else:
            self.fail('disposable database failed to start')
        def sql(database, statement):
            return subprocess.run(['docker', 'exec', '-i', name, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
                                   '-U', 'postgres', '-d', database, '-At'], input=statement,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
        sql('postgres', b'CREATE DATABASE source;')
        sql('postgres', b'CREATE DATABASE restored;')
        sql('source', b"CREATE TABLE proof (value text); INSERT INTO proof VALUES ('restored safely');")
        self.dump.write_bytes(subprocess.check_output(['docker', 'exec', name, 'pg_dump', '-U', 'postgres', 'source']))
        parts = self.root / 'database-parts'
        archive.pack(self.dump, parts, self.fingerprint, self.signer)
        archive.unpack(parts, self.output, self.signer)
        sql('restored', self.output.read_bytes())
        self.assertEqual(sql('restored', b'SELECT value FROM proof;').strip(), b'restored safely')
