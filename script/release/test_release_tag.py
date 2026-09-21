"""Verify release tags against an isolated set of approved public keys.

Adapted from dev7a/lnpctl tests/test_release_tag.py. The GnuPG binary is
resolved the way script/release/verify-tag.sh resolves it, because PATH on a
development Mac can lead to MacGPG 2.2, which cannot read a modern keybox.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'verify-tag.sh'


def gpg_program():
    for candidate in ('/opt/homebrew/bin/gpg', 'gpg'):
        found = shutil.which(candidate)
        if found:
            return found
    return None


class TagTests(unittest.TestCase):
    def test_only_approved_signed_annotated_tags_pass(self):
        gpg = gpg_program()
        if gpg is None:
            self.skipTest('no gpg on this machine, so tag verification cannot be exercised')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / 'gpg'
            home.mkdir(mode=0o700)
            env = dict(os.environ, GNUPGHOME=str(home), GIT_CONFIG_NOSYSTEM='1',
                       GIT_CONFIG_GLOBAL=os.devnull, GIT_AUTHOR_NAME='Test',
                       GIT_AUTHOR_EMAIL='test@example.invalid', GIT_COMMITTER_NAME='Test',
                       GIT_COMMITTER_EMAIL='test@example.invalid', GPG_PROGRAM=gpg)

            def run(*args):
                return subprocess.check_output(args, cwd=root, env=env, stderr=subprocess.DEVNULL)

            run('git', 'init', '-q')
            run('git', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'fixture')
            for user in ('Approved <approved@example.invalid>', 'Other <other@example.invalid>'):
                run(gpg, '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                    '--quick-generate-key', user, 'ed25519', 'sign', '1d')
            keys = root / 'approved.asc'
            keys.write_bytes(run(gpg, '--armor', '--export', 'approved@example.invalid'))
            for signer, tag in (('approved@example.invalid', 'v1.0.0'), ('other@example.invalid', 'v1.0.1')):
                run('git', '-c', f'gpg.program={gpg}', '-c', f'user.signingkey={signer}',
                    'tag', '-s', tag, '-m', signer)
            run('git', 'tag', '-a', 'v1.0.2', '-m', 'unsigned')
            run('git', 'tag', 'v1.0.3')
            try:
                for tag, accepted in [('v1.0.0', True), ('v1.0.1', False), ('v1.0.2', False), ('v1.0.3', False)]:
                    with self.subTest(tag=tag):
                        result = subprocess.run(['bash', str(SCRIPT), tag, str(keys)], cwd=root,
                                                env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode == 0, accepted, result.stderr)
            finally:
                # The isolated agent must not outlive its temporary home.
                subprocess.run([str(Path(gpg).with_name('gpgconf')), '--kill', 'gpg-agent'],
                               cwd=root, env=env, check=False,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    unittest.main()
