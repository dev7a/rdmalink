"""Exercise the release receipt without Xcode, Apple or a real disk image.

script/package_dmg.sh calls script/release/receipt.sh for the two files that
travel with a release DMG. Everything it decides — the tag must name the
version, both notarizations must have been accepted, the sum is over the
shipped bytes — is checked here against fixtures, so the logic is covered by
the ordinary test gate and not only by a real two-minute signed build.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'receipt.sh'
IMAGE_BYTES = b'not really a disk image'


class ReceiptTests(unittest.TestCase):
    def run_receipt(self, *, version='0.4.2', tag='v0.4.2', dmg_name=None,
                    app_status='Accepted', image_status='Accepted', write_image=True,
                    sha='a' * 40, tag_object='b' * 40):
        directory = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', directory], check=True))
        root = Path(directory)
        assets = root / 'release-assets'
        assets.mkdir()
        name = dmg_name or f'RDMALink-{version}.dmg'
        if write_image:
            (assets / name).write_bytes(IMAGE_BYTES)
        for which, status in (('app', app_status), ('image', image_status)):
            (root / f'notary-{which}.json').write_text(json.dumps(
                {'id': f'{which}-submission', 'status': status, 'message': 'Processing complete'}))
        env = dict(os.environ, RELEASE_TAG=tag, RELEASE_SHA=sha, RELEASE_TAG_OBJECT=tag_object,
                   VERSION=version, BUILD_NUMBER='7', TEAM_ID='BV5XC39R5P',
                   BUNDLE_IDENTIFIER='com.dev7a.RDMALink', MINIMUM_MACOS='27.0',
                   NOTARY_APP_JSON=str(root / 'notary-app.json'),
                   NOTARY_IMAGE_JSON=str(root / 'notary-image.json'),
                   XCODE_VERSION='Xcode 27.0\nBuild version 27A266a')
        result = subprocess.run(['bash', str(SCRIPT), str(assets), name],
                                env=env, capture_output=True, text=True)
        return result, assets, name

    def test_writes_the_sum_and_the_receipt(self):
        result, assets, name = self.run_receipt()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (assets / 'SHA256SUMS').read_text(),
            hashlib.sha256(IMAGE_BYTES).hexdigest() + '  ' + name + '\n')
        receipt = json.loads((assets / 'release.json').read_text())
        self.assertEqual(receipt['tag'], 'v0.4.2')
        self.assertEqual(receipt['commit'], 'a' * 40)
        self.assertEqual(receipt['tag_object'], 'b' * 40)
        self.assertEqual(receipt['version'], '0.4.2')
        self.assertEqual(receipt['build'], '7')
        self.assertEqual(receipt['asset'], name)
        self.assertEqual(receipt['architecture'], 'arm64')
        self.assertEqual(receipt['minimum_macos'], '27.0')
        self.assertEqual(receipt['team_id'], 'BV5XC39R5P')
        self.assertEqual(receipt['bundle_identifier'], 'com.dev7a.RDMALink')
        self.assertEqual(receipt['notarization']['app']['status'], 'Accepted')
        self.assertEqual(receipt['notarization']['image']['status'], 'Accepted')
        self.assertIn('27A266a', receipt['xcode'])

    def test_refusals_write_nothing(self):
        cases = {
            'tag names another version': dict(tag='v0.4.3'),
            'tag is not a release tag': dict(tag='v0.4.2-rc1', version='0.4.2-rc1'),
            'commit is not a hash': dict(sha='HEAD'),
            'tag object is not a hash': dict(tag_object='refs/tags/v0.4.2'),
            'image is named something else': dict(dmg_name='RDMALink.dmg'),
            'image is missing': dict(write_image=False),
            'the app was not notarized': dict(app_status='Invalid'),
            'the image was not notarized': dict(image_status='Rejected'),
        }
        for name, arguments in cases.items():
            with self.subTest(case=name):
                result, assets, _ = self.run_receipt(**arguments)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse((assets / 'SHA256SUMS').exists())
                self.assertFalse((assets / 'release.json').exists())


if __name__ == '__main__':
    unittest.main()
