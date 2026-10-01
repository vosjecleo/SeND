import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'application', pathlib.Path(__file__).with_name('bundle-application.py'))
application = importlib.util.module_from_spec(spec)
spec.loader.exec_module(application)


class ApplicationRuntimeTest(unittest.TestCase):
    def test_all_elf_files_are_roots_not_only_executable_or_mpv(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'lib').mkdir()
            for name in ('app', 'lib/libflutter.so', 'lib/plugin.so', 'lib/mpv.so'):
                (root / name).write_bytes(b'\x7fELFtest')
            (root / 'image.png').write_bytes(b'\x89PNG')
            self.assertEqual({str(p.relative_to(root)) for p in application.elf_files(root)},
                             {'app', 'lib/libflutter.so', 'lib/plugin.so', 'lib/mpv.so'})

    def test_embedded_sources_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'outside the AppImage'):
            application.bundle(pathlib.Path('/app'), pathlib.Path('/app/sources'))


if __name__ == '__main__':
    unittest.main()
