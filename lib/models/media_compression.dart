enum ImageCompressionPreset {
  original,
  balanced,
  smaller;

  static ImageCompressionPreset parse(Object? value) =>
      values.where((preset) => preset.name == value).firstOrNull ?? balanced;
}

enum VideoCompressionPreset {
  smaller,
  balanced;

  int get targetBitrate => this == smaller ? 1500000 : 4000000;
  int get landscapeWidth => this == smaller ? 1280 : 1920;
  int get landscapeHeight => this == smaller ? 720 : 1080;

  static VideoCompressionPreset parse(Object? value) =>
      values.where((preset) => preset.name == value).firstOrNull ?? balanced;
}

/// Native exporters check before reading their complete output into memory.
/// This is separate from a compression preset, and matches the file allowance.
const maximumPreparedVideoBytes = 512 * 1024 * 1024;
