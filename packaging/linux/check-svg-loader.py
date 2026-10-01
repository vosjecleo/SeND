"""Exercise host SVG decoding after mpv/FFmpeg has loaded its dependencies."""
import ctypes
import os
import pathlib
import tempfile

lib = pathlib.Path(os.environ['APPDIR']) / 'usr/lib/deltiecord/lib'
# Same process/global ELF namespace as the app's media plugin and GTK.
ctypes.CDLL(str(lib / 'libmpv.so.2'), mode=ctypes.RTLD_GLOBAL)
# Fail on the exact undefined symbol before GTK turns it into an assertion.
ctypes.CDLL(os.environ['SVG_TEST_LOADER'], mode=os.RTLD_NOW)

class GError(ctypes.Structure):
    _fields_ = [('domain', ctypes.c_uint), ('code', ctypes.c_int),
                ('message', ctypes.c_char_p)]

pixbuf = ctypes.CDLL('libgdk_pixbuf-2.0.so.0')
pixbuf.gdk_pixbuf_new_from_file.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.POINTER(GError))]
pixbuf.gdk_pixbuf_new_from_file.restype = ctypes.c_void_p
pixbuf.gdk_pixbuf_get_width.argtypes = [ctypes.c_void_p]
pixbuf.gdk_pixbuf_get_height.argtypes = [ctypes.c_void_p]
gobject = ctypes.CDLL('libgobject-2.0.so.0')
gobject.g_object_unref.argtypes = [ctypes.c_void_p]
with tempfile.TemporaryDirectory() as directory:
    svg = pathlib.Path(directory) / 'icon.svg'
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">'
                   '<rect width="16" height="16" fill="blue"/></svg>')
    error = ctypes.POINTER(GError)()
    image = pixbuf.gdk_pixbuf_new_from_file(os.fsencode(svg), ctypes.byref(error))
    if not image:
        raise RuntimeError(error.contents.message.decode() if error else 'SVG decode failed')
    assert pixbuf.gdk_pixbuf_get_width(image) == 16
    assert pixbuf.gdk_pixbuf_get_height(image) == 16
    gobject.g_object_unref(image)
print('Host SVG loader decoded a 16x16 icon after mpv initialization')
