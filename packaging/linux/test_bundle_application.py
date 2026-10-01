import importlib.util
import pathlib
import tempfile
import unittest
import json

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

    def test_remove_only_host_module_libraries_and_update_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            lib = root / 'usr/lib/deltiecord/lib/mpv-runtime'
            lib.mkdir(parents=True)
            names = ['libpipewire-0.3.so.0', 'libspa-0.2.so.0', 'librsvg-2.so.2', 'libjack.so.0', 'libmpv.so.2']
            for name in names:
                (lib / name).write_bytes(b'ELF placeholder')
            docs = root / 'usr/share/doc/deltiecord/mpv-runtime'
            docs.mkdir(parents=True)
            manifest = docs / 'manifest.json'
            manifest.write_text(json.dumps([{'library': name} for name in names]))
            removed = application.remove_host_module_libraries(root)
            self.assertEqual(removed, set(names[:3]))
            self.assertEqual({p.name for p in lib.iterdir()}, set(names[3:]))
            self.assertEqual(json.loads(manifest.read_text()), [{'library': name} for name in names[3:]])


if __name__ == '__main__':
    unittest.main()
