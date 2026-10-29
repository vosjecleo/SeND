"""Exercise the Flatpak manifest update without downloads or SSH."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('jq'), 'jq is required for manifest updates')
class ReleaseChannelsTest(unittest.TestCase):
    def update(self, data):
        script = (ROOT / 'packaging/publish-flatpak.sh').read_text()
        expression = re.search(r"--arg release \"\$release_id\" '(.*?)' \"\$root/releases.json\"", script, re.S)[1]
        result = subprocess.run(['jq', '--arg', 'name', 'SeND-0.9.42+134-linux-x86_64.flatpak',
                                 '--arg', 'hash', 'a' * 64, '--argjson', 'size', '1024',
                                 '--arg', 'release', '0.9.42+134', expression],
                                input=json.dumps(data), text=True, capture_output=True, check=True)
        return json.loads(result.stdout)

    def fixture(self):
        return {'version': '0.9.42', 'build': 134,
                'stable_version': '0.9.42', 'stable_build': 134,
                'platforms': {'linux': {'latest': [{'name': 'appimage'}], 'stable': [{'name': 'appimage'}]}}}

    def test_matching_stable_release_gets_flatpak_too(self):
        updated = self.update(self.fixture())
        linux = updated['platforms']['linux']
        self.assertEqual(linux['latest'], linux['stable'])
        self.assertEqual(len(linux['stable']), 2)
        self.assertEqual(linux['stable'][-1]['size'], 1024)
        self.assertEqual(self.update(updated), updated)

    def test_older_stable_channel_is_not_promoted(self):
        data = self.fixture()
        data['stable_build'] = 132
        updated = self.update(data)
        self.assertEqual(updated['platforms']['linux']['stable'], data['platforms']['linux']['stable'])
        self.assertEqual(len(updated['platforms']['linux']['latest']), 2)

    def test_no_stable_channel_is_not_created(self):
        data = self.fixture()
        del data['stable_version'], data['stable_build']
        del data['platforms']['linux']['stable']
        self.assertNotIn('stable', self.update(data)['platforms']['linux'])

    def test_latest_only_build_keeps_development_appstream_metadata(self):
        root = ET.parse(ROOT / 'packaging/flatpak/net.deltie.deltiecord.metainfo.xml').getroot()
        release = root.find('./releases/release[@version="0.9.42+134"]')
        self.assertIsNotNone(release)
        self.assertEqual(release.get('type'), 'development')


if __name__ == '__main__':
    unittest.main()
