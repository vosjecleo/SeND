enum ImageCompressionPreset {
  original,
  balanced,
  smaller;

  static ImageCompressionPreset parse(Object? value) =>
      values.where((preset) => preset.name == value).firstOrNull ?? original;
}

enum VideoCompressionPreset {
  smaller,
  balanced;

  int get targetBytes => (this == smaller ? 10 : 20) * 1024 * 1024;
  int get maximumBytes => (this == smaller ? 12 : 24) * 1024 * 1024;
  int get maximumBitrate => this == smaller ? 1500000 : 4000000;
  int get landscapeWidth => this == smaller ? 1280 : 1920;
  int get landscapeHeight => this == smaller ? 720 : 1080;

  static VideoCompressionPreset parse(Object? value) =>
      values.where((preset) => preset.name == value).firstOrNull ?? balanced;
}
