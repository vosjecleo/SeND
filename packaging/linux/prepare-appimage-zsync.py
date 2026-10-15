#!/usr/bin/env python3
"""Finalize versioned filenames without changing the binary block checksums."""
import pathlib
import re
import sys


def finalize(data, filename):
    if not re.fullmatch(r'SeND-[0-9.]+\+[0-9]+-linux-appimage-x86_64\.AppImage', filename):
        raise ValueError('Unexpected AppImage filename')
    header, records = data.split(b'\n\n', 1)
    lines = header.decode('ascii').splitlines()
    if not lines[0].startswith('zsync: '):
        raise ValueError('Missing zsync header')
    lines = [line for line in lines if not line.startswith(('Filename:', 'URL:'))]
    lines += [f'Filename: {filename}', f'URL: https://deltie.net/SeND/{filename}']
    return ('\n'.join(lines) + '\n\n').encode('ascii') + records


if __name__ == '__main__':
    source = pathlib.Path(sys.argv[1])
    target = source.parent / (sys.argv[2] + '.zsync')
    target.write_bytes(finalize(source.read_bytes(), sys.argv[2]))
    if target != source:
        source.unlink()
