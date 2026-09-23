import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'web_deploy', Path(__file__).parents[1] / 'packaging' / 'deploy-web.py')
deployment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deployment)


class WebDeploymentTests(unittest.TestCase):
    def archive(self, path, unsafe=None):
        with tarfile.open(path, 'w:gz') as bundle:
            files = {'index.html': b'app', 'main.dart.js': b'app', 'sw.js': b'app',
                     'browser_bridge.js': b'app', 'pkg/vodozemac_bindings_dart_bg.wasm': b'app',
                     'version.json': json.dumps({'version': '0.9.30', 'build_number': '99'}).encode()}
            for name, body in files.items():
                member = tarfile.TarInfo(name)
                member.size = len(body)
                bundle.addfile(member, io.BytesIO(body))
            if unsafe:
                bundle.addfile(unsafe, io.BytesIO(b''))

    def test_atomic_selection_and_repeat_deployment(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / 'web.tar.gz'
            self.archive(archive)
            for _ in range(2):
                deployment.deploy(archive, root / 'web', '0.9.30+99')
            self.assertEqual((root / 'web/current/index.html').read_bytes(), b'app')
            self.assertTrue((root / 'web/current').is_symlink())

    def test_paths_and_links_are_rejected_without_selecting(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('evil', tarfile.SYMTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = '/etc/passwd'
                archive = root / 'bad.tar.gz'
                self.archive(archive, member)
                with self.assertRaises(ValueError):
                    deployment.deploy(archive, root / 'web', '0.9.30+99')
                self.assertFalse((root / 'web/current').exists())
