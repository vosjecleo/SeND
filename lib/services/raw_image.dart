/// Camera RAW is an attachment, not a format for the built-in raster editor.
bool isRawImageFile(String name, String mimeType) {
  const extensions = {
    'raw',
    'dng',
    'cr2',
    'cr3',
    'crw',
    'nef',
    'nrw',
    'arw',
    'srf',
    'sr2',
    'raf',
    'rw2',
    'rwl',
    'orf',
    'pef',
    'ptx',
    'srw',
    'x3f',
    'iiq',
    'kdc',
    'dcr',
    'mos',
    'mrw',
    'erf',
    '3fr',
    'fff',
    'bay',
    'cap',
    'eip',
    'mef',
  };
  final filename = name.trim().toLowerCase();
  if (filename.contains('.') && extensions.contains(filename.split('.').last)) {
    return true;
  }
  final mime = mimeType.split(';').first.trim().toLowerCase();
  return mime == 'image/raw' ||
      mime == 'image/x-raw' ||
      mime == 'image/x-dcraw' ||
      mime == 'application/x-raw-camera-image' ||
      ((mime.startsWith('image/x-') || mime.startsWith('application/x-')) &&
          extensions.contains(mime.split('-').last));
}
