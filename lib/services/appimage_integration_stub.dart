bool get canIntegrateAppImage => false;
Future<void> integrateAppImage() async =>
    throw UnsupportedError('AppImage integration is Linux only.');
