import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    'sidecar', pathlib.Path(__file__).with_name('prepare-appimage-zsync.py'))
sidecar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sidecar)


class AppImageSidecarTest(unittest.TestCase):
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
