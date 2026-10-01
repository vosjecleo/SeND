#!/usr/bin/env python3
"""Audit every application ELF, not only mpv. Keep the host ABI/driver boundary.

New libraries live on the application's library path so Flutter/plugins can
resolve them too. Existing private mpv libraries and application bytes stay intact.
"""
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import hashlib
import re

spec = importlib.util.spec_from_file_location(
    'mpv', pathlib.Path(__file__).with_name('bundle-mpv.py'))
mpv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mpv)

HOST_PIPEWIRE = re.compile(r'lib(?:pipewire-0\.3|spa-0\.2)\.so(?:\..*)?')
HOST_MODULE_LIBRARIES = re.compile(r'lib(?:pipewire-0\.3|spa-0\.2|rsvg-2)\.so(?:\..*)?')


def remove_host_module_libraries(appdir):
    """Keep dynamically loaded host audio/icon modules with their own libraries."""
    removed = set()
    for path in (appdir / 'usr/lib/deltiecord/lib').rglob('*'):
        if (path.is_file() or path.is_symlink()) and HOST_MODULE_LIBRARIES.fullmatch(path.name):
            removed.add(path.name)
            path.unlink()
    for path in (appdir / 'usr/share/doc/deltiecord').glob('*/manifest.json'):
        entries = json.loads(path.read_text())
        entries = [entry for entry in entries if not HOST_MODULE_LIBRARIES.fullmatch(entry['library'])]
        path.write_text(json.dumps(entries, indent=2) + '\n')
    return removed


def elf_files(root):
    for path in root.rglob('*'):
        if path.is_file():
            with path.open('rb') as stream:
                if stream.read(4) == b'\x7fELF':
                    yield path


def bundle(appdir, sources):
    if sources.is_relative_to(appdir):
        raise RuntimeError('Source archives must be outside the AppImage')
    removed = remove_host_module_libraries(appdir)
    if removed:
        print('Removed host-owned module libraries: ' + ', '.join(sorted(removed)))
    lib = appdir / 'usr/lib/deltiecord/lib'
    env = dict(os.environ, LD_LIBRARY_PATH=f'{lib}:{lib}/mpv-runtime')
    roots = list(elf_files(appdir / 'usr/lib/deltiecord'))
    queue = list(roots)
    visited = set()
    selected = {}
    public_links = {}
    while queue:
        path = queue.pop().resolve()
        if path in visited:
            continue
        visited.add(path)
        needed = mpv.run('patchelf', '--print-needed', str(path)).splitlines()
        if not needed:
            continue
        resolved = mpv.dependencies(mpv.run('ldd', str(path), env=env))
        for soname in needed:
            if mpv.HOST.match(soname):
                continue
            dependency = resolved.get(soname)
            if dependency is None:
                raise RuntimeError(f'{path.name}: missing {soname}')
            if not dependency.resolve().is_relative_to(appdir):
                selected[soname] = dependency
            elif ((path.parent == lib and path.name != 'libmpv.so.2') or path == appdir / 'usr/lib/deltiecord/deltiecord') and dependency.parent == lib / 'mpv-runtime':
                # A Flutter/plugin direct dependency must be visible on the
                # launcher's path, not only inside mpv's private RUNPATH.
                public_links[soname] = dependency
            queue.append(dependency)
    docs = appdir / 'usr/share/doc/deltiecord/application-runtime'
    docs.mkdir(parents=True, exist_ok=True)
    sources.mkdir(parents=True, exist_ok=True)
    manifest_path = docs / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
    source_packages = set()
    for soname, path in sorted(selected.items()):
        destination = lib / soname
        if destination.exists():
            raise RuntimeError(f'Refusing to replace existing application file: {destination}')
        shutil.copy2(path.resolve(), destination)
        subprocess.check_call(['patchelf', '--set-rpath', '$ORIGIN:$ORIGIN/mpv-runtime', str(destination)])
        package = mpv.package_for(path)
        source, version = mpv.run('dpkg-query', '-W',
                                 '-f=${source:Package}\t${source:Version}', package).split('\t')
        source_packages.add((source, version))
        shutil.copy2(pathlib.Path('/usr/share/doc') / package.split(':')[0] / 'copyright',
                     docs / (package.replace(':', '_') + '.copyright'))
        manifest.append({'library': soname, 'binary_package': package,
                         'source_package': source, 'source_version': version,
                         'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    for source, version in sorted(source_packages):
        subprocess.check_call(['apt-get', 'source', '--download-only', '--only-source',
                               f'{source}={version}'], cwd=sources)
    for soname, path in public_links.items():
        destination = lib / soname
        if not destination.exists():
            # A symlink changes the loader's $ORIGIN to the public directory;
            # retain an independent copy with an explicit private search path.
            shutil.copy2(path, destination)
            subprocess.check_call(['patchelf', '--set-rpath',
                                   '$ORIGIN/mpv-runtime:$ORIGIN', str(destination)])
            manifest.append({'library': soname,
                             'source_manifest': '../mpv-runtime/manifest.json',
                             'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    (docs / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Validate with the actual launcher's path, not the discovery-only path.
    env['LD_LIBRARY_PATH'] = str(lib)
    for root in roots:
        if mpv.run('patchelf', '--print-needed', str(root)):
            try:
                mpv.dependencies(mpv.run('ldd', str(root), env=env))
            except RuntimeError as error:
                raise RuntimeError(f'{root}: {error}') from error
    if not (lib / 'libepoxy.so.0').is_file():
        raise RuntimeError('Flutter graphics loader libepoxy must be bundled')
    for path in lib.rglob('libjack.so*'):
        # A standalone JACK fallback is safe; a bundled PipeWire-JACK adapter
        # would reintroduce coupling to a particular host PipeWire version.
        needed = mpv.run('patchelf', '--print-needed', str(path)).splitlines()
        if any(HOST_PIPEWIRE.fullmatch(name) for name in needed):
            raise RuntimeError('Do not bundle a PipeWire-JACK adapter')
    print(f'Audited {len(roots)} ELF files; added {len(manifest)} application libraries')


if __name__ == '__main__':
    bundle(pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve())
