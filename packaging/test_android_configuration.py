"""Check parsed Android policies, not XML whitespace or attribute order."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1] / 'android/app/src/main'
ANDROID = '{http://schemas.android.com/apk/res/android}'


class AndroidConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.application = ET.parse(ROOT / 'AndroidManifest.xml').getroot().find('application')

    def test_shell_profiling_never_enables_application_debugging(self):
        self.assertEqual(self.application.find('profileable').get(ANDROID + 'shell'), 'true')
        self.assertNotEqual(self.application.get(ANDROID + 'debuggable'), 'true')

    def test_each_backup_and_transfer_policy_excludes_every_private_domain(self):
        self.assertEqual(self.application.get(ANDROID + 'allowBackup'), 'false')
        policies = {}
        for attribute in ('fullBackupContent', 'dataExtractionRules'):
            resource = self.application.get(ANDROID + attribute)
            self.assertRegex(resource, r'^@xml/[a-z_]+$')
            policies[attribute] = ET.parse(ROOT / 'res' / (resource[1:] + '.xml')).getroot()
        legacy = policies['fullBackupContent']
        modern = policies['dataExtractionRules']
        self.assertEqual(legacy.tag, 'full-backup-content')
        self.assertEqual(modern.tag, 'data-extraction-rules')
        for policy in (legacy, modern.find('cloud-backup'), modern.find('device-transfer')):
            with self.subTest(policy=policy.tag if policy is not None else 'missing'):
                self.assertIsNotNone(policy)
                self.assertEqual(
                    {node.get('domain') for node in policy.findall('exclude') if node.get('path') == '.'},
                    {'root', 'file', 'database', 'sharedpref', 'external',
                     'device_root', 'device_file', 'device_database', 'device_sharedpref'},
                )
                self.assertEqual(policy.findall('include'), [])

    def test_unifiedpush_broadcasts_target_the_exported_receiver(self):
        receiver = next(node for node in self.application.findall('receiver')
                        if node.get(ANDROID + 'name') == '.DeltiecordPushService')
        self.assertEqual(receiver.get(ANDROID + 'exported'), 'true')
        self.assertNotEqual(receiver.get(ANDROID + 'enabled'), 'false')
        self.assertEqual(
            {node.get(ANDROID + 'name') for node in receiver.findall('./intent-filter/action')},
            {'org.unifiedpush.android.connector.' + action for action in
             ('MESSAGE', 'UNREGISTERED', 'NEW_ENDPOINT', 'REGISTRATION_FAILED', 'REGISTRATION_REFUSED')},
        )

    def test_media_share_types_belong_to_the_matching_activity_actions(self):
        activity = next(node for node in self.application.findall('activity')
                        if node.get(ANDROID + 'name') == '.MainActivity')
        self.assertEqual(activity.get(ANDROID + 'exported'), 'true')
        targets = {}
        for intent in activity.findall('intent-filter'):
            types = {node.get(ANDROID + 'mimeType') for node in intent.findall('data')}
            for action in intent.findall('action'):
                targets.setdefault(action.get(ANDROID + 'name'), set()).update(types)
        self.assertTrue({'text/plain', 'image/*', 'video/*'} <= targets['android.intent.action.SEND'])
        self.assertTrue({'image/*', 'video/*'} <= targets['android.intent.action.SEND_MULTIPLE'])
