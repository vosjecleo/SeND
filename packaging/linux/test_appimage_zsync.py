import importlib.util
import pathlib
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'sidecar', pathlib.Path(__file__).with_name('prepare-appimage-zsync.py'))
sidecar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sidecar)


class AppImageSidecarTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('zsyncmake'), 'zsyncmake is not installed')
    def test_generator_sidecar_is_created_in_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            output = root / 'dist'
            output.mkdir()
            image = output / 'sample.AppImage'
            image.write_bytes(b'fixture' * 4096)
            subprocess.run(['zsyncmake', str(image), '-u', image.name],
                           cwd=output, check=True, capture_output=True)
            control = output / (image.name + '.zsync')
            self.assertTrue(control.is_file())
            finalized = sidecar.finalize(control.read_bytes(),
                'SeND-0.9.39+129-linux-appimage-x86_64.AppImage')
            self.assertIn(b'URL: https://deltie.net/SeND/', finalized)

    def test_rename_keeps_block_records_and_uses_versioned_mirror_url(self):
        records = bytes(range(256))
        data = (b'zsync: 0.6.2\nFilename: old.AppImage\nLength: 4096\n'
                b'URL: old.AppImage\n\n' + records)
        name = 'SeND-0.9.39+128-linux-appimage-x86_64.AppImage'
        result = sidecar.finalize(data, name)
        header, actual = result.split(b'\n\n', 1)
        self.assertEqual(actual, records)
        self.assertIn(f'Filename: {name}'.encode(), header)
        self.assertIn(f'URL: https://deltie.net/SeND/{name}'.encode(), header)
        self.assertNotIn(b'old.AppImage', header)

    def test_path_traversal_and_non_control_files_rejected(self):
        with self.assertRaises(ValueError):
            sidecar.finalize(b'zsync: 0.6.2\n\n', '../bad.AppImage')
        with self.assertRaises(ValueError):
            sidecar.finalize(b'bad\n\n', 'SeND-0.9.39+128-linux-appimage-x86_64.AppImage')
