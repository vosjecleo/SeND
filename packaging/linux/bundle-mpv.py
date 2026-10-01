#!/usr/bin/env python3
"""Bundle Debian's mpv dependency closure, without replacing the desktop stack.

Private RUNPATHs keep media/TLS libraries out of the launcher's global library
path. The loader, libc, GPU drivers and host GTK/session libraries stay native.
Debian copyright files stay inside; matching sources are a separate download.
"""
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys


HOST = re.compile(
    r"^(ld-linux|lib(c|m|dl|pthread|rt|resolv|util|anl)\.so|"
    r"lib(stdc\+\+|gcc_s)\.so|lib(EGL|GL|GLX|GLdispatch|OpenGL|vulkan|"
    r"drm[^.]*|gbm|wayland[^.]*|xkbcommon[^.]*|X11|Xau|Xdmcp|Xext|"
    r"Xrender|Xfixes|Xrandr|Xi|Xcursor|Xinerama|Xcomposite|Xdamage|xcb)\.so|"
    r"lib(glib-2.0|gobject-2.0|gio-2.0|gmodule-2.0|gthread-2.0|"
    r"gtk-3|gdk-3|gdk_pixbuf-2.0|atk-1.0|atk-bridge-2.0|atspi|"
    r"cairo[^.]*|pango[^/]*|fontconfig|"
    r"freetype|harfbuzz[^.]*|pulse[^.]*|pipewire-0\.3|spa-0\.2|"
    r"asound|dbus-1|systemd|udev)\.so)"
)


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def dependencies(output):
    result = {}
    for line in output.splitlines():
        if '=> not found' in line:
            raise RuntimeError(f'Unresolved media dependency: {line.strip()}')
        match = re.match(r'\s*(\S+) => (/\S+) \(', line)
        if match:
            result[match[1]] = pathlib.Path(match[2])
    return result


def package_for(path):
    candidates = [str(path), str(path.resolve())]
    if str(path).startswith('/usr/lib/'):
        candidates.append(str(path)[4:])
    for candidate in candidates:
        result = subprocess.run(['dpkg-query', '-S', candidate],
                                capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.split(': ', 1)[0]
    raise RuntimeError(f'No Debian source provenance for {path}')


def bundle(appdir, sources_dir):
    library_dir = appdir / 'usr/lib/deltiecord/lib'
    if not library_dir.is_dir():
        raise RuntimeError('Build the AppDir first')
    cache = run('ldconfig', '-p')
    match = re.search(r'libmpv\.so\.2 .* => (\S+)', cache)
    if not match:
        raise RuntimeError('Build AppImages on Debian 12 with libmpv-dev installed')
    root = pathlib.Path(match[1])
    closure = dependencies(run('ldd', str(root)))
    closure['libmpv.so.2'] = root
    # Stop traversal at host libraries, rather than bundling GTK's dependencies.
    selected = {}
    pending = ['libmpv.so.2']
    while pending:
        soname = pending.pop()
        if soname in selected or HOST.match(soname):
            continue
        path = closure.get(soname)
        if path is None:
            raise RuntimeError(f'Unresolved media dependency: {soname}')
        selected[soname] = path
        pending.extend(run('patchelf', '--print-needed', str(path)).splitlines())
    private = library_dir / 'mpv-runtime'
    private.mkdir()
    docs = appdir / 'usr/share/doc/deltiecord/mpv-runtime'
    sources_dir.mkdir(parents=True, exist_ok=True)
    manifest = []
    sources = set()
    for soname, path in sorted(selected.items()):
        destination = library_dir / soname if soname == 'libmpv.so.2' else private / soname
        shutil.copy2(path.resolve(), destination)
        subprocess.check_call(['patchelf', '--set-rpath',
                               '$ORIGIN/mpv-runtime' if soname == 'libmpv.so.2' else '$ORIGIN',
                               str(destination)])
        package = package_for(path)
        source, version = run('dpkg-query', '-W', '-f=${source:Package}\t${source:Version}', package).split('\t')
        sources.add((source, version))
        copyright_file = pathlib.Path('/usr/share/doc') / package.split(':')[0] / 'copyright'
        shutil.copy2(copyright_file, docs / (package.replace(':', '_') + '.copyright'))
        manifest.append({'library': soname, 'binary_package': package,
                         'source_package': source, 'source_version': version,
                         'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    # Match exact source versions, fail closed rather than shipping undocumented
    # binary dependencies. APT authenticates the archive indexes/checksums.
    for source, version in sorted(sources):
        subprocess.check_call(['apt-get', 'source', '--download-only', '--only-source',
                               f'{source}={version}'], cwd=sources_dir)
    (docs / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # This also checks the private RUNPATH closure before compression.
    dependencies(run('ldd', str(library_dir / 'libmpv.so.2')))
    print(f'Bundled libmpv and {len(manifest)-1} media libraries with corresponding sources')


if __name__ == '__main__':
    bundle(pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve())
