import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    'bundle_mpv', pathlib.Path(__file__).with_name('bundle-mpv.py'))
mpv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mpv)


class MediaRuntimeTest(unittest.TestCase):
    def test_host_stack_stays_native(self):
        for library in ('libc.so.6', 'libm.so.6', 'libGL.so.1',
                        'libgtk-3.so.0', 'libstdc++.so.6',
                        'libsystemd.so.0', 'libdrm_amdgpu.so.1',
                        'libatk-1.0.so.0', 'libatk-bridge-2.0.so.0',
                        'libpango-1.0.so.0', 'libpangoft2-1.0.so.0',
                        'libpangocairo-1.0.so.0', 'libpipewire-0.3.so.0',
                        'libspa-0.2.so.0'):
            with self.subTest(library=library):
                self.assertIsNotNone(mpv.HOST.match(library))

    def test_media_dependencies_are_not_accidentally_excluded(self):
        for library in ('libmpv.so.2', 'libavcodec.so.59', 'libssl.so.3',
                        'libXss.so.1', 'libass.so.9', 'libxcb-shape.so.0',
                        'libepoxy.so.0', 'libsecret-1.so.0', 'libjack.so.0'):
            with self.subTest(library=library):
                self.assertIsNone(mpv.HOST.match(library))

    def test_parse_resolved_libraries(self):
        self.assertEqual(mpv.dependencies(
            ' linux-vdso.so.1 (0x123)\n'
            ' libmpv.so.2 => /lib/x86_64-linux-gnu/libmpv.so.2 (0x456)\n'
            ' /lib64/ld-linux-x86-64.so.2 (0x789)'),
            {'libmpv.so.2': pathlib.Path('/lib/x86_64-linux-gnu/libmpv.so.2')})

    def test_missing_library_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, 'Unresolved media dependency'):
            mpv.dependencies(' libmpv.so.2 => not found')


if __name__ == '__main__':
    unittest.main()
